"""Ratings API router.


Job rating endpoints, split out of the oversized jobs/router.py for single
responsibility. Paths are unchanged.
"""

from __future__ import annotations

import uuid

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    status,
)
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import entity_or_404
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.jobs.rating_service import RatingService
from app.features.jobs.schemas import (
    RatingCreate,
    RatingResponse,
)

router = APIRouter(tags=["ratings"])


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
    job = entity_or_404(result.scalars().first(), f"Job {job_id} not found")

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
