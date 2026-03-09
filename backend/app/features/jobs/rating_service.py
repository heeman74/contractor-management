"""Rating service — mutual ratings with eligibility checks and 30-day window.

Business logic for the star rating domain:
- Create rating with job status validation and 30-day window enforcement
- Update rating with re-validation
- Retrieve ratings for a job or a user's profile
- Recalculate and update denormalized average_rating on ClientProfile

CLAUDE.md rules enforced:
- Inherits TenantScopedService per CLAUDE.md OOP rules.
- No db.commit() — the get_db dependency handles commit/rollback.
- Specific exception types (HTTPException) over bare ValueError.
- No N+1 queries — all relationships eager-loaded.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.core.base_repository import TenantScopedRepository
from app.core.base_service import TenantScopedService
from app.features.jobs.models import Job, Rating
from app.features.jobs.schemas import JobStatus, RatingDirection

RATING_WINDOW_DAYS = 30


class RatingRepository(TenantScopedRepository[Rating]):
    """Repository for Rating with eager-loaded job and user relationships."""

    model = Rating
    eager_load_options = [joinedload(Rating.job)]

    async def get_rating_for_job_direction(
        self, job_id: uuid.UUID, direction: RatingDirection
    ) -> Rating | None:
        """Check if a rating already exists for this job+direction (UNIQUE constraint check)."""
        result = await self.db.execute(
            select(Rating)
            .where(Rating.job_id == job_id)
            .where(Rating.direction == direction)
            .where(Rating.deleted_at.is_(None))
        )
        return result.scalars().first()

    async def list_for_job(self, job_id: uuid.UUID) -> list[Rating]:
        """Both rating directions for a single job."""
        result = await self.db.execute(
            select(Rating)
            .where(Rating.job_id == job_id)
            .where(Rating.deleted_at.is_(None))
            .options(joinedload(Rating.rater), joinedload(Rating.ratee))
        )
        return list(result.scalars().all())

    async def list_for_user(self, user_id: uuid.UUID) -> list[Rating]:
        """All ratings where ratee_id matches (for profile display)."""
        result = await self.db.execute(
            select(Rating)
            .where(Rating.ratee_id == user_id)
            .where(Rating.deleted_at.is_(None))
            .options(joinedload(Rating.job))
            .order_by(Rating.created_at.desc())
        )
        return list(result.scalars().all())


class RatingService(TenantScopedService[Rating]):
    """Business logic for mutual ratings with eligibility checks and 30-day window."""

    repository_class = RatingRepository

    def __init__(self, db) -> None:
        super().__init__(db)
        self.rating_repo = RatingRepository(db)

    async def create_rating(
        self,
        job_id: uuid.UUID,
        rater_id: uuid.UUID,
        ratee_id: uuid.UUID,
        direction: RatingDirection,
        stars: int,
        review_text: str | None,
        company_id: uuid.UUID,
    ) -> Rating:
        """Create a star rating with full eligibility validation.

        Validation steps:
        a. Job exists and status is 'complete' or 'invoiced'
        b. No existing rating for this job+direction (UNIQUE constraint)
        c. Rating window: find most recent 'complete' entry in status_history.
           If more than 30 days ago, reject with 422.
        d. Create Rating record.
        e. If direction is admin_to_client: recalculate and update average_rating
           on the ratee's ClientProfile.
        """
        # a. Load the job and validate status
        job = await self._get_job_or_404(job_id)

        if job.status not in (JobStatus.complete, JobStatus.invoiced):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"Ratings can only be submitted for complete or invoiced jobs. "
                    f"Job {job_id} is currently '{job.status}'"
                ),
            )

        # b. Check for existing rating for this job+direction
        existing = await self.rating_repo.get_rating_for_job_direction(job_id, direction)
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"A rating in direction '{direction}' already exists for job {job_id}",
            )

        # c. Enforce 30-day rating window from last 'complete' transition
        self._validate_rating_window(job)

        # d. Create the Rating record
        rating = Rating(
            company_id=company_id,
            job_id=job_id,
            rater_id=rater_id,
            ratee_id=ratee_id,
            direction=direction,
            stars=stars,
            review_text=review_text,
        )
        self.db.add(rating)
        await self.db.flush()
        await self.db.refresh(rating)

        # e. Update denormalized average_rating on ClientProfile if admin_to_client
        if direction == RatingDirection.admin_to_client:
            await self._update_client_average_rating(ratee_id)

        return rating

    async def update_rating(
        self,
        rating_id: uuid.UUID,
        stars: int,
        review_text: str | None,
        user_id: uuid.UUID,
    ) -> Rating:
        """Update an existing rating.

        Re-validates the 30-day window. Recalculates average_rating if admin_to_client.
        Raises 404 if rating not found.
        Raises 403 if the caller is not the rater.
        """
        rating = await self.rating_repo.get_by_id(rating_id)
        if rating is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Rating {rating_id} not found",
            )

        if rating.rater_id != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only edit your own ratings",
            )

        # Re-validate the 30-day window
        job = await self._get_job_or_404(rating.job_id)
        self._validate_rating_window(job)

        rating.stars = stars
        rating.review_text = review_text
        await self.db.flush()
        await self.db.refresh(rating)

        if rating.direction == RatingDirection.admin_to_client:
            await self._update_client_average_rating(rating.ratee_id)

        return rating

    async def get_ratings_for_job(self, job_id: uuid.UUID) -> list[Rating]:
        """Both rating directions for a single job."""
        return await self.rating_repo.list_for_job(job_id)

    async def get_ratings_for_user(self, user_id: uuid.UUID) -> list[Rating]:
        """All ratings where ratee_id matches (for profile display)."""
        return await self.rating_repo.list_for_user(user_id)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    async def _get_job_or_404(self, job_id: uuid.UUID) -> Job:
        """Fetch the Job by ID or raise 404."""
        result = await self.db.execute(select(Job).where(Job.id == job_id))
        job = result.scalars().first()
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {job_id} not found",
            )
        return job

    def _validate_rating_window(self, job: Job) -> None:
        """Enforce the 30-day rating window based on status_history.

        Finds the most recent 'complete' entry in job.status_history JSONB.
        If no 'complete' entry is found, the window is open (job may be invoiced
        without ever explicitly entering 'complete' in history).
        If the most recent 'complete' entry is older than 30 days, raises 422.
        """
        status_history: list[dict] = job.status_history or []

        # Find the most recent 'complete' timestamp entry
        complete_entries = [
            entry for entry in status_history if entry.get("status") == JobStatus.complete
        ]

        if not complete_entries:
            # No 'complete' entry found — window is open (invoiced without complete step)
            return

        # Sort by timestamp descending, take the most recent
        most_recent_complete = max(
            complete_entries,
            key=lambda e: e.get("timestamp", ""),
        )

        try:
            complete_ts = datetime.fromisoformat(most_recent_complete["timestamp"])
            if complete_ts.tzinfo is None:
                complete_ts = complete_ts.replace(tzinfo=UTC)
        except (KeyError, ValueError):
            # Malformed timestamp — treat as valid (don't block rating on bad history)
            return

        cutoff = datetime.now(UTC) - timedelta(days=RATING_WINDOW_DAYS)
        if complete_ts < cutoff:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"The {RATING_WINDOW_DAYS}-day rating window has expired. "
                    f"Job was completed on {complete_ts.date().isoformat()}"
                ),
            )

    async def _update_client_average_rating(self, ratee_id: uuid.UUID) -> None:
        """Recalculate and update the denormalized average_rating on ClientProfile.

        Only called when direction is admin_to_client (company rates the client).
        Uses CrmRepository.recalculate_average_rating and update_average_rating.
        """
        from app.features.jobs.crm_repository import CrmRepository
        from app.features.jobs.models import ClientProfile

        crm_repo = CrmRepository(self.db)
        new_average = await crm_repo.recalculate_average_rating(ratee_id)

        # Find the ClientProfile by user_id (ratee_id is the user's ID)
        result = await self.db.execute(
            select(ClientProfile)
            .where(ClientProfile.user_id == ratee_id)
            .where(ClientProfile.deleted_at.is_(None))
            .limit(1)
        )
        profile = result.scalars().first()
        if profile is not None:
            await crm_repo.update_average_rating(profile.id, new_average)
