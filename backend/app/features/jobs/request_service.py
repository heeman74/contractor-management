"""Request service — job request submission, admin review, and request-to-job conversion.

Business logic for the inbound job request lifecycle:
- Client submits request (authenticated or anonymous via web form)
- Admin reviews: accept (creates Job at Quote stage), decline, or request more info
- Request-to-job conversion pre-fills the Job from request fields

CLAUDE.md rules enforced:
- Inherits TenantScopedService — uses _require_tenant_id() for RLS safety.
- No db.commit() — the get_db dependency handles commit/rollback.
- Specific exception types (HTTPException) over bare ValueError.
- No N+1 queries — all relationships eager-loaded.
"""

from __future__ import annotations

import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import joinedload, selectinload

from app.core.base_repository import TenantScopedRepository
from app.core.base_service import TenantScopedService
from app.features.jobs.models import Job, JobRequest
from app.features.jobs.schemas import (
    JobCreate,
    JobPriority,
    JobRequestCreate,
    JobRequestStatus,
    JobStatus,
)


class RequestRepository(TenantScopedRepository[JobRequest]):
    """Repository for JobRequest with eager-loaded client relationship."""

    model = JobRequest
    eager_load_options = [joinedload(JobRequest.client)]

    async def get_with_relations(self, request_id: uuid.UUID) -> JobRequest | None:
        """Fetch single request with eager-loaded client and converted_job."""
        result = await self.db.execute(
            select(JobRequest)
            .where(JobRequest.id == request_id)
            .where(JobRequest.deleted_at.is_(None))
            .options(
                joinedload(JobRequest.client),
                joinedload(JobRequest.converted_job),
            )
        )
        return result.scalars().first()

    async def list_pending(
        self, company_id: uuid.UUID, offset: int = 0, limit: int = 50
    ) -> list[JobRequest]:
        """All pending requests for a company, oldest first for review queue."""
        result = await self.db.execute(
            select(JobRequest)
            .where(JobRequest.company_id == company_id)
            .where(JobRequest.status == JobRequestStatus.pending)
            .where(JobRequest.deleted_at.is_(None))
            .options(joinedload(JobRequest.client))
            .order_by(JobRequest.created_at.asc())
            .offset(offset)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def list_for_client(self, client_id: uuid.UUID) -> list[JobRequest]:
        """All requests for a specific client (for client's in-app view)."""
        result = await self.db.execute(
            select(JobRequest)
            .where(JobRequest.client_id == client_id)
            .where(JobRequest.deleted_at.is_(None))
            .options(joinedload(JobRequest.client))
            .order_by(JobRequest.created_at.desc())
        )
        return list(result.scalars().all())

    async def find_user_by_email(self, email: str, company_id: uuid.UUID) -> uuid.UUID | None:
        """Look up an existing User by email within a company. Returns user_id or None."""
        from app.features.users.models import User

        result = await self.db.execute(
            select(User.id)
            .where(User.email == email)
            .where(User.company_id == company_id)
            .where(User.deleted_at.is_(None))
            .limit(1)
        )
        return result.scalars().first()


class RequestService(TenantScopedService[JobRequest]):
    """Business logic for job request submission and admin review lifecycle."""

    repository_class = RequestRepository

    def __init__(self, db) -> None:
        super().__init__(db)
        self.request_repo = RequestRepository(db)

    async def submit_request(
        self,
        data: JobRequestCreate,
        company_id: uuid.UUID,
        client_id: uuid.UUID | None = None,
        photo_paths: list[str] | None = None,
    ) -> JobRequest:
        """Create a JobRequest from form data.

        For anonymous web form submissions (client_id=None): look up an existing
        User by submitted_email within the company. If found, set client_id.
        If not found, store the submission details in submitted_name/email/phone
        fields and create a new User with client role.

        Photo file paths (actual file writing handled at router level) are stored
        in the photos JSONB array.
        """
        resolved_client_id = client_id

        if resolved_client_id is None and data.submitted_email:
            # Look up existing user by email within this company
            existing_user_id = await self.request_repo.find_user_by_email(
                data.submitted_email, company_id
            )
            if existing_user_id is not None:
                resolved_client_id = existing_user_id
            else:
                # Create a new User with client role for the anonymous submitter
                from app.features.users.models import User, UserRole

                new_user = User(
                    company_id=company_id,
                    email=data.submitted_email,
                    first_name=data.submitted_name,
                    last_name=None,
                    phone=data.submitted_phone,
                )
                self.db.add(new_user)
                await self.db.flush()

                client_role = UserRole(
                    user_id=new_user.id,
                    company_id=company_id,
                    role="client",
                )
                self.db.add(client_role)
                await self.db.flush()
                resolved_client_id = new_user.id

        job_request = JobRequest(
            company_id=company_id,
            client_id=resolved_client_id,
            description=data.description,
            trade_type=data.trade_type,
            urgency=data.urgency,
            preferred_date_start=data.preferred_date_start,
            preferred_date_end=data.preferred_date_end,
            budget_min=data.budget_min,
            budget_max=data.budget_max,
            photos=photo_paths or [],
            status=JobRequestStatus.pending,
            submitted_name=data.submitted_name,
            submitted_email=data.submitted_email,
            submitted_phone=data.submitted_phone,
        )
        self.db.add(job_request)
        await self.db.flush()
        await self.db.refresh(job_request)
        return job_request

    async def list_pending_requests(
        self, company_id: uuid.UUID, offset: int = 0, limit: int = 50
    ) -> list[JobRequest]:
        """All pending job requests for a company, ordered oldest-first for review queue."""
        return await self.request_repo.list_pending(company_id, offset=offset, limit=limit)

    async def review_request(
        self,
        request_id: uuid.UUID,
        action: JobRequestStatus,
        admin_user_id: uuid.UUID,
        decline_reason: str | None = None,
        decline_message: str | None = None,
    ) -> JobRequest | Job:
        """Handle admin review of a pending job request.

        Actions:
        - accept: Set status='accepted', create a Job at Quote stage pre-filled
          from the request, set converted_job_id. Returns the created Job.
        - decline: Set status='declined', store decline_reason and decline_message.
          Returns the updated JobRequest.
        - info_requested: Set status='info_requested'. Returns the updated JobRequest.

        Raises 404 if request not found.
        Raises 422 if request is not in 'pending' status.
        Only 'accepted', 'declined', 'info_requested' are valid actions.
        """
        job_request = await self.request_repo.get_with_relations(request_id)
        if job_request is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job request {request_id} not found",
            )

        if job_request.status != JobRequestStatus.pending:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Job request is already in '{job_request.status}' status — cannot review",
            )

        if action not in (
            JobRequestStatus.accepted,
            JobRequestStatus.declined,
            JobRequestStatus.info_requested,
        ):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid review action '{action}'. Must be accepted, declined, or info_requested",
            )

        if action == JobRequestStatus.accepted:
            return await self._accept_request(job_request, admin_user_id)

        if action == JobRequestStatus.declined:
            job_request.status = JobRequestStatus.declined
            job_request.decline_reason = decline_reason
            job_request.decline_message = decline_message
            await self.db.flush()
            await self.db.refresh(job_request)
            return job_request

        # info_requested
        job_request.status = JobRequestStatus.info_requested
        await self.db.flush()
        await self.db.refresh(job_request)
        return job_request

    async def _accept_request(self, job_request: JobRequest, admin_user_id: uuid.UUID) -> Job:
        """Create a Job at Quote stage pre-filled from the request fields.

        The new Job is linked back to the request via converted_job_id.
        Import JobService at method level to avoid circular imports.
        """
        from datetime import UTC, datetime

        # Determine trade_type (fall back to empty string if not specified)
        trade_type = job_request.trade_type or "general"

        # Build the job create schema from request fields
        job_data = JobCreate(
            description=job_request.description,
            trade_type=trade_type,
            status=JobStatus.quote,
            priority=JobPriority.medium,
            client_id=job_request.client_id,
            notes=None,
        )

        # Create the job directly (avoids circular service import)
        initial_history_entry = {
            "status": JobStatus.quote,
            "timestamp": datetime.now(UTC).isoformat(),
            "user_id": str(admin_user_id),
            "reason": f"Created from job request {job_request.id}",
        }

        new_job = Job(
            company_id=job_request.company_id,
            description=job_data.description,
            trade_type=job_data.trade_type,
            status=job_data.status,
            status_history=[initial_history_entry],
            priority=job_data.priority,
            client_id=job_data.client_id,
            notes=job_data.notes,
            tags=[],
        )
        self.db.add(new_job)
        await self.db.flush()

        # Link the request to the created job
        job_request.status = JobRequestStatus.accepted
        job_request.converted_job_id = new_job.id
        await self.db.flush()

        # Reload job with eager-loaded relationships
        result = await self.db.execute(
            select(Job)
            .where(Job.id == new_job.id)
            .options(
                joinedload(Job.client),
                joinedload(Job.contractor),
                selectinload(Job.ratings),
            )
        )
        return result.scalars().one()

    async def get_request(self, request_id: uuid.UUID) -> JobRequest:
        """Single request by ID with eager-loaded relationships. Raises 404 if not found."""
        job_request = await self.request_repo.get_with_relations(request_id)
        if job_request is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job request {request_id} not found",
            )
        return job_request

    async def list_requests_for_client(self, client_id: uuid.UUID) -> list[JobRequest]:
        """All requests for a specific client (for client's in-app view)."""
        return await self.request_repo.list_for_client(client_id)
