"""SQLAlchemy ORM models for the scheduling domain.

Six models correspond to the six tables created in migration 0007:
  - ContractorScheduleLock   — per-contractor SELECT FOR UPDATE anchor row
  - ContractorWeeklySchedule — weekly working-hours template (multi-block per day)
  - ContractorDateOverride   — date-specific schedule overrides or full-day unavailability
  - JobSite                  — geocoded job location
  - Booking                  — scheduled time block with GIST exclusion constraint
  - TravelTimeCache          — cached ORS travel-time results (30-day TTL)

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All tenant-scoped models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- ContractorScheduleLock and TravelTimeCache are NOT tenant-scoped business entities;
  they use Base directly with explicit columns.

IMPORTANT: The EXCLUDE USING GIST constraint on Booking.__table_args__ is for ORM
metadata/documentation only. The actual constraint is enforced by migration 0007.
Do NOT rely on Alembic autogenerate to detect or create this constraint.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, time
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    Text,
    Time,
    func,
)
from sqlalchemy.dialects.postgresql import TSTZRANGE, UUID, ExcludeConstraint, Range
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import Base, TenantScopedModel

if TYPE_CHECKING:
    from app.features.users.models import User


class ContractorScheduleLock(Base):
    """Per-contractor lock anchor row for SELECT FOR UPDATE serialization.

    One row per contractor, never deleted. The booking service issues
    SELECT FOR UPDATE on this row before performing the availability check
    and insert — serializing concurrent booking attempts for the same contractor.

    NOT a TenantScopedModel because:
    - contractor_id is the primary key (not a separate UUID 'id')
    - No version, created_at, or updated_at needed (pure lock anchor)
    - RLS is applied via company_id FK, not the full tenant model contract
    """

    __tablename__ = "contractor_schedule_locks"

    contractor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        primary_key=True,
    )
    company_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("companies.id"),
        nullable=False,
    )

    # Relationships with lazy="raise" to surface accidental lazy loads loudly
    contractor: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )


class ContractorWeeklySchedule(TenantScopedModel):
    """Weekly working-hours template for a contractor.

    Multiple blocks per day are supported via block_index (e.g., 0 = morning
    block, 1 = afternoon block after a lunch break). The combination of
    (contractor_id, day_of_week, block_index) is unique.

    day_of_week: 0=Monday, 1=Tuesday, ..., 6=Sunday (ISO weekday - 1)
    """

    __tablename__ = "contractor_weekly_schedule"

    contractor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    day_of_week: Mapped[int] = mapped_column(Integer, nullable=False)
    block_index: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    start_time: Mapped[time] = mapped_column(Time, nullable=False)
    end_time: Mapped[time] = mapped_column(Time, nullable=False)

    # Relationships
    contractor: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )


class ContractorDateOverride(TenantScopedModel):
    """Date-specific schedule override for a contractor.

    Two mutually exclusive modes (enforced by DB CHECK constraint):
    1. Full-day unavailable: is_unavailable=True, start_time=None, end_time=None
    2. Custom hours: is_unavailable=False, start_time/end_time set per block

    Multiple blocks per date supported via block_index (same as weekly schedule).
    The combination of (contractor_id, override_date, block_index) is unique.
    """

    __tablename__ = "contractor_date_overrides"

    contractor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    override_date: Mapped[date] = mapped_column(Date, nullable=False)
    is_unavailable: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    block_index: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    start_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    end_time: Mapped[time | None] = mapped_column(Time, nullable=True)

    # Relationships
    contractor: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )


class JobSite(TenantScopedModel):
    """Geocoded job location.

    Lat/lng stored as Numeric(9,6) for ~10cm precision.
    name is optional — used for well-known named sites (e.g., "Client Office").
    Coordinates are used as cache keys for travel time lookups.
    """

    __tablename__ = "job_sites"

    address: Mapped[str] = mapped_column(Text, nullable=False)
    latitude: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    longitude: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    name: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Relationships
    bookings: Mapped[list[Booking]] = relationship(
        "Booking",
        back_populates="job_site",
        lazy="raise",
    )


class Booking(TenantScopedModel):
    """Scheduled time block for a contractor.

    Core safety mechanism: EXCLUDE USING GIST (contractor_id WITH =, time_range WITH &&)
    WHERE (deleted_at IS NULL) prevents overlapping bookings for the same contractor
    at the database level. This is a belt-and-suspenders safety net on top of the
    application-level SELECT FOR UPDATE lock.

    IMPORTANT: The ExcludeConstraint in __table_args__ is for ORM documentation only.
    The actual constraint is defined in migration 0007 via raw SQL. Do NOT run
    `alembic revision --autogenerate` on this model — it will produce broken migration code.

    time_range: Half-open TSTZRANGE [start, end) stored in UTC.
    day_index: None for single-day bookings; 0-based index for multi-day.
    parent_booking_id: Links all booking records for the same multi-day job.
    job_id: UUID referencing the jobs table (Phase 4). FK will be added in Phase 4.
    """

    __tablename__ = "bookings"

    contractor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    job_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    job_site_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("job_sites.id"),
        nullable=True,
    )
    time_range: Mapped[Range[datetime]] = mapped_column(TSTZRANGE, nullable=False)
    day_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    parent_booking_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("bookings.id"),
        nullable=True,
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    # ORM documentation of the GIST constraint (actual enforcement is in migration 0007)
    __table_args__ = (
        ExcludeConstraint(
            ("contractor_id", "="),
            ("time_range", "&&"),
            name="bookings_contractor_id_time_range_excl",
            where="deleted_at IS NULL",
        ),
    )

    # Relationships
    contractor: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )
    job_site: Mapped[JobSite | None] = relationship(
        "JobSite",
        foreign_keys=[job_site_id],
        back_populates="bookings",
        lazy="raise",
    )
    child_bookings: Mapped[list[Booking]] = relationship(
        "Booking",
        foreign_keys=[parent_booking_id],
        back_populates="parent_booking",
        lazy="raise",
    )
    parent_booking: Mapped[Booking | None] = relationship(
        "Booking",
        foreign_keys=[parent_booking_id],
        back_populates="child_bookings",
        remote_side="Booking.id",
        lazy="raise",
    )


class TravelTimeCache(Base):
    """Cached OpenRouteService travel-time results.

    Cache key: (company_id, lat1, lng1, lat2, lng2) — UNIQUE constraint.
    Coordinates stored as NUMERIC(9,6) matching the precision used in job_sites.
    TTL (30 days) is enforced at application level by checking fetched_at.

    Uses Base directly (NOT BaseEntityModel or TenantScopedModel) because:
    - travel_time_cache has no version, deleted_at columns — it is a cache, not a versioned entity
    - The company_id FK is for cache scoping, not for a full RLS tenant policy
    - No RLS policy on this table — reads are scoped by the service layer
    - fetched_at replaces updated_at; no created_at (fetched_at serves both purposes)
    """

    __tablename__ = "travel_time_cache"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="gen_random_uuid()",
    )
    company_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("companies.id"),
        nullable=False,
    )
    lat1: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    lng1: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    lat2: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    lng2: Mapped[Decimal] = mapped_column(Numeric(9, 6), nullable=False)
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    fetched_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
