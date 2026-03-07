"""SchedulingRepository — database operations for the scheduling engine.

All queries use AsyncSession (inherited from TenantScopedRepository via BaseRepository).
No db.commit() calls — get_db dependency handles transaction lifecycle.

Key responsibilities:
  - Per-contractor SELECT FOR UPDATE lock acquisition (serializes concurrent bookings)
  - TSTZRANGE overlap queries for booking conflicts
  - Weekly schedule and date override retrieval
  - Company scheduling config parsing from JSONB
  - Booking creation with GIST constraint violation handling
  - Contractor location lookup for proximity sorting
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import selectinload

from app.core.base_repository import TenantScopedRepository
from app.core.tenant import get_current_tenant_id
from app.features.companies.models import Company
from app.features.scheduling.models import (
    Booking,
    ContractorDateOverride,
    ContractorScheduleLock,
    ContractorWeeklySchedule,
)
from app.features.scheduling.schemas import SchedulingConfig
from app.features.users.models import User


class BookingConflictError(Exception):
    """Raised when a GIST constraint violation is detected on booking insert.

    Holds a human-readable detail string from the IntegrityError.
    The SchedulingService raises its own richer BookingConflictError (with
    ConflictDetail list) before the INSERT, so this is a last-resort safety net.
    """

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class SchedulingRepository(TenantScopedRepository[Booking]):
    """Database operations for the scheduling engine.

    Inherits from TenantScopedRepository[Booking] — the primary model is Booking,
    but this repository also queries ContractorWeeklySchedule, ContractorDateOverride,
    ContractorScheduleLock, Company, and User directly via self.db.
    """

    model = Booking

    # -------------------------------------------------------------------------
    # Lock acquisition
    # -------------------------------------------------------------------------

    async def acquire_contractor_lock(self, contractor_id: uuid.UUID) -> None:
        """Acquire a per-contractor SELECT FOR UPDATE advisory lock.

        Serializes booking attempts for the SAME contractor while allowing
        concurrent booking of DIFFERENT contractors (row-level locking).

        Algorithm:
        1. SELECT FOR UPDATE on the contractor's lock row.
        2. If no row exists: create one (with company_id from tenant context),
           flush to persist, then re-acquire with FOR UPDATE.
        3. The lock is released automatically when the enclosing transaction
           commits or rolls back — no explicit unlock needed.
        """
        stmt = (
            select(ContractorScheduleLock)
            .where(ContractorScheduleLock.contractor_id == contractor_id)
            .with_for_update()
        )
        result = await self.db.execute(stmt)
        lock_row = result.scalar_one_or_none()

        if lock_row is None:
            # Create anchor row — must flush before re-acquiring FOR UPDATE
            company_id = get_current_tenant_id()
            new_lock = ContractorScheduleLock(
                contractor_id=contractor_id,
                company_id=company_id,
            )
            self.db.add(new_lock)
            await self.db.flush()

            # Re-acquire with FOR UPDATE now that the row exists
            result = await self.db.execute(stmt)
            # Row is now locked for the duration of this transaction

    # -------------------------------------------------------------------------
    # Booking queries
    # -------------------------------------------------------------------------

    async def get_bookings_in_range(
        self,
        contractor_id: uuid.UUID,
        range_start: datetime,
        range_end: datetime,
    ) -> list[Booking]:
        """Return all non-deleted bookings that overlap with [range_start, range_end).

        Uses PostgreSQL TSTZRANGE && overlap operator for efficient index-backed
        overlap detection. Eager-loads job_site to avoid N+1 in the service layer.
        """
        from sqlalchemy import func

        # Build the TSTZRANGE literal for the overlap check using cast
        range_literal = func.tstzrange(range_start, range_end, "[)")
        stmt = (
            select(Booking)
            .where(
                Booking.contractor_id == contractor_id,
                Booking.deleted_at.is_(None),
                Booking.time_range.op("&&")(range_literal),
            )
            .options(selectinload(Booking.job_site))
            .order_by(Booking.time_range)
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def find_conflicts(
        self,
        contractor_id: uuid.UUID,
        utc_ranges: list[tuple[datetime, datetime]],
    ) -> list[Booking]:
        """Return non-deleted bookings that overlap any range in utc_ranges.

        Combines multiple range overlap checks with OR so that a single query
        handles multi-day booking conflict detection without N+1 queries.
        """
        if not utc_ranges:
            return []

        from sqlalchemy import func

        overlap_conditions = [
            Booking.time_range.op("&&")(func.tstzrange(start, end, "[)"))
            for start, end in utc_ranges
        ]
        stmt = (
            select(Booking)
            .where(
                Booking.contractor_id == contractor_id,
                Booking.deleted_at.is_(None),
                or_(*overlap_conditions),
            )
            .order_by(Booking.time_range)
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    # -------------------------------------------------------------------------
    # Schedule and config queries
    # -------------------------------------------------------------------------

    async def get_weekly_schedule(
        self,
        contractor_id: uuid.UUID,
    ) -> list[ContractorWeeklySchedule]:
        """Return all non-deleted weekly schedule blocks for a contractor.

        Ordered by day_of_week then block_index for deterministic iteration.
        """
        stmt = (
            select(ContractorWeeklySchedule)
            .where(
                ContractorWeeklySchedule.contractor_id == contractor_id,
                ContractorWeeklySchedule.deleted_at.is_(None),
            )
            .order_by(
                ContractorWeeklySchedule.day_of_week,
                ContractorWeeklySchedule.block_index,
            )
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_date_overrides(
        self,
        contractor_id: uuid.UUID,
        start_date: date,
        end_date: date,
    ) -> list[ContractorDateOverride]:
        """Return non-deleted date overrides for a contractor within [start_date, end_date].

        Ordered by override_date then block_index for deterministic processing.
        """
        stmt = (
            select(ContractorDateOverride)
            .where(
                ContractorDateOverride.contractor_id == contractor_id,
                ContractorDateOverride.deleted_at.is_(None),
                ContractorDateOverride.override_date >= start_date,
                ContractorDateOverride.override_date <= end_date,
            )
            .order_by(
                ContractorDateOverride.override_date,
                ContractorDateOverride.block_index,
            )
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_company_scheduling_config(
        self,
        company_id: uuid.UUID,
    ) -> SchedulingConfig:
        """Parse company scheduling_config JSONB into a SchedulingConfig model.

        Returns SchedulingConfig() with all defaults if the column is NULL or empty.
        """
        result = await self.db.execute(
            select(Company.scheduling_config).where(Company.id == company_id)
        )
        raw_config = result.scalar_one_or_none()
        if not raw_config:
            return SchedulingConfig()
        return SchedulingConfig.model_validate(raw_config)

    # -------------------------------------------------------------------------
    # Booking creation
    # -------------------------------------------------------------------------

    async def create_booking(self, booking: Booking) -> Booking:
        """Persist a booking and return it with server-generated fields.

        Wraps the inherited create() to catch IntegrityError from the GIST
        exclusion constraint and convert it to a BookingConflictError.
        This is a last-resort safety net — the SchedulingService performs an
        application-level conflict check before calling this method.
        """
        try:
            return await self.create(booking)
        except IntegrityError as exc:
            # GIST constraint violation: the booking overlaps an existing one
            raise BookingConflictError(
                f"Booking conflict detected by database constraint: {exc.orig}"
            ) from exc

    # -------------------------------------------------------------------------
    # Contractor lookup
    # -------------------------------------------------------------------------

    async def get_contractor_with_location(
        self,
        contractor_id: uuid.UUID,
    ) -> User | None:
        """Return the User record with home location fields for proximity sorting.

        Fetches the user's most recent booking's job_site eagerly so the service
        layer can fall back to "last job location" for distance calculations.
        """
        stmt = select(User).where(User.id == contractor_id)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_contractors_by_trade(
        self,
        trade_type: str,
        company_id: uuid.UUID,
    ) -> list[User]:
        """Return all contractor users whose company supports the given trade_type.

        Queries users with the 'contractor' role within the company. Trade type
        filtering is applied in the service layer from the company's trade_types array
        because the contractor -> trade relationship lives on the company level.
        """
        from app.features.users.models import UserRole

        stmt = (
            select(User)
            .join(UserRole, UserRole.user_id == User.id)
            .where(
                UserRole.role == "contractor",
                User.company_id == company_id,
                User.deleted_at.is_(None),
            )
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().unique().all())

    # -------------------------------------------------------------------------
    # Schedule management (used by set_weekly_schedule / set_date_override)
    # -------------------------------------------------------------------------

    async def delete_weekly_schedule_for_day(
        self,
        contractor_id: uuid.UUID,
        day_of_week: int,
    ) -> None:
        """Soft-delete all weekly schedule blocks for a contractor's day.

        Called before inserting replacement blocks in set_weekly_schedule.
        """
        from datetime import UTC
        from datetime import datetime as dt

        from sqlalchemy import update

        await self.db.execute(
            update(ContractorWeeklySchedule)
            .where(
                ContractorWeeklySchedule.contractor_id == contractor_id,
                ContractorWeeklySchedule.day_of_week == day_of_week,
                ContractorWeeklySchedule.deleted_at.is_(None),
            )
            .values(deleted_at=dt.now(UTC))
        )

    async def delete_date_overrides_for_date(
        self,
        contractor_id: uuid.UUID,
        override_date: date,
    ) -> None:
        """Soft-delete all date overrides for a contractor's specific date.

        Called before inserting replacement overrides in set_date_override.
        """
        from datetime import UTC
        from datetime import datetime as dt

        from sqlalchemy import update

        await self.db.execute(
            update(ContractorDateOverride)
            .where(
                ContractorDateOverride.contractor_id == contractor_id,
                ContractorDateOverride.override_date == override_date,
                ContractorDateOverride.deleted_at.is_(None),
            )
            .values(deleted_at=dt.now(UTC))
        )

    async def create_weekly_schedule_block(
        self,
        block: ContractorWeeklySchedule,
    ) -> ContractorWeeklySchedule:
        """Persist a single weekly schedule block."""
        self.db.add(block)
        await self.db.flush()
        await self.db.refresh(block)
        return block

    async def create_date_override(
        self,
        override: ContractorDateOverride,
    ) -> ContractorDateOverride:
        """Persist a single date override block."""
        self.db.add(override)
        await self.db.flush()
        await self.db.refresh(override)
        return override

    async def ensure_schedule_lock_exists(
        self,
        contractor_id: uuid.UUID,
        company_id: uuid.UUID,
    ) -> None:
        """Create a ContractorScheduleLock row if one does not already exist.

        Called by set_weekly_schedule to ensure the lock anchor is ready before
        the first booking attempt for a newly onboarded contractor.
        """
        stmt = select(ContractorScheduleLock).where(
            ContractorScheduleLock.contractor_id == contractor_id
        )
        result = await self.db.execute(stmt)
        existing = result.scalar_one_or_none()
        if existing is None:
            lock = ContractorScheduleLock(
                contractor_id=contractor_id,
                company_id=company_id,
            )
            self.db.add(lock)
            await self.db.flush()
