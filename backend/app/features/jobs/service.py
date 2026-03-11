"""JobService — core business logic for the job lifecycle domain.

Implements:
- State machine with role-based transition guards (ALLOWED_TRANSITIONS)
- Version-checked transitions for offline/online conflict safety
- Backward transitions requiring a reason string
- Cancellation: sets status='cancelled' (NOT deleted_at) and bulk soft-deletes bookings
- soft_delete_job: admin-only hard-removal via deleted_at (distinct from cancellation)
- CRUD delegation to JobRepository
- Full-text search delegation to JobRepository
- Phase 6 field workflow: job notes, time entries, GPS geocoding

State machine design (from CONTEXT.md locked decisions):
  Admin:       all forward + backward transitions
  Contractor:  Scheduled→In Progress, In Progress→Complete (own jobs only)
  Client:      view only (no transitions)
  Cancelled:   terminal — no transitions out for any role

All CLAUDE.md rules apply:
- No db.commit() — get_db handles transaction lifecycle
- Inherits TenantScopedService[Job] per OOP architecture rules
- Specific exception types over generic ValueError
- No standalone service functions — class methods only
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.features.jobs.models import Job, JobNote, TimeEntry
from app.features.jobs.repository import JobRepository
from app.features.jobs.schemas import (
    DelayReportRequest,
    JobCreate,
    JobNoteCreate,
    JobStatus,
    JobUpdate,
    TimeEntryAdjust,
    TimeEntryUpdate,
)

# ---------------------------------------------------------------------------
# State machine constants
# ---------------------------------------------------------------------------

# All valid job statuses (matches CheckConstraint on jobs table)
_ALL_STATUSES: frozenset[str] = frozenset(
    {
        JobStatus.quote,
        JobStatus.scheduled,
        JobStatus.in_progress,
        JobStatus.complete,
        JobStatus.invoiced,
        JobStatus.cancelled,
    }
)

# Backward transition pairs — (from_status, to_status) — always require a reason
# Cancellation from any non-terminal state is NOT backward — it's a termination.
BACKWARD_TRANSITIONS: set[tuple[str, str]] = {
    (JobStatus.scheduled, JobStatus.quote),
    (JobStatus.in_progress, JobStatus.scheduled),
    (JobStatus.complete, JobStatus.in_progress),
    (JobStatus.invoiced, JobStatus.complete),
}

# Allowed transitions per (current_status, role) — role string values:
# "admin", "contractor", "client"
# Cancelled is terminal — no role can transition out.
ALLOWED_TRANSITIONS: dict[tuple[str, str], frozenset[str]] = {
    # ------- Admin: all forward + backward, can cancel from any non-terminal state -------
    (JobStatus.quote, "admin"): frozenset(
        {JobStatus.scheduled, JobStatus.in_progress, JobStatus.cancelled}
    ),
    (JobStatus.scheduled, "admin"): frozenset(
        {JobStatus.quote, JobStatus.in_progress, JobStatus.cancelled}
    ),
    (JobStatus.in_progress, "admin"): frozenset(
        {JobStatus.scheduled, JobStatus.complete, JobStatus.cancelled}
    ),
    (JobStatus.complete, "admin"): frozenset(
        {JobStatus.in_progress, JobStatus.invoiced, JobStatus.cancelled}
    ),
    (JobStatus.invoiced, "admin"): frozenset({JobStatus.complete, JobStatus.cancelled}),
    (JobStatus.cancelled, "admin"): frozenset(),  # terminal — no transitions out
    # ------- Contractor: own jobs only, Scheduled→In Progress & In Progress→Complete -------
    (JobStatus.quote, "contractor"): frozenset(),
    (JobStatus.scheduled, "contractor"): frozenset({JobStatus.in_progress}),
    (JobStatus.in_progress, "contractor"): frozenset({JobStatus.complete}),
    (JobStatus.complete, "contractor"): frozenset(),
    (JobStatus.invoiced, "contractor"): frozenset(),
    (JobStatus.cancelled, "contractor"): frozenset(),  # terminal
    # ------- Client: view only — no transitions -------
    (JobStatus.quote, "client"): frozenset(),
    (JobStatus.scheduled, "client"): frozenset(),
    (JobStatus.in_progress, "client"): frozenset(),
    (JobStatus.complete, "client"): frozenset(),
    (JobStatus.invoiced, "client"): frozenset(),
    (JobStatus.cancelled, "client"): frozenset(),
}


def is_backward(current: str, next_status: str) -> bool:
    """Return True if transitioning from current to next_status is a backward move.

    Backward pairs are pre-defined. Cancellation is NOT backward — it's a
    terminal transition that may happen from any stage.
    """
    return (current, next_status) in BACKWARD_TRANSITIONS


# ---------------------------------------------------------------------------
# Custom exceptions
# ---------------------------------------------------------------------------


class InvalidTransitionError(Exception):
    """Raised when a role attempts an invalid state machine transition.

    Attributes:
        from_status: The current job status.
        to_status:   The attempted target status.
        role:        The role of the user attempting the transition.
    """

    def __init__(self, from_status: str, to_status: str, role: str) -> None:
        self.from_status = from_status
        self.to_status = to_status
        self.role = role
        super().__init__(
            f"Role '{role}' cannot transition job from '{from_status}' to '{to_status}'"
        )


# ---------------------------------------------------------------------------
# JobService
# ---------------------------------------------------------------------------


class JobService(TenantScopedService[Job]):
    """Service for job lifecycle operations.

    Inherits TenantScopedService[Job] which wires up self.repository via
    repository_class and provides _require_tenant_id().
    """

    repository_class = JobRepository

    # Expose typed repository reference for IDE completion
    repository: JobRepository

    async def create_job(
        self,
        data: JobCreate,
        *,
        user_id: uuid.UUID,
        company_id: uuid.UUID,
    ) -> Job:
        """Create a new job from schema data.

        Sets initial status from data (defaults to 'quote' but company-assigned
        jobs can start at any stage per CONTEXT.md locked decision).
        Appends initial status_history entry recording the creation event.
        Uses db.flush() to obtain generated ID without committing.
        """
        initial_status = data.status or JobStatus.quote
        initial_history_entry: dict[str, Any] = {
            "status": str(initial_status),
            "timestamp": datetime.now(UTC).isoformat(),
            "user_id": str(user_id),
            "reason": "Job created",
        }
        job = Job(
            company_id=company_id,
            description=data.description,
            trade_type=data.trade_type,
            status=str(initial_status),
            status_history=[initial_history_entry],
            priority=str(data.priority),
            client_id=data.client_id,
            contractor_id=data.contractor_id,
            purchase_order_number=data.purchase_order_number,
            external_reference=data.external_reference,
            tags=data.tags,
            notes=data.notes,
            estimated_duration_minutes=data.estimated_duration_minutes,
            scheduled_completion_date=data.scheduled_completion_date,
        )
        self.db.add(job)
        await self.db.flush()
        await self.db.refresh(job)
        return job

    async def transition_status(
        self,
        job_id: uuid.UUID,
        new_status: str,
        *,
        role: str,
        user_id: uuid.UUID,
        reason: str | None = None,
        expected_version: int,
    ) -> Job:
        """Transition a job to a new lifecycle status.

        Enforces:
        - 404 if job not found
        - 409 if expected_version != job.version (optimistic locking, prevents
          offline/online race conditions per RESEARCH.md Pitfall 2)
        - InvalidTransitionError if (current_status, role) doesn't allow new_status
        - 422 if backward transition and no reason provided
        - 403 if contractor attempts to transition a job they are not assigned to
        - Bulk soft-delete of bookings when cancelling (or backing out of scheduling)
        - Status history list replacement (NOT in-place append, per Pitfall 3)
        - Version increment after successful transition
        """
        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )

        # Optimistic locking — reject stale clients
        if job.version != expected_version:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Version conflict: expected version {expected_version}, "
                    f"job is at version {job.version}. "
                    "Fetch the latest job and retry."
                ),
            )

        # Role-based transition guard
        allowed = ALLOWED_TRANSITIONS.get((job.status, role), frozenset())
        if new_status not in allowed:
            raise InvalidTransitionError(
                from_status=job.status,
                to_status=new_status,
                role=role,
            )

        # Backward transitions require a reason
        if is_backward(job.status, new_status) and not reason:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="A reason is required for backward transitions.",
            )

        # Contractor: own jobs only
        if role == "contractor" and job.contractor_id != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Contractors can only transition their own assigned jobs.",
            )

        # Capture original status before mutation (needed for post-transition logic)
        original_status = job.status

        # Append history entry via list replacement (Pitfall 3: never in-place)
        new_entry: dict[str, Any] = {
            "status": new_status,
            "timestamp": datetime.now(UTC).isoformat(),
            "user_id": str(user_id),
            "reason": reason,
        }
        job.status_history = [*job.status_history, new_entry]

        # Apply the transition
        job.status = new_status
        job.version = job.version + 1  # type: ignore[assignment]

        # Free bookings when cancelling or when backing out of scheduled stage
        # (use original_status — job.status is now new_status)
        if new_status == JobStatus.cancelled or is_backward(original_status, new_status):
            await self.repository.cancel_job_bookings(job_id)

        await self.db.flush()
        await self.db.refresh(job)
        return job

    async def update_job(
        self,
        job_id: uuid.UUID,
        data: JobUpdate,
    ) -> Job:
        """Partial update for non-lifecycle fields (PATCH semantics).

        Increments version to signal that the record has changed — clients
        should refresh their cached version before attempting a transition.
        Returns updated Job or raises 404 if not found.
        """
        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )

        update_data = data.model_dump(exclude_unset=True)
        if not update_data:
            # Nothing to update — return as-is
            return job

        for field, value in update_data.items():
            setattr(job, field, value)
        job.version = job.version + 1  # type: ignore[assignment]

        await self.db.flush()
        await self.db.refresh(job)
        return job

    async def search_jobs(
        self,
        query: str,
        *,
        status: str | None = None,
        contractor_id: uuid.UUID | None = None,
        client_id: uuid.UUID | None = None,
        trade_type: str | None = None,
        priority: str | None = None,
    ) -> list[Job]:
        """Full-text search across jobs — delegates to repository."""
        return await self.repository.search_jobs(
            query,
            status=status,
            contractor_id=contractor_id,
            client_id=client_id,
            trade_type=trade_type,
            priority=priority,
        )

    async def get_job(self, job_id: uuid.UUID) -> Job | None:
        """Retrieve a single job by ID — delegates to repository.get_by_id."""
        return await self.repository.get_by_id(job_id)

    async def list_jobs(
        self,
        *,
        status: str | None = None,
        contractor_id: uuid.UUID | None = None,
        client_id: uuid.UUID | None = None,
        trade_type: str | None = None,
        priority: str | None = None,
        offset: int = 0,
        limit: int = 50,
    ) -> list[Job]:
        """Filtered list of jobs — delegates to repository.list_jobs."""
        return await self.repository.list_jobs(
            status=status,
            contractor_id=contractor_id,
            client_id=client_id,
            trade_type=trade_type,
            priority=priority,
            offset=offset,
            limit=limit,
        )

    async def get_contractor_jobs(self, contractor_id: uuid.UUID) -> list[Job]:
        """All active jobs for a contractor — delegates to repository."""
        return await self.repository.get_jobs_for_contractor(contractor_id)

    async def report_delay(
        self,
        job_id: uuid.UUID,
        data: DelayReportRequest,
        *,
        user_id: uuid.UUID,
    ) -> Job:
        """Record a delay report against a scheduled or in-progress job.

        Appends a delay entry to status_history (list replacement — NOT in-place
        append, per CONTEXT.md Pitfall 3) and updates scheduled_completion_date
        to the new ETA. Increments version to signal record change.

        Raises:
            404 — job not found
            409 — version conflict (stale client must re-fetch and retry)
            422 — job status is not 'scheduled' or 'in_progress'
        """
        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )

        # Optimistic locking — reject stale clients
        if job.version != data.version:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Version conflict: expected version {data.version}, "
                    f"job is at version {job.version}. "
                    "Fetch the latest job and retry."
                ),
            )

        # Delays only apply to active jobs (scheduled or in_progress)
        if job.status not in (JobStatus.scheduled, JobStatus.in_progress):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"Cannot report delay: job status is '{job.status}'. "
                    "Delays can only be reported for jobs that are 'scheduled' or 'in_progress'."
                ),
            )

        # Build delay entry and append via list replacement (Pitfall 3: never in-place)
        delay_entry: dict = {
            "type": "delay",
            "reason": data.reason,
            "new_eta": data.new_eta.isoformat(),
            "timestamp": datetime.now(UTC).isoformat(),
            "user_id": str(user_id),
        }
        job.status_history = [*job.status_history, delay_entry]

        # Update scheduled completion date and bump version
        job.scheduled_completion_date = data.new_eta
        job.version = job.version + 1  # type: ignore[assignment]

        await self.db.flush()
        await self.db.refresh(job)
        return job

    # -------------------------------------------------------------------------
    # Phase 6 — Field workflow: notes, time entries, GPS geocoding
    # -------------------------------------------------------------------------

    async def create_note(
        self,
        job_id: uuid.UUID,
        author_id: uuid.UUID,
        company_id: uuid.UUID,
        data: JobNoteCreate,
    ) -> JobNote:
        """Create a note on a job and eager-load attachments for response.

        Raises 404 if job not found.
        """
        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )

        note = JobNote(
            company_id=company_id,
            job_id=job_id,
            author_id=author_id,
            body=data.body,
        )
        self.db.add(note)
        await self.db.flush()
        # Reload with eager-loaded attachments (empty list for new note)
        return await self.repository.get_note_by_id(note.id)  # type: ignore[return-value]

    async def list_notes(self, job_id: uuid.UUID) -> list[JobNote]:
        """Return all non-deleted notes for a job, newest first, with attachments eager-loaded."""
        return await self.repository.list_notes(job_id)

    async def create_time_entry(
        self,
        job_id: uuid.UUID,
        contractor_id: uuid.UUID,
        company_id: uuid.UUID,
        clocked_in_at: datetime,
    ) -> TimeEntry:
        """Clock in: create an active time entry for a contractor on a job.

        Enforces one-active-session-per-contractor: if the contractor has any
        active session (across any job), it is closed first with duration computed
        from clocked_in_at of the new session minus the old session's clocked_in_at.

        If the job status is 'scheduled', transitions it to 'in_progress' and
        records the transition in status_history.

        Raises 404 if job not found.
        """
        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )

        # Close any existing active session for this contractor (across any job)
        active = await self.repository.get_active_time_entry(contractor_id)
        if active is not None:
            duration = int((clocked_in_at - active.clocked_in_at).total_seconds())
            active.clocked_out_at = clocked_in_at  # type: ignore[assignment]
            active.duration_seconds = max(0, duration)
            active.session_status = "completed"
            await self.db.flush()

        # Auto-transition job from scheduled -> in_progress on first clock-in
        if job.status == JobStatus.scheduled:
            entry: dict[str, Any] = {
                "status": JobStatus.in_progress,
                "timestamp": datetime.now(UTC).isoformat(),
                "user_id": str(contractor_id),
                "reason": "Auto-transitioned to in_progress on contractor clock-in",
            }
            job.status_history = [*job.status_history, entry]
            job.status = JobStatus.in_progress
            job.version = job.version + 1  # type: ignore[assignment]
            await self.db.flush()

        entry_obj = TimeEntry(
            company_id=company_id,
            job_id=job_id,
            contractor_id=contractor_id,
            clocked_in_at=clocked_in_at,
            session_status="active",
        )
        self.db.add(entry_obj)
        await self.db.flush()
        await self.db.refresh(entry_obj)
        return entry_obj

    async def update_time_entry(
        self,
        entry_id: uuid.UUID,
        data: TimeEntryUpdate,
    ) -> TimeEntry:
        """Clock out: complete an active time entry.

        Sets clocked_out_at, computes duration, and sets session_status='completed'.
        Raises 404 if entry not found, 422 if entry is not active.
        """
        entry = await self.repository.get_time_entry_by_id(entry_id)
        if entry is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Time entry {entry_id} not found",
            )

        if entry.session_status != "active":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"Cannot clock out: time entry session_status is "
                    f"'{entry.session_status}' (must be 'active')."
                ),
            )

        entry.clocked_out_at = data.clocked_out_at  # type: ignore[assignment]
        if data.duration_seconds is not None:
            entry.duration_seconds = data.duration_seconds
        else:
            entry.duration_seconds = max(
                0,
                int((data.clocked_out_at - entry.clocked_in_at).total_seconds()),
            )
        entry.session_status = "completed"

        await self.db.flush()
        await self.db.refresh(entry)
        return entry

    async def adjust_time_entry(
        self,
        entry_id: uuid.UUID,
        adjuster_id: uuid.UUID,
        data: TimeEntryAdjust,
    ) -> TimeEntry:
        """Admin adjustment to a time entry.

        Appends an audit entry to adjustment_log JSONB, updates the times,
        sets session_status='adjusted', and recalculates duration_seconds.
        Raises 404 if entry not found.
        """
        entry = await self.repository.get_time_entry_by_id(entry_id)
        if entry is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Time entry {entry_id} not found",
            )

        # Build audit log entry before mutation
        log_entry: dict[str, Any] = {
            "adjusted_by": str(adjuster_id),
            "reason": data.reason,
            "old_clocked_in_at": entry.clocked_in_at.isoformat(),
            "old_clocked_out_at": (
                entry.clocked_out_at.isoformat() if entry.clocked_out_at else None
            ),
            "new_clocked_in_at": (data.clocked_in_at.isoformat() if data.clocked_in_at else None),
            "new_clocked_out_at": (
                data.clocked_out_at.isoformat() if data.clocked_out_at else None
            ),
            "timestamp": datetime.now(UTC).isoformat(),
        }
        # List replacement (Pitfall 3: never in-place JSONB append)
        entry.adjustment_log = [*entry.adjustment_log, log_entry]

        if data.clocked_in_at is not None:
            entry.clocked_in_at = data.clocked_in_at  # type: ignore[assignment]
        if data.clocked_out_at is not None:
            entry.clocked_out_at = data.clocked_out_at  # type: ignore[assignment]

        entry.session_status = "adjusted"
        entry.version = entry.version + 1  # type: ignore[assignment]

        # Recompute duration if both bounds are known
        if entry.clocked_out_at is not None:
            entry.duration_seconds = max(
                0,
                int((entry.clocked_out_at - entry.clocked_in_at).total_seconds()),
            )

        await self.db.flush()
        await self.db.refresh(entry)
        return entry

    async def list_time_entries(self, job_id: uuid.UUID) -> list[TimeEntry]:
        """Return all non-deleted time entries for a job, ordered by clocked_in_at desc."""
        return await self.repository.list_time_entries(job_id)

    async def update_job_gps(
        self,
        job_id: uuid.UUID,
        latitude: float,
        longitude: float,
    ) -> Job:
        """Store GPS coordinates on a job and attempt reverse geocoding.

        Calls ORSGeocodingProvider.reverse_geocode(latitude, longitude) to resolve
        an address. If geocoding fails or returns None, gps_address is set to None
        (client will retry on next sync).

        Raises 404 if job not found.
        """
        from app.core.config import settings

        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )

        job.gps_latitude = latitude  # type: ignore[assignment]
        job.gps_longitude = longitude  # type: ignore[assignment]

        # Attempt reverse geocoding — fail gracefully (store coords, no address)
        address: str | None = None
        ors_api_key = getattr(settings, "ors_api_key", None)
        if ors_api_key:
            try:
                import httpx

                from app.features.scheduling.geocoding.ors_geocoder import ORSGeocodingProvider

                async with httpx.AsyncClient() as http_client:
                    provider = ORSGeocodingProvider(api_key=ors_api_key, client=http_client)
                    address = await provider.reverse_geocode(latitude, longitude)
            except Exception:  # noqa: BLE001
                # Geocode failure is non-fatal — store coords and retry on next sync
                address = None

        job.gps_address = address
        job.version = job.version + 1  # type: ignore[assignment]

        await self.db.flush()
        await self.db.refresh(job)
        return job

    async def soft_delete_job(
        self,
        job_id: uuid.UUID,
        user_id: uuid.UUID,  # noqa: ARG002  # reserved for audit logging
    ) -> Job:
        """Admin-only: mark a job as administratively deleted (sets deleted_at).

        This is DISTINCT from lifecycle cancellation:
        - transition_status(new_status='cancelled'): sets status='cancelled', job
          stays visible in queries (WHERE deleted_at IS NULL), bookings freed.
        - soft_delete_job: sets deleted_at, making the job invisible in all list
          queries. This is a hard administrative removal, not a lifecycle event.
          No status_history entry is added — this is not a lifecycle transition.

        Also soft-deletes associated bookings to free scheduling slots.
        Per CONTEXT.md: "Cancelled is a separate status (not soft-delete) —
        job stays visible in history with Cancelled badge."
        """
        job = await self.repository.get_by_id(job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )

        job.deleted_at = datetime.now(UTC)  # type: ignore[assignment]
        # Free any associated booking slots
        await self.repository.cancel_job_bookings(job_id)

        await self.db.flush()
        return job
