"""CRM service — client profile CRUD and saved property management.

Business logic for the client-facing CRM domain:
- Create/update client profiles
- List clients with optional name/email search
- Get client job history (profile + jobs)
- Manage saved properties (add, remove)

CLAUDE.md rules enforced:
- Inherits TenantScopedService — uses _require_tenant_id() for RLS safety.
- No db.commit() — the get_db dependency handles commit/rollback.
- Lazy imports where needed to break circular import with JobRepository.
- Specific exception types (HTTPException) over bare ValueError.
"""

from __future__ import annotations

import uuid
from typing import TYPE_CHECKING

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import TenantScopedService
from app.features.jobs.crm_repository import CrmRepository
from app.features.jobs.models import ClientProfile, ClientProperty
from app.features.jobs.schemas import ClientProfileCreate, ClientProfileUpdate

if TYPE_CHECKING:
    from app.features.jobs.models import Job


class CrmService(TenantScopedService[ClientProfile]):
    """Business logic for client profile CRUD and saved property management."""

    repository_class = CrmRepository

    def __init__(self, db: AsyncSession) -> None:
        super().__init__(db)
        self.crm_repo = CrmRepository(db)

    async def get_profile(self, user_id: uuid.UUID) -> ClientProfile | None:
        """Retrieve the client profile for a given user ID."""
        return await self.crm_repo.get_client_profile(user_id)

    async def create_or_update_profile(
        self,
        user_id: uuid.UUID,
        company_id: uuid.UUID,
        data: ClientProfileCreate | ClientProfileUpdate,
    ) -> ClientProfile:
        """Get or create a profile then apply the fields from data.

        If the profile already exists, only non-None fields from data are applied
        (PATCH semantics). If it does not exist, a new profile is created and
        all provided fields are set.
        """
        profile = await self.crm_repo.get_or_create_profile(user_id, company_id)

        # Apply fields from the schema (skip None for partial updates)
        update_fields = data.model_dump(exclude_none=True, exclude={"user_id"})
        for field, value in update_fields.items():
            setattr(profile, field, value)

        await self.db.flush()
        await self.db.refresh(profile)
        return profile

    async def list_clients(
        self,
        company_id: uuid.UUID,
        search_term: str | None = None,
        offset: int = 0,
        limit: int = 50,
    ) -> list[ClientProfile]:
        """List client profiles with optional name/email search and pagination."""
        return await self.crm_repo.list_client_profiles(
            company_id=company_id,
            search_term=search_term,
            offset=offset,
            limit=limit,
        )

    async def get_client_with_job_history(
        self, user_id: uuid.UUID
    ) -> tuple[ClientProfile, list[Job]]:
        """Get client profile together with their job history.

        Lazy import of JobRepository to avoid circular imports between
        crm_service and job service/repository modules.
        """
        profile = await self.crm_repo.get_client_profile(user_id)
        if profile is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Client profile not found for user {user_id}",
            )

        # Import at method level to avoid circular import
        from sqlalchemy import select
        from sqlalchemy.orm import joinedload

        from app.features.jobs.models import Job

        result = await self.db.execute(
            select(Job)
            .where(Job.client_id == user_id)
            .where(Job.deleted_at.is_(None))
            .options(joinedload(Job.client), joinedload(Job.contractor))
            .order_by(Job.created_at.desc())
        )
        jobs = list(result.scalars().all())
        return profile, jobs

    async def manage_properties(
        self, client_id: uuid.UUID, company_id: uuid.UUID
    ) -> list[ClientProperty]:
        """List all saved properties for a client."""
        return await self.crm_repo.get_client_properties(client_id)

    async def add_property(
        self,
        client_id: uuid.UUID,
        company_id: uuid.UUID,
        job_site_id: uuid.UUID,
        nickname: str | None = None,
        is_default: bool = False,
    ) -> ClientProperty:
        """Add a saved property association for a client.

        If is_default=True, any existing default for this client is unset first.
        """
        return await self.crm_repo.add_client_property(
            client_id=client_id,
            company_id=company_id,
            job_site_id=job_site_id,
            nickname=nickname,
            is_default=is_default,
        )

    async def remove_property(self, property_id: uuid.UUID) -> None:
        """Soft-delete a client property association.

        Raises 404 if the property does not exist.
        Uses crm_repo.soft_delete_property (not the inherited soft_delete which
        queries by ClientProfile.id — the repository model type — not ClientProperty.id).
        """
        deleted = await self.crm_repo.soft_delete_property(property_id)
        if not deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Client property {property_id} not found",
            )
