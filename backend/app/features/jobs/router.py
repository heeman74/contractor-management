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

import uuid
from datetime import UTC, date, datetime, time
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

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user

# isort: split
# Import scheduling models FIRST (before crm_service) so SQLAlchemy can resolve the
# 'foreign(Booking.job_id) == Job.id' string in Job.bookings before configure_mappers()
# runs. Importing crm_repository (via CrmService) triggers joinedload(ClientProfile.user)
# which calls configure_mappers() — Booking must be in the registry by then.
# Per STATE.md: "Job.bookings uses primaryjoin with foreign() — Booking.job_id has no ORM ForeignKey".
import app.features.scheduling.models  # noqa: F401  (registers Booking in mapper registry)

# isort: split
from app.features.jobs.crm_service import CrmService
from app.features.jobs.rating_service import RatingService
from app.features.jobs.request_service import RequestService
from app.features.jobs.schemas import (
    ClientProfileCreate,
    ClientProfileResponse,
    ClientPropertyCreate,
    ClientPropertyResponse,
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
    RatingCreate,
    RatingResponse,
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

router = APIRouter(tags=["jobs"])

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
    from datetime import timedelta

    tomorrow = datetime.now(UTC).date() + timedelta(days=1)
    return datetime.combine(tomorrow, time(8, 0), tzinfo=UTC)


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
    return JobResponse.model_validate(job)


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
    return [JobResponse.model_validate(j) for j in jobs]


@router.get("/jobs/search", response_model=list[JobResponse])
async def search_jobs(
    q: str = Query(description="Full-text search query"),
    status: str | None = Query(default=None),
    contractor_id: uuid.UUID | None = Query(default=None),
    client_id: uuid.UUID | None = Query(default=None),
    trade_type: str | None = Query(default=None),
    priority: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[JobResponse]:
    """Full-text search across jobs."""
    svc = JobService(db)
    jobs = await svc.search_jobs(
        q,
        status=status,
        contractor_id=contractor_id,
        client_id=client_id,
        trade_type=trade_type,
        priority=priority,
    )
    return [JobResponse.model_validate(j) for j in jobs]


@router.get("/jobs/contractor/mine", response_model=list[JobResponse])
async def get_my_contractor_jobs(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[JobResponse]:
    """Return all active jobs assigned to the current authenticated user (contractor view)."""
    svc = JobService(db)
    jobs = await svc.get_contractor_jobs(current_user.user_id)
    return [JobResponse.model_validate(j) for j in jobs]


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
    return templates.TemplateResponse(
        request,
        "job_request.html",
        {"company_id": str(company_id), "success": False},
    )


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
    # Validate description is present
    if not description.strip():
        return templates.TemplateResponse(
            request,
            "job_request.html",
            {"company_id": str(company_id), "success": False, "error": "Description is required"},
            status_code=400,
        )

    # Validate photos
    valid_photos: list[UploadFile] = []
    if photos:
        for photo in photos:
            if photo.filename:  # skip empty file inputs
                valid_photos.append(photo)

    if len(valid_photos) > _MAX_PHOTOS:
        return templates.TemplateResponse(
            request,
            "job_request.html",
            {
                "company_id": str(company_id),
                "success": False,
                "error": f"Maximum {_MAX_PHOTOS} photos allowed",
            },
            status_code=400,
        )

    for photo in valid_photos:
        content_type = (photo.content_type or "").lower()
        if content_type not in _ALLOWED_PHOTO_TYPES:
            return templates.TemplateResponse(
                request,
                "job_request.html",
                {
                    "company_id": str(company_id),
                    "success": False,
                    "error": "Only JPEG, PNG, and HEIC images are accepted",
                },
                status_code=400,
            )

    # Parse optional date/decimal fields
    import contextlib
    from decimal import Decimal, InvalidOperation

    parsed_start: date | None = None
    parsed_end: date | None = None
    parsed_budget_min: Decimal | None = None
    parsed_budget_max: Decimal | None = None

    if preferred_date_start:
        with contextlib.suppress(ValueError):
            parsed_start = date.fromisoformat(preferred_date_start)

    if preferred_date_end:
        with contextlib.suppress(ValueError):
            parsed_end = date.fromisoformat(preferred_date_end)

    if budget_min:
        with contextlib.suppress(InvalidOperation):
            parsed_budget_min = Decimal(budget_min)

    if budget_max:
        with contextlib.suppress(InvalidOperation):
            parsed_budget_max = Decimal(budget_max)

    # Set tenant context so RLS allows anonymous user creation for web form submissions.
    # The web form has no JWT auth, so TenantMiddleware leaves _current_tenant_id=None.
    # Without setting it here, any User INSERT triggered by submitted_email would fail
    # the RLS policy (requires app.current_company_id to be set per transaction).
    from app.core.tenant import set_current_tenant_id

    set_current_tenant_id(company_id)

    # Build request create schema
    from app.features.jobs.schemas import JobUrgency

    urgency_value = JobUrgency.urgent if urgency == "urgent" else JobUrgency.normal

    job_request_data = JobRequestCreate(
        description=description,
        trade_type=trade_type or None,
        urgency=urgency_value,
        preferred_date_start=parsed_start,
        preferred_date_end=parsed_end,
        budget_min=parsed_budget_min,
        budget_max=parsed_budget_max,
        submitted_name=submitted_name,
        submitted_email=submitted_email,
        submitted_phone=submitted_phone,
    )

    svc = RequestService(db)
    job_request = await svc.submit_request(
        data=job_request_data,
        company_id=company_id,
        client_id=None,
        photo_paths=[],  # files saved below after request is created
    )

    # Save photos to disk after request is created (we need request ID for directory)
    photo_paths: list[str] = []
    if valid_photos:
        upload_dir = Path("uploads") / "job_requests" / str(job_request.id)
        upload_dir.mkdir(parents=True, exist_ok=True)

        for photo in valid_photos:
            safe_name = Path(photo.filename or "photo").name
            dest = upload_dir / safe_name
            content = await photo.read()
            async with aiofiles.open(dest, "wb") as f:
                await f.write(content)
            photo_paths.append(str(dest))

        # Update the photos list on the created request (list replacement per CLAUDE.md)
        if photo_paths:
            job_request.photos = photo_paths
            await db.flush()

    return templates.TemplateResponse(
        request,
        "job_request.html",
        {"company_id": str(company_id), "success": True},
    )


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
    """Get a single job request by ID.

    Declared here (before /jobs/{job_id}) to prevent route shadowing.
    """
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
    return JobResponse.model_validate(job)


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
    job = await svc.get_job(job_id)
    if job is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job {job_id} not found",
        )
    return JobResponse.model_validate(job)


@router.patch("/jobs/{job_id}", response_model=JobResponse)
async def update_job(
    job_id: uuid.UUID,
    data: JobUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> JobResponse:
    """Partial update of non-lifecycle fields (PATCH semantics). Returns 404 if not found."""
    svc = JobService(db)
    job = await svc.update_job(job_id, data)
    return JobResponse.model_validate(job)


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
        scheduling_svc = SchedulingService(db)
        duration = job.estimated_duration_minutes or 0

        try:
            if duration > 0 and duration <= _SINGLE_DAY_MAX_MINUTES:
                # Single-day booking
                from datetime import timedelta

                start_dt = _derive_booking_start(job)
                end_dt = start_dt + timedelta(minutes=duration)
                booking_data = BookingCreate(
                    contractor_id=job.contractor_id,  # type: ignore[arg-type]
                    job_id=job.id,
                    job_site_id=None,
                    start=start_dt,
                    end=end_dt,
                )
                await scheduling_svc.book_slot(booking_data)
            elif duration > _SINGLE_DAY_MAX_MINUTES:
                # Multi-day booking — derive day blocks from job data
                # Build minimal two-day blocks (scheduler enforces min_length=2)
                from datetime import timedelta

                base_date = (
                    job.scheduled_completion_date
                    if job.scheduled_completion_date
                    else (datetime.now(UTC).date() + timedelta(days=1))
                )
                minutes_per_day = _SINGLE_DAY_MAX_MINUTES
                num_full_days = duration // minutes_per_day
                remaining = duration % minutes_per_day

                day_blocks: list[DayBlock] = []
                for i in range(num_full_days):
                    day_date = base_date + timedelta(days=i)
                    day_blocks.append(
                        DayBlock(
                            date=day_date,
                            start_time=time(8, 0),
                            end_time=time(16, 0),
                        )
                    )
                if remaining > 0:
                    extra_date = base_date + timedelta(days=num_full_days)
                    end_hour = 8 + (remaining // 60)
                    end_minute = remaining % 60
                    day_blocks.append(
                        DayBlock(
                            date=extra_date,
                            start_time=time(8, 0),
                            end_time=time(end_hour, end_minute),
                        )
                    )
                # Ensure at least 2 blocks (MultiDayBookingCreate.day_blocks min_length=2)
                if len(day_blocks) < 2:
                    extra_date = base_date + timedelta(days=len(day_blocks))
                    day_blocks.append(
                        DayBlock(
                            date=extra_date,
                            start_time=time(8, 0),
                            end_time=time(8 + (remaining // 60 or 1), remaining % 60),
                        )
                    )

                booking_data_multi = MultiDayBookingCreate(
                    contractor_id=job.contractor_id,  # type: ignore[arg-type]
                    job_id=job.id,
                    job_site_id=None,
                    day_blocks=day_blocks,
                )
                await scheduling_svc.book_multiday_job(booking_data_multi)
        except SchedulingConflictError as exc:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "Scheduling conflict: the selected time slot is no longer available. "
                    "Please choose a different time."
                ),
            ) from exc

    return JobResponse.model_validate(job)


@router.delete("/jobs/{job_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Admin hard-removal: sets deleted_at (distinct from cancellation). Returns 204."""
    svc = JobService(db)
    await svc.soft_delete_job(job_id, current_user.user_id)


# ---------------------------------------------------------------------------
# Client CRM endpoints
# ---------------------------------------------------------------------------


@router.get("/clients/", response_model=list[ClientProfileResponse])
async def list_clients(
    search: str | None = Query(default=None),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ClientProfileResponse]:
    """List client profiles. Optionally filter by name/email search term."""
    svc = CrmService(db)
    profiles = await svc.list_clients(
        company_id=current_user.company_id,
        search_term=search,
        offset=offset,
        limit=limit,
    )
    return [ClientProfileResponse.model_validate(p) for p in profiles]


@router.get("/clients/{user_id}", response_model=ClientProfileResponse)
async def get_client(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ClientProfileResponse:
    """Get a client profile. Returns 404 if not found."""
    svc = CrmService(db)
    profile = await svc.get_profile(user_id)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Client profile not found for user {user_id}",
        )
    return ClientProfileResponse.model_validate(profile)


@router.post(
    "/clients/{user_id}/profile",
    status_code=status.HTTP_201_CREATED,
    response_model=ClientProfileResponse,
)
async def create_or_update_client_profile(
    user_id: uuid.UUID,
    data: ClientProfileCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ClientProfileResponse:
    """Create or update a client profile (upsert semantics)."""
    svc = CrmService(db)
    profile = await svc.create_or_update_profile(
        user_id=user_id,
        company_id=current_user.company_id,
        data=data,
    )
    return ClientProfileResponse.model_validate(profile)


@router.get("/clients/{user_id}/properties", response_model=list[ClientPropertyResponse])
async def list_client_properties(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ClientPropertyResponse]:
    """List saved properties for a client."""
    svc = CrmService(db)
    properties = await svc.manage_properties(
        client_id=user_id,
        company_id=current_user.company_id,
    )
    return [ClientPropertyResponse.model_validate(p) for p in properties]


@router.post(
    "/clients/{user_id}/properties",
    status_code=status.HTTP_201_CREATED,
    response_model=ClientPropertyResponse,
)
async def add_client_property(
    user_id: uuid.UUID,
    data: ClientPropertyCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ClientPropertyResponse:
    """Add a saved property association for a client."""
    svc = CrmService(db)
    prop = await svc.add_property(
        client_id=user_id,
        company_id=current_user.company_id,
        job_site_id=data.job_site_id,
        nickname=data.nickname,
        is_default=data.is_default,
    )
    return ClientPropertyResponse.model_validate(prop)


@router.delete(
    "/clients/properties/{property_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None
)
async def remove_client_property(
    property_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Remove a saved property association. Returns 204."""
    svc = CrmService(db)
    await svc.remove_property(property_id)


# ---------------------------------------------------------------------------
# NOTE: The job request routes (web form + in-app) are declared BEFORE /jobs/{job_id}
# above, to prevent FastAPI from shadowing them with the {job_id} path parameter route.
# The old declarations below were removed as part of the route ordering fix.
# See the early declarations around line 235 for the actual handler implementations.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Rating endpoints
# ---------------------------------------------------------------------------


@router.post(
    "/jobs/{job_id}/ratings",
    status_code=status.HTTP_201_CREATED,
    response_model=RatingResponse,
)
async def create_rating(
    job_id: uuid.UUID,
    data: RatingCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> RatingResponse:
    """Create a star rating for a completed job.

    Raises 422 if:
    - Job status is not 'complete' or 'invoiced'
    - Rating window (30 days from completion) has expired

    Raises 409 if a rating in this direction already exists for the job.
    """
    svc = RatingService(db)
    # ratee_id: if direction is admin_to_client, ratee is the job's client;
    #           if client_to_company, ratee is the company's admin user.
    # For simplicity, the rater provides ratee_id via the direction field and
    # we trust the service layer to validate eligibility.
    from sqlalchemy import select

    from app.features.jobs.models import Job

    result = await db.execute(select(Job).where(Job.id == job_id))
    job = result.scalars().first()
    if job is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job {job_id} not found",
        )

    # Determine ratee based on direction
    from app.features.jobs.schemas import RatingDirection

    if data.direction == RatingDirection.admin_to_client:
        ratee_id = job.client_id
    else:
        # client_to_company: ratee is the contractor assigned to the job
        ratee_id = job.contractor_id

    if ratee_id is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Cannot create rating: the required party (client or contractor) is not assigned to this job",
        )

    rating = await svc.create_rating(
        job_id=job_id,
        rater_id=current_user.user_id,
        ratee_id=ratee_id,
        direction=data.direction,
        stars=data.stars,
        review_text=data.review_text,
        company_id=current_user.company_id,
    )
    return RatingResponse.model_validate(rating)


@router.patch("/ratings/{rating_id}", response_model=RatingResponse)
async def update_rating(
    rating_id: uuid.UUID,
    data: RatingCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> RatingResponse:
    """Update an existing rating. Raises 403 if caller is not the original rater."""
    svc = RatingService(db)
    rating = await svc.update_rating(
        rating_id=rating_id,
        stars=data.stars,
        review_text=data.review_text,
        user_id=current_user.user_id,
    )
    return RatingResponse.model_validate(rating)


@router.get("/jobs/{job_id}/ratings", response_model=list[RatingResponse])
async def get_job_ratings(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[RatingResponse]:
    """Get all ratings for a job (up to 2: one per direction)."""
    svc = RatingService(db)
    ratings = await svc.get_ratings_for_job(job_id)
    return [RatingResponse.model_validate(r) for r in ratings]
