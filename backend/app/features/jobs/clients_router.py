"""Client profile & saved-property API router.


Client CRM profile + saved-property endpoints (/clients/*), split out of the
oversized jobs/router.py for single responsibility. Paths are unchanged and
distinct from crm_router (/crm/*), which serves the CRM list/detail views.
"""

from __future__ import annotations

import uuid

from fastapi import (
    APIRouter,
    Depends,
    Query,
    status,
)
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import entity_or_404
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.jobs.crm_service import CrmService
from app.features.jobs.schemas import (
    ClientProfileCreate,
    ClientProfileResponse,
    ClientPropertyCreate,
    ClientPropertyResponse,
)

router = APIRouter(tags=["clients"])


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
    results = await svc.list_clients(
        company_id=current_user.company_id,
        search_term=search,
        offset=offset,
        limit=limit,
    )
    # list_clients returns list[tuple[ClientProfile, int]] — extract the profile
    return [ClientProfileResponse.model_validate(profile) for profile, _jobs_count in results]


@router.get("/clients/{user_id}", response_model=ClientProfileResponse)
async def get_client(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ClientProfileResponse:
    """Get a client profile. Returns 404 if not found."""
    svc = CrmService(db)
    profile = entity_or_404(
        await svc.get_profile(user_id), f"Client profile not found for user {user_id}"
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
