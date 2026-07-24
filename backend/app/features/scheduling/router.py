"""Scheduling API router.

Endpoints (all require Depends(get_current_user)):
  POST   /api/v1/scheduling/availability             — multi-contractor availability query
  GET    /api/v1/scheduling/availability/{id}        — single-contractor availability
  POST   /api/v1/scheduling/bookings                 — create single-day booking
  POST   /api/v1/scheduling/bookings/multi-day       — create multi-day booking (all-or-nothing)
  GET    /api/v1/scheduling/bookings                 — list bookings with optional filters
  DELETE /api/v1/scheduling/bookings/{id}            — soft-delete a booking
  PATCH  /api/v1/scheduling/bookings/{id}/reschedule — move booking to new time
  POST   /api/v1/scheduling/conflicts                — read-only conflict check
  POST   /api/v1/scheduling/suggest-dates            — suggest multi-day date combinations
  PUT    /api/v1/scheduling/schedules/{id}/weekly/{dow}    — replace weekly schedule for a day
  PUT    /api/v1/scheduling/schedules/{id}/overrides/{date} — replace date overrides
  GET    /api/v1/scheduling/schedules/{id}/weekly          — get full weekly schedule
  GET    /api/v1/scheduling/schedules/{id}/overrides       — get date overrides in range

Design: thin router functions delegate all business logic to SchedulingService.
Custom domain (not standard CRUD) so CRUDRouter mixin is NOT used per CLAUDE.md guidance.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator, Iterator
from contextlib import contextmanager
from datetime import date

import httpx
from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.core.tenant import get_current_tenant_id
from app.features.scheduling.schemas import (
    AvailabilityRequest,
    AvailabilityResponse,
    BookingCreate,
    BookingResponse,
    ConflictCheckRequest,
    ConflictDetail,
    DateOverrideCreate,
    DateSuggestion,
    MultiDayBookingCreate,
    RescheduleRequest,
    SuggestDatesRequest,
    WeeklyScheduleCreate,
)
from app.features.scheduling.service import (
    BookingNotFoundError,
    BookingTooShortError,
    OutsideWorkingHoursError,
    SchedulingConflictError,
    SchedulingService,
)
from app.features.scheduling.travel.cache import (
    CachedTravelTimeProvider,
    TravelTimeCacheService,
)
from app.features.scheduling.travel.ors_provider import OpenRouteServiceProvider

router = APIRouter(prefix="/scheduling", tags=["scheduling"])


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------


async def _get_http_client() -> AsyncGenerator[httpx.AsyncClient, None]:
    """Yield an httpx.AsyncClient that is properly closed after the request."""
    async with httpx.AsyncClient() as client:
        yield client


async def get_scheduling_service(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    http_client: httpx.AsyncClient = Depends(_get_http_client),
) -> SchedulingService:
    """FastAPI dependency that constructs a SchedulingService with optional travel provider.

    If ORS_API_KEY is set in environment, injects a CachedTravelTimeProvider backed
    by OpenRouteService so availability calculations include real travel time blocks.
    If ORS_API_KEY is absent, travel_provider=None and travel time is skipped.

    The httpx.AsyncClient is managed by the _get_http_client dependency and closed
    automatically when the request finishes.
    """
    travel_provider = None
    if settings.ors_api_key:
        company_id = get_current_tenant_id()
        ors = OpenRouteServiceProvider(api_key=settings.ors_api_key, client=http_client)
        cache_svc = TravelTimeCacheService(db=db, provider=ors)
        travel_provider = CachedTravelTimeProvider(
            cache_service=cache_svc,
            company_id=company_id,
        )
    return SchedulingService(db=db, travel_provider=travel_provider)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _booking_to_response(booking) -> BookingResponse:
    """Convert a Booking ORM model to BookingResponse schema.

    Uses model_validate() per CLAUDE.md convention. The BookingResponse
    model_validator(mode='before') handles extracting time_range.lower/upper
    into time_range_start/time_range_end.
    """
    return BookingResponse.model_validate(booking, from_attributes=True)


@contextmanager
def _translate_booking_errors(conflict_message: str) -> Iterator[None]:
    """Map scheduling domain errors raised by a booking operation to HTTP responses.

    conflict_message is the human-friendly text used for SchedulingConflictError,
    which differs per endpoint (single-day / multi-day / reschedule).
    """
    try:
        yield
    except BookingNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except SchedulingConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "message": conflict_message,
                "conflicts": [c.model_dump(mode="json") for c in exc.conflicts],
            },
        ) from exc
    except OutsideWorkingHoursError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"message": str(exc)},
        ) from exc
    except BookingTooShortError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "message": str(exc),
                "requested_minutes": exc.requested_minutes,
                "minimum_minutes": exc.minimum_minutes,
            },
        ) from exc


# ---------------------------------------------------------------------------
# Availability endpoints
# ---------------------------------------------------------------------------


@router.post(
    "/availability",
    response_model=list[AvailabilityResponse],
    summary="Get availability for multiple contractors",
)
async def get_availability(
    request: AvailabilityRequest,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[AvailabilityResponse]:
    """Compute availability for one or more contractors on a specific date.

    Accepts contractor_ids and/or trade_type. If job_site_id is provided,
    results are sorted by distance from the job site (nearest first).
    Returns free windows and blocked intervals for each contractor.
    """
    return await svc.get_available_slots(request)


@router.get(
    "/availability/{contractor_id}",
    response_model=AvailabilityResponse,
    summary="Get availability for a single contractor",
)
async def get_contractor_availability(
    contractor_id: uuid.UUID,
    query_date: date,
    job_site_id: uuid.UUID | None = None,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> AvailabilityResponse:
    """Convenience endpoint: availability for a single contractor on a given date.

    Returns the contractor's free windows and blocked intervals.
    If job_site_id is provided, the response includes distance_km.
    Returns 404 if the contractor has no availability record.
    """
    request = AvailabilityRequest(
        contractor_ids=[contractor_id],
        date=query_date,
        job_site_id=job_site_id,
    )
    results = await svc.get_available_slots(request)
    if not results:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Contractor {contractor_id} not found or has no schedule configured",
        )
    return results[0]


# ---------------------------------------------------------------------------
# Booking endpoints
# ---------------------------------------------------------------------------


@router.post(
    "/bookings",
    response_model=BookingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a single-day booking",
)
async def create_booking(
    booking_data: BookingCreate,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> BookingResponse:
    """Book a single time slot for a contractor.

    Returns 409 if the slot conflicts with an existing booking.
    Returns 422 if the booking is outside working hours or below minimum duration.
    """
    with _translate_booking_errors("Booking conflicts with existing schedule"):
        booking = await svc.book_slot(booking_data)
    return _booking_to_response(booking)


@router.post(
    "/bookings/multi-day",
    response_model=list[BookingResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create a multi-day booking (all-or-nothing)",
)
async def create_multiday_booking(
    booking_data: MultiDayBookingCreate,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[BookingResponse]:
    """Book multiple days for a contractor atomically.

    All days are checked before any are created. If any day conflicts,
    the entire booking is rejected — no partial bookings are created.
    Returns 409 if any day conflicts with an existing booking.
    """
    with _translate_booking_errors("One or more days conflict with existing bookings"):
        bookings = await svc.book_multiday_job(booking_data)
    return [_booking_to_response(b) for b in bookings]


@router.get(
    "/bookings",
    response_model=list[BookingResponse],
    summary="List bookings with optional filters",
)
async def list_bookings(
    contractor_id: uuid.UUID | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
    limit: int = Query(default=100, ge=1, le=1000),
    offset: int = Query(default=0, ge=0),
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[BookingResponse]:
    """List bookings with optional contractor and date range filters.

    If contractor_id is omitted, all bookings for the company are returned.
    date_from and date_to filter bookings that overlap the given range.
    Supports pagination via limit and offset query parameters.
    """
    bookings = await svc.list_bookings(
        contractor_id=contractor_id,
        date_from=date_from,
        date_to=date_to,
        limit=limit,
        offset=offset,
    )
    return [_booking_to_response(b) for b in bookings]


@router.delete(
    "/bookings/{booking_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
    summary="Soft-delete a booking",
)
async def delete_booking(
    booking_id: uuid.UUID,
    current_user: CurrentUser = Depends(get_current_user),
    svc: SchedulingService = Depends(get_scheduling_service),
) -> None:
    """Soft-delete a booking, freeing the contractor's time slot.

    Requires admin role. The booking record is retained with deleted_at set.
    The GIST exclusion constraint WHERE clause excludes deleted bookings
    from conflict checks.
    Returns 404 if the booking is not found or already deleted.
    """
    await require_permission("schedule.delete")(current_user, svc.db)
    deleted = await svc.repository.soft_delete(booking_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Booking {booking_id} not found",
        )


@router.patch(
    "/bookings/{booking_id}/reschedule",
    response_model=BookingResponse,
    summary="Reschedule a booking to a new time slot",
)
async def reschedule_booking(
    booking_id: uuid.UUID,
    reschedule_data: RescheduleRequest,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> BookingResponse:
    """Move an existing booking to a new time slot.

    Atomically soft-deletes the existing booking and creates a new one.
    If the new slot is unavailable, the original booking is restored.
    Returns 409 if the new slot conflicts, 422 if outside working hours.
    Optionally reassigns to a different contractor via contractor_id.
    """
    with _translate_booking_errors("New time slot conflicts with existing bookings"):
        new_booking = await svc.reschedule_booking(
            booking_id=booking_id,
            new_start=reschedule_data.start,
            new_end=reschedule_data.end,
            new_contractor_id=reschedule_data.contractor_id,
        )
    return _booking_to_response(new_booking)


# ---------------------------------------------------------------------------
# Conflict check endpoint
# ---------------------------------------------------------------------------


@router.post(
    "/conflicts",
    response_model=list[ConflictDetail],
    summary="Read-only conflict check",
)
async def check_conflicts(
    request: ConflictCheckRequest,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[ConflictDetail]:
    """Check for booking conflicts without creating any records.

    Returns an empty list if the slot is free, or a list of conflicting
    bookings if the slot is taken. No lock is acquired — this is a read-only
    pre-check for UI use before presenting booking options.
    """
    return await svc.check_conflicts(
        contractor_id=request.contractor_id,
        start=request.start,
        end=request.end,
    )


# ---------------------------------------------------------------------------
# Date suggestion endpoint
# ---------------------------------------------------------------------------


@router.post(
    "/suggest-dates",
    response_model=list[DateSuggestion],
    summary="Suggest date combinations for a multi-day job",
)
async def suggest_dates(
    request: SuggestDatesRequest,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[DateSuggestion]:
    """Suggest available date combinations for a multi-day job.

    Returns up to 5 date combinations where the contractor has sufficient
    free time on each day. Consecutive date combinations are preferred
    over non-consecutive alternatives.
    """
    return await svc.suggest_dates(
        contractor_id=request.contractor_id,
        num_days=request.num_days,
        preferred_start=request.preferred_start,
        duration_hours=request.duration_hours,
        within_days=request.within_days,
    )


# ---------------------------------------------------------------------------
# Schedule management endpoints
# ---------------------------------------------------------------------------


@router.put(
    "/schedules/{contractor_id}/weekly/{day_of_week}",
    response_model=list[dict],
    summary="Replace weekly schedule blocks for a day",
)
async def set_weekly_schedule(
    contractor_id: uuid.UUID,
    day_of_week: int = Path(..., ge=0, le=6, description="Day of week: 0=Monday, 6=Sunday"),
    schedule_data: WeeklyScheduleCreate = ...,
    current_user: CurrentUser = Depends(get_current_user),
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[dict]:
    """Replace all weekly schedule blocks for a contractor's day.

    Requires admin role.
    day_of_week: 0=Monday, 1=Tuesday, ..., 6=Sunday.
    An empty blocks list clears the contractor's schedule for that day.
    Atomically replaces all existing blocks for (contractor_id, day_of_week).
    """
    await require_permission("schedule.edit")(current_user, svc.db)
    created = await svc.set_weekly_schedule(
        contractor_id=contractor_id,
        day_of_week=day_of_week,
        blocks=schedule_data.blocks,
    )
    return [
        {
            "id": str(block.id),
            "contractor_id": str(block.contractor_id),
            "day_of_week": block.day_of_week,
            "block_index": block.block_index,
            "start_time": block.start_time.isoformat(),
            "end_time": block.end_time.isoformat(),
        }
        for block in created
    ]


@router.put(
    "/schedules/{contractor_id}/overrides/{override_date}",
    response_model=list[dict],
    summary="Replace date-specific schedule overrides",
)
async def set_date_override(
    contractor_id: uuid.UUID,
    override_date: date,
    override_data: DateOverrideCreate,
    current_user: CurrentUser = Depends(get_current_user),
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[dict]:
    """Replace all schedule overrides for a contractor's specific date.

    Requires admin role.
    Two modes:
    - is_unavailable=True: marks the entire day as unavailable
    - is_unavailable=False with blocks: custom working hours for the date

    Atomically replaces all existing overrides for (contractor_id, override_date).
    """
    await require_permission("schedule.edit")(current_user, svc.db)
    created = await svc.set_date_override(
        contractor_id=contractor_id,
        override_date=override_date,
        is_unavailable=override_data.is_unavailable,
        blocks=override_data.blocks,
    )
    return [
        {
            "id": str(override.id),
            "contractor_id": str(override.contractor_id),
            "override_date": override.override_date.isoformat(),
            "is_unavailable": override.is_unavailable,
            "block_index": override.block_index,
            "start_time": override.start_time.isoformat() if override.start_time else None,
            "end_time": override.end_time.isoformat() if override.end_time else None,
        }
        for override in created
    ]


@router.get(
    "/schedules/{contractor_id}/weekly",
    response_model=dict,
    summary="Get full weekly schedule for a contractor",
)
async def get_weekly_schedule(
    contractor_id: uuid.UUID,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> dict:
    """Return the contractor's full weekly schedule grouped by day_of_week.

    Returns a dict mapping day_of_week (0-6) to a list of time blocks.
    Days with no schedule entries are omitted from the response.
    """
    return await svc.get_contractor_weekly_schedule(contractor_id)


@router.get(
    "/schedules/{contractor_id}/overrides",
    response_model=list[dict],
    summary="Get date overrides for a contractor in a date range",
)
async def get_date_overrides(
    contractor_id: uuid.UUID,
    date_from: date,
    date_to: date,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[dict]:
    """Return date-specific schedule overrides for a contractor within [date_from, date_to].

    Ordered by override_date then block_index.
    """
    return await svc.get_contractor_date_overrides(
        contractor_id=contractor_id,
        date_from=date_from,
        date_to=date_to,
    )
