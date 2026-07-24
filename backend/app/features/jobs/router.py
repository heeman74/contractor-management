"""Jobs API router — all REST endpoints for the job lifecycle domain.

Endpoints:
  Job CRUD:
    POST   /jobs/                            — Create job (auth required)
    GET    /jobs/                            — List jobs with filters (auth required)
    GET    /jobs/search                      — Full-text search (auth required)
    GET    /jobs/contractor/mine             — Jobs for current contractor (auth required)
    GET    /jobs/{job_id}                    — Get single job (auth required)
    PATCH  /jobs/{job_id}                    — Update non-lifecycle fields (auth required)
    PATCH  /jobs/{job_id}/transition         — Transition job status (auth required)
    DELETE /jobs/{job_id}                    — Soft delete job (auth required)

  Client CRM:
    GET    /clients/                         — List client profiles (auth required, admin)
    GET    /clients/{user_id}                — Get client with job history (auth required)
    POST   /clients/{user_id}/profile        — Create/update client profile (auth required)
    GET    /clients/{user_id}/properties     — List saved properties (auth required)
    POST   /clients/{user_id}/properties     — Add saved property (auth required)
    DELETE /clients/properties/{property_id} — Remove saved property (auth required)

  Job Requests (web form + in-app):
    GET    /jobs/request/{company_id}        — Render Jinja2 web form (public)
    POST   /jobs/request/{company_id}        — Submit web form (public, multipart/form-data)
    POST   /jobs/requests                    — Submit in-app request (auth required, JSON)
    GET    /jobs/requests                    — List pending requests (auth required, admin)
    GET    /jobs/requests/{request_id}       — Get single request (auth required)
    POST   /jobs/requests/{request_id}/review — Admin review (auth required, admin)

  Ratings:
    POST   /jobs/{job_id}/ratings            — Create rating (auth required)
    PATCH  /ratings/{rating_id}              — Update rating (auth required)
    GET    /jobs/{job_id}/ratings            — Get ratings for job (auth required)

Design notes:
- Plain APIRouter (not CRUDRouter) — lifecycle operations are non-CRUD per CONTEXT.md.
- All logic delegated to service layer (JobService, CrmService, RequestService,
  RatingService). Router handles: auth, schema validation, exception mapping, and
  the SchedulingService orchestration on transition-to-scheduled.
- PATCH /jobs/{job_id}/transition calls SchedulingService.book_slot or book_multiday_job
  when transitioning to 'scheduled', fulfilling the locked decision that
  "Bookings are created when scheduling" from CONTEXT.md.
- InvalidTransitionError -> 422
- Version mismatch -> 409 (raised directly by JobService as HTTPException)
- SchedulingConflictError -> 409 with human-friendly message
- Jinja2Templates uses Path(__file__).parent / "templates" (Pitfall 6 pattern)
- Photo uploads: max 5 files, JPEG/PNG/HEIC only, saved via aiofiles to
  uploads/job_requests/{request_id}/ (Pitfall 7 pattern)
"""

from __future__ import annotations

import contextlib
import uuid
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Annotated

import aiofiles
from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
    status,
)
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.requests import Request

from app.core.base_service import entity_or_404
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.core.tenant import set_current_tenant_id

# isort: split
# Import scheduling models FIRST (before crm_service) so SQLAlchemy can resolve the
# 'foreign(Booking.job_id) == Job.id' string in Job.bookings before configure_mappers()
# runs. Importing crm_repository (via CrmService) triggers joinedload(ClientProfile.user)
# which calls configure_mappers() — Booking must be in the registry by then.
# Per STATE.md: "Job.bookings uses primaryjoin with foreign() — Booking.job_id has no ORM ForeignKey".
import app.features.scheduling.models  # noqa: F401  (registers Booking in mapper registry)

# isort: split
from app.features.jobs.request_service import RequestService
from app.features.jobs.schemas import (
    DelayReportRequest,
    JobCreate,
    JobNoteCreate,
    JobNoteResponse,
    JobRequestCreate,
    JobRequestResponse,
    JobRequestReviewAction,
    JobResponse,
    JobStatus,
    JobTransitionRequest,
    JobUpdate,
    JobUrgency,
    TimeEntryAdjust,
    TimeEntryCreate,
    TimeEntryResponse,
    TimeEntryUpdate,
)
from app.features.jobs.service import InvalidTransitionError, JobService
from app.features.scheduling.schemas import BookingCreate, DayBlock, MultiDayBookingCreate
from app.features.scheduling.service import SchedulingConflictError, SchedulingService

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_TEMPLATES_DIR = Path(__file__).parent / "templates"
templates = Jinja2Templates(directory=str(_TEMPLATES_DIR))

_ALLOWED_PHOTO_TYPES = {"image/jpeg", "image/png", "image/heic", "image/heif"}
_MAX_PHOTOS = 5
# Single-day threshold: if estimated_duration_minutes <= 480 (8 hours), book as single day
_SINGLE_DAY_MAX_MINUTES = 480
_WORK_DAY_START = time(8, 0)
_WORK_DAY_END = time(16, 0)
_MINUTES_PER_HOUR = 60
_MIN_MULTIDAY_BLOCKS = 2

router = APIRouter(tags=["jobs"])


# ---------------------------------------------------------------------------
# Helpers — public job-request web form
# ---------------------------------------------------------------------------


def _render_job_request_form(
    request: Request,
    company_id: uuid.UUID,
    *,
    success: bool,
    error: str | None = None,
    status_code: int = 200,
) -> HTMLResponse:
    """Render the job_request.html template, optionally with an error message."""
    context: dict = {"company_id": str(company_id), "success": success}
    if error is not None:
        context["error"] = error
    return templates.TemplateResponse(request, "job_request.html", context, status_code=status_code)


def _collect_valid_photos(photos: list[UploadFile] | None) -> list[UploadFile]:
    """Drop empty file inputs, keeping only uploads with a filename."""
    return [photo for photo in (photos or []) if photo.filename]


def _photo_validation_error(valid_photos: list[UploadFile]) -> str | None:
    """Return an error message if the photos violate count or content-type rules."""
    if len(valid_photos) > _MAX_PHOTOS:
        return f"Maximum {_MAX_PHOTOS} photos allowed"
    for photo in valid_photos:
        if (photo.content_type or "").lower() not in _ALLOWED_PHOTO_TYPES:
            return "Only JPEG, PNG, and HEIC images are accepted"
    return None


def _parse_optional_date(raw: str | None) -> date | None:
    """Parse an ISO date string, returning None when absent or malformed."""
    if not raw:
        return None
    with contextlib.suppress(ValueError):
        return date.fromisoformat(raw)
    return None


def _parse_optional_decimal(raw: str | None) -> Decimal | None:
    """Parse a decimal string, returning None when absent or malformed."""
    if not raw:
        return None
    with contextlib.suppress(InvalidOperation):
        return Decimal(raw)
    return None


async def _save_request_photos(
    request_id: uuid.UUID,
    valid_photos: list[UploadFile],
) -> list[str]:
    """Persist uploaded photos under uploads/job_requests/{request_id}/ and return their paths."""
    if not valid_photos:
        return []

    upload_dir = Path("uploads") / "job_requests" / str(request_id)
    upload_dir.mkdir(parents=True, exist_ok=True)

    photo_paths: list[str] = []
    for photo in valid_photos:
        destination = upload_dir / Path(photo.filename or "photo").name
        content = await photo.read()
        async with aiofiles.open(destination, "wb") as file:
            await file.write(content)
        photo_paths.append(str(destination))
    return photo_paths


# ---------------------------------------------------------------------------
# Helper — build JobResponse with client_name from eager-loaded relationship
# ---------------------------------------------------------------------------


def _job_with_client_name(job) -> JobResponse:  # type: ignore[type-arg]
    """Serialize a Job ORM object to JobResponse, populating client_name and contractor_name.

    Accesses job.client / job.contractor only when the relationship attribute is already
    loaded in the SQLAlchemy instance state. If not loaded (e.g. after
    db.refresh() on a newly-created or mutated job), those fields are left
    as None rather than triggering a lazy-load that would raise with
    lazy="raise".

    Combines first_name + last_name; returns None when no user is
    assigned or both name parts are empty.
    """
    from sqlalchemy import inspect as sa_inspect

    resp = JobResponse.model_validate(job)
    insp = sa_inspect(job)
    # Check if 'client' relationship is already loaded (not expired/unloaded)
    if "client" not in insp.unloaded and job.client is not None:
        parts = [job.client.first_name, job.client.last_name]
        resp.client_name = " ".join(p for p in parts if p) or None
    # Phase 17: also populate contractor_name using the same sa_inspect guard
    if "contractor" not in insp.unloaded and job.contractor is not None:
        parts = [job.contractor.first_name, job.contractor.last_name]
        resp.contractor_name = " ".join(p for p in parts if p) or None
    return resp


# ---------------------------------------------------------------------------
# Helper — derive booking times from job data
# ---------------------------------------------------------------------------


def _derive_booking_start(job) -> datetime:
    """Derive the booking start time from the job's scheduled_completion_date.

    Falls back to next business day at 08:00 UTC if no date is set.
    This is a safe default — operators can always update the booking after creation.
    """
    if job.scheduled_completion_date:
        return datetime.combine(
            job.scheduled_completion_date,
            time(8, 0),
            tzinfo=UTC,
        )
    # Fallback: tomorrow at 08:00 UTC
    tomorrow = datetime.now(UTC).date() + timedelta(days=1)
    return datetime.combine(tomorrow, time(8, 0), tzinfo=UTC)


# ---------------------------------------------------------------------------
# Helpers — derive scheduling bookings from a job's estimated duration
# ---------------------------------------------------------------------------


def _build_single_day_booking(job, duration_minutes: int) -> BookingCreate:  # type: ignore[type-arg]
    """Build a single-day BookingCreate spanning duration_minutes from the job's start."""
    start_dt = _derive_booking_start(job)
    return BookingCreate(
        contractor_id=job.contractor_id,
        job_id=job.id,
        job_site_id=None,
        start=start_dt,
        end=start_dt + timedelta(minutes=duration_minutes),
    )


def _partial_day_end_time(remaining_minutes: int) -> time:
    """End time for a partial final work day that starts at _WORK_DAY_START."""
    end_hour = _WORK_DAY_START.hour + (remaining_minutes // _MINUTES_PER_HOUR)
    return time(end_hour, remaining_minutes % _MINUTES_PER_HOUR)


def _derive_day_blocks(duration_minutes: int, base_date: date) -> list[DayBlock]:
    """Split a multi-day duration into consecutive daily work blocks from base_date.

    Full days span _WORK_DAY_START–_WORK_DAY_END; a final partial day covers the
    remainder. The result always has at least _MIN_MULTIDAY_BLOCKS blocks, as
    required by MultiDayBookingCreate.
    """
    full_days = duration_minutes // _SINGLE_DAY_MAX_MINUTES
    remaining = duration_minutes % _SINGLE_DAY_MAX_MINUTES

    day_blocks: list[DayBlock] = [
        DayBlock(
            date=base_date + timedelta(days=day_offset),
            start_time=_WORK_DAY_START,
            end_time=_WORK_DAY_END,
        )
        for day_offset in range(full_days)
    ]
    if remaining > 0:
        day_blocks.append(
            DayBlock(
                date=base_date + timedelta(days=full_days),
                start_time=_WORK_DAY_START,
                end_time=_partial_day_end_time(remaining),
            )
        )

    while len(day_blocks) < _MIN_MULTIDAY_BLOCKS:
        day_blocks.append(
            DayBlock(
                date=base_date + timedelta(days=len(day_blocks)),
                start_time=_WORK_DAY_START,
                end_time=_partial_day_end_time(remaining or _MINUTES_PER_HOUR),
            )
        )
    return day_blocks


def _build_multiday_booking(job, duration_minutes: int) -> MultiDayBookingCreate:  # type: ignore[type-arg]
    """Build a MultiDayBookingCreate covering duration_minutes across consecutive days."""
    base_date = job.scheduled_completion_date or (datetime.now(UTC).date() + timedelta(days=1))
    return MultiDayBookingCreate(
        contractor_id=job.contractor_id,
        job_id=job.id,
        job_site_id=None,
        day_blocks=_derive_day_blocks(duration_minutes, base_date),
    )


async def _create_bookings_for_scheduled_job(db: AsyncSession, job) -> None:  # type: ignore[type-arg]
    """Create scheduling bookings for a job that just transitioned to 'scheduled'.

    Single-day when duration <= _SINGLE_DAY_MAX_MINUTES, otherwise multi-day.
    A non-positive duration books nothing. Propagates SchedulingConflictError.
    """
    duration_minutes = job.estimated_duration_minutes or 0
    if duration_minutes <= 0:
        return

    scheduling_svc = SchedulingService(db)
    if duration_minutes <= _SINGLE_DAY_MAX_MINUTES:
        await scheduling_svc.book_slot(_build_single_day_booking(job, duration_minutes))
    else:
        await scheduling_svc.book_multiday_job(_build_multiday_booking(job, duration_minutes))


# ---------------------------------------------------------------------------
# Job CRUD endpoints
# ---------------------------------------------------------------------------


@router.post("/jobs/", status_code=status.HTTP_201_CREATED, response_model=JobResponse)
async def create_job(
    data: JobCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Create a new job. Returns 201 + JobResponse."""
    svc = JobService(db)
    job = await svc.create_job(
        data,
        user_id=current_user.user_id,
        company_id=current_user.company_id,
    )
    return _job_with_client_name(job)


@router.get("/jobs/", response_model=list[JobResponse])
async def list_jobs(
    status: str | None = Query(default=None),
    contractor_id: uuid.UUID | None = Query(default=None),
    client_id: uuid.UUID | None = Query(default=None),
    trade_type: str | None = Query(default=None),
    priority: str | None = Query(default=None),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[JobResponse]:
    """List jobs with optional filters. Paginated via offset/limit."""
    svc = JobService(db)
    jobs = await svc.list_jobs(
        status=status,
        contractor_id=contractor_id,
        client_id=client_id,
        trade_type=trade_type,
        priority=priority,
        offset=offset,
        limit=limit,
    )
    return [_job_with_client_name(j) for j in jobs]


@router.get("/jobs/search", response_model=list[JobResponse])
async def search_jobs(
    q: str = Query(description="Full-text search query"),
    status: str | None = Query(default=None),
    contractor_id: uuid.UUID | None = Query(default=None),
    client_id: uuid.UUID | None = Query(default=None),
    trade_type: str | None = Query(default=None),
    priority: str | None = Query(default=None),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[JobResponse]:
    """Full-text search across jobs. Paginated via offset/limit."""
    svc = JobService(db)
    jobs = await svc.search_jobs(
        q,
        status=status,
        contractor_id=contractor_id,
        client_id=client_id,
        trade_type=trade_type,
        priority=priority,
    )
    # Apply pagination
    jobs = jobs[offset : offset + limit]
    return [_job_with_client_name(j) for j in jobs]


@router.get("/jobs/contractor/mine", response_model=list[JobResponse])
async def get_my_contractor_jobs(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[JobResponse]:
    """Return all active jobs assigned to the current authenticated user (contractor view)."""
    svc = JobService(db)
    jobs = await svc.get_contractor_jobs(current_user.user_id)
    return [_job_with_client_name(j) for j in jobs]


# NOTE: /jobs/requests* and /jobs/request/{company_id} routes are declared BEFORE
# /jobs/{job_id} so that FastAPI matches the specific literal path segments before the
# catch-all UUID path parameter. Declaring them after would cause "requests" to be
# parsed as a UUID job_id, resulting in 422 Unprocessable Entity on every request.


@router.get("/jobs/request/{company_id}", response_class=HTMLResponse, include_in_schema=False)
async def render_job_request_form(
    request: Request,
    company_id: uuid.UUID,
) -> HTMLResponse:
    """Render the Jinja2 web form for anonymous client job request submissions.

    No authentication required — this is the public-facing intake form.
    """
    return _render_job_request_form(request, company_id, success=False)


@router.post("/jobs/request/{company_id}", response_class=HTMLResponse, include_in_schema=False)
async def submit_job_request_form(
    request: Request,
    company_id: uuid.UUID,
    submitted_name: Annotated[str | None, Form()] = None,
    submitted_email: Annotated[str | None, Form()] = None,
    submitted_phone: Annotated[str | None, Form()] = None,
    description: Annotated[str, Form()] = "",
    trade_type: Annotated[str | None, Form()] = None,
    urgency: Annotated[str, Form()] = "normal",
    property_address: Annotated[str | None, Form()] = None,
    preferred_date_start: Annotated[str | None, Form()] = None,
    preferred_date_end: Annotated[str | None, Form()] = None,
    budget_min: Annotated[str | None, Form()] = None,
    budget_max: Annotated[str | None, Form()] = None,
    photos: Annotated[list[UploadFile] | None, File()] = None,
    db: AsyncSession = Depends(get_db),
) -> HTMLResponse:
    """Handle multipart/form-data job request submission from the web form.

    Declared before /jobs/{job_id} to prevent FastAPI route shadowing.
    - Validates photo count (max 5) and content type (JPEG/PNG/HEIC).
    - Saves photos to uploads/job_requests/{request_id}/ using aiofiles.
    - Creates a JobRequest via RequestService.
    - Returns success HTML on completion.

    No authentication required — this is the public-facing intake form.
    """
    if not description.strip():
        return _render_job_request_form(
            request, company_id, success=False, error="Description is required", status_code=400
        )

    valid_photos = _collect_valid_photos(photos)
    photo_error = _photo_validation_error(valid_photos)
    if photo_error is not None:
        return _render_job_request_form(
            request, company_id, success=False, error=photo_error, status_code=400
        )

    # Set tenant context so RLS allows anonymous user creation for web form submissions.
    # The web form has no JWT auth, so TenantMiddleware leaves _current_tenant_id=None.
    # Without this, any User INSERT triggered by submitted_email would fail the RLS policy
    # (which requires app.current_company_id to be set per transaction).
    set_current_tenant_id(company_id)

    urgency_value = JobUrgency.urgent if urgency == "urgent" else JobUrgency.normal
    job_request_data = JobRequestCreate(
        description=description,
        trade_type=trade_type or None,
        urgency=urgency_value,
        preferred_date_start=_parse_optional_date(preferred_date_start),
        preferred_date_end=_parse_optional_date(preferred_date_end),
        budget_min=_parse_optional_decimal(budget_min),
        budget_max=_parse_optional_decimal(budget_max),
        submitted_name=submitted_name,
        submitted_email=submitted_email,
        submitted_phone=submitted_phone,
    )

    svc = RequestService(db)
    job_request = await svc.submit_request(
        data=job_request_data,
        company_id=company_id,
        client_id=None,
        photo_paths=[],  # files saved below once the request ID exists
    )

    photo_paths = await _save_request_photos(job_request.id, valid_photos)
    if photo_paths:
        job_request.photos = photo_paths
        await db.flush()

    return _render_job_request_form(request, company_id, success=True)


@router.post(
    "/jobs/requests",
    status_code=status.HTTP_201_CREATED,
    response_model=JobRequestResponse,
)
async def submit_in_app_job_request_early(
    data: JobRequestCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobRequestResponse:
    """Submit a job request from the mobile app (authenticated, JSON body).

    Declared here (before /jobs/{job_id}) to prevent route shadowing.
    """
    svc = RequestService(db)
    job_request = await svc.submit_request(
        data=data,
        company_id=current_user.company_id,
        client_id=current_user.user_id,
    )
    return JobRequestResponse.model_validate(job_request)


@router.get("/jobs/requests", response_model=list[JobRequestResponse])
async def list_job_requests_early(
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[JobRequestResponse]:
    """List all pending job requests for admin review.

    Declared here (before /jobs/{job_id}) to prevent route shadowing.
    """
    await require_permission("jobs.view")(current_user, db)
    svc = RequestService(db)
    requests = await svc.list_pending_requests(
        company_id=current_user.company_id,
        offset=offset,
        limit=limit,
    )
    return [JobRequestResponse.model_validate(r) for r in requests]


@router.get("/jobs/requests/{request_id}", response_model=JobRequestResponse)
async def get_job_request_early(
    request_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobRequestResponse:
    """Get a single job request by ID (admin only).

    Declared here (before /jobs/{job_id}) to prevent route shadowing.
    """
    await require_permission("jobs.view")(current_user, db)
    svc = RequestService(db)
    job_request = await svc.get_request(request_id)
    return JobRequestResponse.model_validate(job_request)


@router.post("/jobs/requests/{request_id}/review", response_model=JobRequestResponse)
async def review_job_request_early(
    request_id: uuid.UUID,
    action: JobRequestReviewAction,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobRequestResponse:
    """Admin review action on a pending job request.

    Declared here (before /jobs/{job_id}) to prevent route shadowing.
    """
    await require_permission("jobs.edit")(current_user, db)
    svc = RequestService(db)
    result = await svc.review_request(
        request_id=request_id,
        action=action.action,
        admin_user_id=current_user.user_id,
        decline_reason=action.decline_reason,
        decline_message=action.decline_message,
    )
    from app.features.jobs.models import Job

    if isinstance(result, Job):
        updated_request = await svc.get_request(request_id)
        return JobRequestResponse.model_validate(updated_request)

    return JobRequestResponse.model_validate(result)


@router.patch("/jobs/{job_id}/delay", response_model=JobResponse)
async def report_job_delay(
    job_id: uuid.UUID,
    data: DelayReportRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Report a delay on a scheduled or in-progress job.

    Appends a delay entry to the job's status_history and updates
    scheduled_completion_date to the new ETA. Both contractors (own jobs)
    and admins can report delays.

    CRITICAL: Declared BEFORE GET /jobs/{job_id} to prevent FastAPI route
    shadowing — 'delay' path segment must be matched before {job_id} catch-all.

    Raises:
    - 404 if job not found
    - 409 if version conflict (stale client)
    - 422 if job status is not 'scheduled' or 'in_progress'
    """
    svc = JobService(db)
    job = await svc.report_delay(job_id, data, user_id=current_user.user_id)
    return _job_with_client_name(job)


# ---------------------------------------------------------------------------
# Phase 6 — Field workflow endpoints (notes, time entries)
#
# CRITICAL: All these endpoints are declared BEFORE the /jobs/{job_id} catch-all
# to prevent FastAPI from matching sub-path segments as UUID path params.
# ---------------------------------------------------------------------------


@router.post(
    "/jobs/{job_id}/notes",
    status_code=status.HTTP_201_CREATED,
    response_model=JobNoteResponse,
)
async def create_note(
    job_id: uuid.UUID,
    data: JobNoteCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobNoteResponse:
    """Create a note on a job.

    Returns 201 + JobNoteResponse with empty attachments list.
    Raises 404 if job not found.
    """
    svc = JobService(db)
    note = await svc.create_note(
        job_id=job_id,
        author_id=current_user.user_id,
        company_id=current_user.company_id,
        data=data,
    )
    return JobNoteResponse.model_validate(note)


@router.get("/jobs/{job_id}/notes", response_model=list[JobNoteResponse])
async def list_notes(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[JobNoteResponse]:
    """List all notes for a job, newest first, with attachments."""
    svc = JobService(db)
    notes = await svc.list_notes(job_id)
    return [JobNoteResponse.model_validate(n) for n in notes]


@router.post(
    "/jobs/{job_id}/time-entries",
    status_code=status.HTTP_201_CREATED,
    response_model=TimeEntryResponse,
)
async def create_time_entry(
    job_id: uuid.UUID,
    data: TimeEntryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TimeEntryResponse:
    """Clock in: create an active time entry for the current contractor on a job.

    Enforces one-active-session-per-contractor — auto-closes any previous active
    session before opening a new one.

    If the job is 'scheduled', auto-transitions it to 'in_progress'.
    Raises 404 if job not found.
    """
    svc = JobService(db)
    entry = await svc.create_time_entry(
        job_id=job_id,
        contractor_id=current_user.user_id,
        company_id=current_user.company_id,
        clocked_in_at=data.clocked_in_at,
    )
    return TimeEntryResponse.model_validate(entry)


@router.patch(
    "/jobs/{job_id}/time-entries/{entry_id}",
    response_model=TimeEntryResponse,
)
async def clock_out_time_entry(
    job_id: uuid.UUID,
    entry_id: uuid.UUID,
    data: TimeEntryUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TimeEntryResponse:
    """Clock out: complete an active time entry.

    Raises 404 if not found, 422 if entry is not 'active'.
    """
    svc = JobService(db)
    entry = await svc.update_time_entry(entry_id=entry_id, data=data)
    return TimeEntryResponse.model_validate(entry)


@router.patch(
    "/jobs/{job_id}/time-entries/{entry_id}/adjust",
    response_model=TimeEntryResponse,
)
async def adjust_time_entry(
    job_id: uuid.UUID,
    entry_id: uuid.UUID,
    data: TimeEntryAdjust,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> TimeEntryResponse:
    """Admin adjustment: edit a time entry's times with audit trail.

    Appends to adjustment_log JSONB, updates times, sets status='adjusted',
    and recalculates duration_seconds.
    Raises 404 if not found.
    """
    await require_permission("jobs.edit")(current_user, db)
    svc = JobService(db)
    entry = await svc.adjust_time_entry(
        entry_id=entry_id,
        adjuster_id=current_user.user_id,
        data=data,
    )
    return TimeEntryResponse.model_validate(entry)


@router.get(
    "/jobs/{job_id}/time-entries",
    response_model=list[TimeEntryResponse],
)
async def list_time_entries(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[TimeEntryResponse]:
    """List all time entries for a job, ordered by clocked_in_at descending."""
    svc = JobService(db)
    entries = await svc.list_time_entries(job_id)
    return [TimeEntryResponse.model_validate(e) for e in entries]


@router.get("/jobs/{job_id}", response_model=JobResponse)
async def get_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Get a single job by ID. Returns 404 if not found."""
    svc = JobService(db)
    job = entity_or_404(await svc.get_job(job_id), f"Job {job_id} not found")
    return _job_with_client_name(job)


@router.patch("/jobs/{job_id}", response_model=JobResponse)
async def update_job(
    job_id: uuid.UUID,
    data: JobUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Partial update of non-lifecycle fields (PATCH semantics). Returns 404 if not found."""
    await require_permission("jobs.edit")(current_user, db)
    svc = JobService(db)
    job = await svc.update_job(job_id, data)
    return _job_with_client_name(job)


@router.patch("/jobs/{job_id}/transition", response_model=JobResponse)
async def transition_job(
    job_id: uuid.UUID,
    data: JobTransitionRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Transition a job to a new lifecycle status.

    Validates: role, version (optimistic locking), and allowed transitions.

    CRITICAL: If transitioning to 'scheduled', creates bookings via SchedulingService:
    - estimated_duration_minutes <= 480: book_slot (single day)
    - estimated_duration_minutes > 480: book_multiday_job (multi-day)

    BookingConflictError -> 409 with human-friendly message.
    InvalidTransitionError -> 422.
    Version mismatch -> 409 (raised by JobService as HTTPException).
    """
    # Derive role from token — first role wins; default to 'client' if no roles
    role = current_user.roles[0] if current_user.roles else "client"

    job_svc = JobService(db)
    try:
        job = await job_svc.transition_status(
            job_id,
            str(data.new_status),
            role=role,
            user_id=current_user.user_id,
            reason=data.reason,
            expected_version=data.version,
        )
    except InvalidTransitionError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc

    # Wired decision from CONTEXT.md: "Bookings are created when scheduling"
    if data.new_status == JobStatus.scheduled:
        try:
            await _create_bookings_for_scheduled_job(db, job)
        except SchedulingConflictError as exc:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "Scheduling conflict: the selected time slot is no longer available. "
                    "Please choose a different time."
                ),
            ) from exc

    return _job_with_client_name(job)


@router.delete("/jobs/{job_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Admin hard-removal: sets deleted_at (distinct from cancellation). Returns 204."""
    await require_permission("jobs.delete")(current_user, db)
    svc = JobService(db)
    await svc.soft_delete_job(job_id, current_user.user_id)
