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
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.scheduling.schemas import (
    AvailabilityRequest,
    AvailabilityResponse,
    BookingCreate,
    BookingResponse,
    ConflictDetail,
    DateOverrideCreate,
    DateSuggestion,
    MultiDayBookingCreate,
    WeeklyScheduleCreate,
)
from app.features.scheduling.service import (
    BookingTooShortError,
    OutsideWorkingHoursError,
    SchedulingConflictError,
    SchedulingService,
)

router = APIRouter(prefix="/scheduling", tags=["scheduling"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _booking_to_response(booking) -> BookingResponse:
    """Convert a Booking ORM model to BookingResponse schema."""
    return BookingResponse(
        id=booking.id,
        company_id=booking.company_id,
        version=booking.version,
        created_at=booking.created_at,
        updated_at=booking.updated_at,
        deleted_at=booking.deleted_at,
        contractor_id=booking.contractor_id,
        job_id=booking.job_id,
        job_site_id=booking.job_site_id,
        time_range_start=booking.time_range.lower,
        time_range_end=booking.time_range.upper,
        day_index=booking.day_index,
        parent_booking_id=booking.parent_booking_id,
        notes=booking.notes,
    )


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
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[AvailabilityResponse]:
    """Compute availability for one or more contractors on a specific date.

    Accepts contractor_ids and/or trade_type. If job_site_id is provided,
    results are sorted by distance from the job site (nearest first).
    Returns free windows and blocked intervals for each contractor.
    """
    svc = SchedulingService(db)
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
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> AvailabilityResponse:
    """Convenience endpoint: availability for a single contractor on a given date.

    Returns the contractor's free windows and blocked intervals.
    If job_site_id is provided, the response includes distance_km.
    Returns 404 if the contractor has no availability record.
    """
    svc = SchedulingService(db)
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
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> BookingResponse:
    """Book a single time slot for a contractor.

    Returns 409 if the slot conflicts with an existing booking.
    Returns 422 if the booking is outside working hours or below minimum duration.
    """
    svc = SchedulingService(db)
    try:
        booking = await svc.book_slot(booking_data)
    except SchedulingConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "message": "Booking conflicts with existing schedule",
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
    return _booking_to_response(booking)


@router.post(
    "/bookings/multi-day",
    response_model=list[BookingResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create a multi-day booking (all-or-nothing)",
)
async def create_multiday_booking(
    booking_data: MultiDayBookingCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[BookingResponse]:
    """Book multiple days for a contractor atomically.

    All days are checked before any are created. If any day conflicts,
    the entire booking is rejected — no partial bookings are created.
    Returns 409 if any day conflicts with an existing booking.
    """
    svc = SchedulingService(db)
    try:
        bookings = await svc.book_multiday_job(booking_data)
    except SchedulingConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "message": "One or more days conflict with existing bookings",
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
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[BookingResponse]:
    """List bookings with optional contractor and date range filters.

    If contractor_id is omitted, all bookings for the company are returned.
    date_from and date_to filter bookings that overlap the given range.
    """
    from sqlalchemy import func, select

    from app.core.tenant import get_current_tenant_id
    from app.features.scheduling.models import Booking

    company_id = get_current_tenant_id()

    stmt = select(Booking).where(
        Booking.deleted_at.is_(None),
        Booking.company_id == company_id,
    )

    if contractor_id is not None:
        stmt = stmt.where(Booking.contractor_id == contractor_id)

    if date_from is not None:
        range_start = datetime(date_from.year, date_from.month, date_from.day)
        stmt = stmt.where(
            Booking.time_range.op(">>")(func.tstzrange(None, range_start, "(]")).is_(False)
        )

    if date_to is not None:
        from datetime import timedelta

        range_end = datetime(date_to.year, date_to.month, date_to.day) + timedelta(days=1)
        stmt = stmt.where(
            Booking.time_range.op("<<")(func.tstzrange(range_end, None, "[)")).is_(False)
        )

    stmt = stmt.order_by(Booking.time_range)
    result = await db.execute(stmt)
    bookings = list(result.scalars().all())
    return [_booking_to_response(b) for b in bookings]


@router.delete(
    "/bookings/{booking_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
    summary="Soft-delete a booking",
)
async def delete_booking(
    booking_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Soft-delete a booking, freeing the contractor's time slot.

    The booking record is retained with deleted_at set. The GIST exclusion
    constraint WHERE clause excludes deleted bookings from conflict checks.
    Returns 404 if the booking is not found or already deleted.
    """
    svc = SchedulingService(db)
    deleted = await svc.repository.soft_delete(booking_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Booking {booking_id} not found",
        )


class RescheduleRequest(BaseModel):
    """Payload for rescheduling a booking to a new time slot."""

    start: datetime
    end: datetime


@router.patch(
    "/bookings/{booking_id}/reschedule",
    response_model=BookingResponse,
    summary="Reschedule a booking to a new time slot",
)
async def reschedule_booking(
    booking_id: uuid.UUID,
    reschedule_data: RescheduleRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> BookingResponse:
    """Move an existing booking to a new time slot.

    Atomically soft-deletes the existing booking and creates a new one.
    If the new slot is unavailable, the original booking is restored.
    Returns 409 if the new slot conflicts, 422 if outside working hours.
    """
    svc = SchedulingService(db)
    try:
        new_booking = await svc.reschedule_booking(
            booking_id=booking_id,
            new_start=reschedule_data.start,
            new_end=reschedule_data.end,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except SchedulingConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "message": "New time slot conflicts with existing bookings",
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
            detail={"message": str(exc)},
        ) from exc
    return _booking_to_response(new_booking)


# ---------------------------------------------------------------------------
# Conflict check endpoint
# ---------------------------------------------------------------------------


class ConflictCheckRequest(BaseModel):
    """Payload for a read-only conflict check."""

    contractor_id: uuid.UUID
    start: datetime
    end: datetime


@router.post(
    "/conflicts",
    response_model=list[ConflictDetail],
    summary="Read-only conflict check",
)
async def check_conflicts(
    request: ConflictCheckRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ConflictDetail]:
    """Check for booking conflicts without creating any records.

    Returns an empty list if the slot is free, or a list of conflicting
    bookings if the slot is taken. No lock is acquired — this is a read-only
    pre-check for UI use before presenting booking options.
    """
    svc = SchedulingService(db)
    return await svc.check_conflicts(
        contractor_id=request.contractor_id,
        start=request.start,
        end=request.end,
    )


# ---------------------------------------------------------------------------
# Date suggestion endpoint
# ---------------------------------------------------------------------------


class SuggestDatesRequest(BaseModel):
    """Payload for multi-day date suggestion."""

    contractor_id: uuid.UUID
    num_days: int
    preferred_start: date
    duration_hours: float
    within_days: int = 30


@router.post(
    "/suggest-dates",
    response_model=list[DateSuggestion],
    summary="Suggest date combinations for a multi-day job",
)
async def suggest_dates(
    request: SuggestDatesRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[DateSuggestion]:
    """Suggest available date combinations for a multi-day job.

    Returns up to 5 date combinations where the contractor has sufficient
    free time on each day. Consecutive date combinations are preferred
    over non-consecutive alternatives.
    """
    svc = SchedulingService(db)
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
    day_of_week: int,
    schedule_data: WeeklyScheduleCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[dict]:
    """Replace all weekly schedule blocks for a contractor's day.

    day_of_week: 0=Monday, 1=Tuesday, ..., 6=Sunday.
    An empty blocks list clears the contractor's schedule for that day.
    Atomically replaces all existing blocks for (contractor_id, day_of_week).
    """
    svc = SchedulingService(db)
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
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[dict]:
    """Replace all schedule overrides for a contractor's specific date.

    Two modes:
    - is_unavailable=True: marks the entire day as unavailable
    - is_unavailable=False with blocks: custom working hours for the date

    Atomically replaces all existing overrides for (contractor_id, override_date).
    """
    svc = SchedulingService(db)
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
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    """Return the contractor's full weekly schedule grouped by day_of_week.

    Returns a dict mapping day_of_week (0-6) to a list of time blocks.
    Days with no schedule entries are omitted from the response.
    """
    from sqlalchemy import select

    from app.features.scheduling.models import ContractorWeeklySchedule

    stmt = (
        select(ContractorWeeklySchedule)
        .where(
            ContractorWeeklySchedule.contractor_id == contractor_id,
            ContractorWeeklySchedule.deleted_at.is_(None),
        )
        .order_by(ContractorWeeklySchedule.day_of_week, ContractorWeeklySchedule.block_index)
    )
    result = await db.execute(stmt)
    blocks = list(result.scalars().all())

    schedule: dict[int, list[dict]] = {}
    for block in blocks:
        day = block.day_of_week
        if day not in schedule:
            schedule[day] = []
        schedule[day].append(
            {
                "id": str(block.id),
                "block_index": block.block_index,
                "start_time": block.start_time.isoformat(),
                "end_time": block.end_time.isoformat(),
            }
        )

    return schedule


@router.get(
    "/schedules/{contractor_id}/overrides",
    response_model=list[dict],
    summary="Get date overrides for a contractor in a date range",
)
async def get_date_overrides(
    contractor_id: uuid.UUID,
    date_from: date,
    date_to: date,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[dict]:
    """Return date-specific schedule overrides for a contractor within [date_from, date_to].

    Ordered by override_date then block_index.
    """
    from sqlalchemy import select

    from app.features.scheduling.models import ContractorDateOverride

    stmt = (
        select(ContractorDateOverride)
        .where(
            ContractorDateOverride.contractor_id == contractor_id,
            ContractorDateOverride.deleted_at.is_(None),
            ContractorDateOverride.override_date >= date_from,
            ContractorDateOverride.override_date <= date_to,
        )
        .order_by(ContractorDateOverride.override_date, ContractorDateOverride.block_index)
    )
    result = await db.execute(stmt)
    overrides = list(result.scalars().all())

    return [
        {
            "id": str(o.id),
            "contractor_id": str(o.contractor_id),
            "override_date": o.override_date.isoformat(),
            "is_unavailable": o.is_unavailable,
            "block_index": o.block_index,
            "start_time": o.start_time.isoformat() if o.start_time else None,
            "end_time": o.end_time.isoformat() if o.end_time else None,
        }
        for o in overrides
    ]
