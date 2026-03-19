"""CRM API router — client list and detail endpoints.

Endpoints (all require Depends(get_current_user)):
  GET /api/v1/crm/clients                — paginated client list with optional search
  GET /api/v1/crm/clients/{user_id}      — client profile with job history and properties

Design: thin router functions delegate all business logic to CrmService.
Custom domain (not standard CRUD) so CRUDRouter mixin is NOT used per CLAUDE.md guidance.

Phase 17: CRM client list and detail
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.core.tenant import get_current_tenant_id
from app.features.jobs.crm_service import CrmService
from app.features.jobs.router import _job_with_client_name
from app.features.jobs.schemas import (
    ClientDetailResponse,
    ClientListResponse,
    ClientPropertyResponse,
)

router = APIRouter(prefix="/crm", tags=["crm"])


@router.get("/clients", response_model=list[ClientListResponse])
async def list_clients(
    search: str | None = Query(default=None, description="Search by name or email"),
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(get_current_user),
) -> list[ClientListResponse]:
    """Return a paginated list of client profiles for the current company.

    Optionally filters by name/email via the `search` query parameter.
    Each item includes a jobs_count scalar subquery result.
    """
    company_id = get_current_tenant_id()
    svc = CrmService(db)
    results = await svc.list_clients(company_id, search, offset, limit)
    return [ClientListResponse.from_profile(profile, count) for profile, count in results]


@router.get("/clients/{user_id}", response_model=ClientDetailResponse)
async def get_client(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(get_current_user),
) -> ClientDetailResponse:
    """Return the full client profile with job history and saved properties.

    Raises 404 if no client profile exists for the given user_id.
    """
    company_id = get_current_tenant_id()
    svc = CrmService(db)
    profile, jobs = await svc.get_client_with_job_history(user_id)
    properties = await svc.manage_properties(user_id, company_id)

    user = profile.user
    pref = profile.preferred_contractor

    job_responses = [_job_with_client_name(j) for j in jobs]
    property_responses = [ClientPropertyResponse.model_validate(p) for p in properties]

    return ClientDetailResponse(
        id=profile.id,
        user_id=profile.user_id,
        first_name=user.first_name if user else None,
        last_name=user.last_name if user else None,
        email=user.email if user else "",
        phone=user.phone if user else None,
        tags=profile.tags or [],
        admin_notes=profile.admin_notes,
        referral_source=profile.referral_source,
        preferred_contractor_id=profile.preferred_contractor_id,
        preferred_contractor_name=(
            f"{pref.first_name or ''} {pref.last_name or ''}".strip() if pref else None
        ),
        preferred_contact_method=profile.preferred_contact_method,
        billing_address=profile.billing_address,
        average_rating=profile.average_rating,
        jobs=job_responses,
        properties=property_responses,
    )
