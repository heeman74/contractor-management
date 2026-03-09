"""CRM repository — data access for client profiles, properties, and ratings.

Handles all DB queries for the client-facing CRM domain:
- ClientProfile CRUD (get, get-or-create, list with search)
- ClientProperty management (list, add, set-default)
- Denormalized average_rating update

CLAUDE.md rules enforced:
- All relationships eager-loaded with selectinload/joinedload — no N+1 queries.
- No db.commit() — the get_db dependency auto-commits.
- Inherits TenantScopedRepository for RLS-aligned list_all / get_by_id.
"""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import func, select, update
from sqlalchemy.orm import joinedload

from app.core.base_repository import TenantScopedRepository
from app.features.jobs.models import ClientProfile, ClientProperty
from app.features.users.models import User


class CrmRepository(TenantScopedRepository[ClientProfile]):
    """Repository for ClientProfile with eager-loaded user/contractor relationships."""

    model = ClientProfile
    eager_load_options = [
        joinedload(ClientProfile.user),
        joinedload(ClientProfile.preferred_contractor),
    ]

    async def get_client_profile(self, user_id: uuid.UUID) -> ClientProfile | None:
        """SELECT ClientProfile WHERE user_id, eager-load user and preferred_contractor."""
        result = await self.db.execute(
            select(ClientProfile)
            .where(ClientProfile.user_id == user_id)
            .where(ClientProfile.deleted_at.is_(None))
            .options(
                joinedload(ClientProfile.user),
                joinedload(ClientProfile.preferred_contractor),
            )
        )
        return result.scalars().first()

    async def get_or_create_profile(
        self, user_id: uuid.UUID, company_id: uuid.UUID
    ) -> ClientProfile:
        """Return the existing profile or create a new one for this user."""
        profile = await self.get_client_profile(user_id)
        if profile is not None:
            return profile

        profile = ClientProfile(
            user_id=user_id,
            company_id=company_id,
        )
        self.db.add(profile)
        await self.db.flush()
        # Reload with eager-loaded relationships
        result = await self.db.execute(
            select(ClientProfile)
            .where(ClientProfile.id == profile.id)
            .options(
                joinedload(ClientProfile.user),
                joinedload(ClientProfile.preferred_contractor),
            )
        )
        return result.scalars().one()

    async def list_client_profiles(
        self,
        company_id: uuid.UUID,
        search_term: str | None = None,
        offset: int = 0,
        limit: int = 50,
    ) -> list[ClientProfile]:
        """List profiles with optional name/email search (joins User for search).

        Search is case-insensitive and matches against user first_name, last_name,
        and email fields. Ordered by user.last_name then created_at.
        """
        stmt = (
            select(ClientProfile)
            .join(User, ClientProfile.user_id == User.id)
            .where(ClientProfile.company_id == company_id)
            .where(ClientProfile.deleted_at.is_(None))
            .options(
                joinedload(ClientProfile.user),
                joinedload(ClientProfile.preferred_contractor),
            )
        )

        if search_term:
            pattern = f"%{search_term}%"
            stmt = stmt.where(
                (User.first_name.ilike(pattern))
                | (User.last_name.ilike(pattern))
                | (User.email.ilike(pattern))
            )

        stmt = stmt.order_by(User.last_name, ClientProfile.created_at).offset(offset).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_client_properties(self, client_id: uuid.UUID) -> list[ClientProperty]:
        """List saved properties for a client, eager-load job_site relationship."""
        result = await self.db.execute(
            select(ClientProperty)
            .where(ClientProperty.client_id == client_id)
            .where(ClientProperty.deleted_at.is_(None))
            .options(joinedload(ClientProperty.job_site))
            .order_by(ClientProperty.is_default.desc(), ClientProperty.created_at)
        )
        return list(result.scalars().all())

    async def add_client_property(
        self,
        client_id: uuid.UUID,
        company_id: uuid.UUID,
        job_site_id: uuid.UUID,
        nickname: str | None,
        is_default: bool,
    ) -> ClientProperty:
        """Create ClientProperty. Unsets other defaults if is_default=True."""
        if is_default:
            # Unset existing defaults for this client before adding the new one
            await self.db.execute(
                update(ClientProperty)
                .where(ClientProperty.client_id == client_id)
                .where(ClientProperty.is_default.is_(True))
                .where(ClientProperty.deleted_at.is_(None))
                .values(is_default=False)
            )

        prop = ClientProperty(
            client_id=client_id,
            company_id=company_id,
            job_site_id=job_site_id,
            nickname=nickname,
            is_default=is_default,
        )
        self.db.add(prop)
        await self.db.flush()
        # Reload with eager-loaded job_site
        result = await self.db.execute(
            select(ClientProperty)
            .where(ClientProperty.id == prop.id)
            .options(joinedload(ClientProperty.job_site))
        )
        return result.scalars().one()

    async def update_average_rating(
        self, client_profile_id: uuid.UUID, new_average: Decimal | None
    ) -> None:
        """Update the denormalized average_rating field on ClientProfile."""
        await self.db.execute(
            update(ClientProfile)
            .where(ClientProfile.id == client_profile_id)
            .values(average_rating=new_average)
        )
        await self.db.flush()

    async def get_client_notes(self, client_id: uuid.UUID, company_id: uuid.UUID) -> str | None:
        """Get admin_notes for a client profile within a company."""
        result = await self.db.execute(
            select(ClientProfile.admin_notes)
            .where(ClientProfile.user_id == client_id)
            .where(ClientProfile.company_id == company_id)
            .where(ClientProfile.deleted_at.is_(None))
        )
        return result.scalars().first()

    async def recalculate_average_rating(self, ratee_id: uuid.UUID) -> Decimal | None:
        """Compute AVG(stars) for all ratings WHERE ratee_id matches.

        Returns None if no ratings exist yet (prevents 0.00 showing as rating).
        """
        from app.features.jobs.models import Rating

        result = await self.db.execute(
            select(func.avg(Rating.stars)).where(Rating.ratee_id == ratee_id)
        )
        avg = result.scalars().first()
        if avg is None:
            return None
        return Decimal(str(avg)).quantize(Decimal("0.01"))
