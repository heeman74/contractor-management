"""SQLAlchemy ORM models for the job lifecycle domain.

Eight models correspond to the tables across migrations 0008 and 0009:
  - Job             — core job record with status machine and full-text search
  - ClientProfile   — CRM record linking a user to a tenant's client roster
  - ClientProperty  — property/job-site association per client
  - JobRequest      — inbound client request, convertible to a Job
  - Rating          — star rating for a completed job (direction-aware)
  - JobNote         — contractor/admin notes attached to a job (migration 0009)
  - Attachment      — file attachments linked to a job note (migration 0009)
  - TimeEntry       — contractor clock-in/clock-out session for a job (migration 0009)

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
  (established Phase 3 pattern used in scheduling/models.py)

IMPORTANT: The bookings.job_id FK was added in migration 0008 (ALTER TABLE).
The Job.bookings relationship uses primaryjoin with foreign() to tell SQLAlchemy
about this FK since Booking.job_id has no ORM-level ForeignKey() declaration
(the FK exists only at the database level via migration 0007/0008).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.scheduling.models import Booking, JobSite
    from app.features.users.models import User


class Job(TenantScopedModel):
    """Core job lifecycle record.

    status: 6-value state machine — quote -> scheduled -> in_progress
            -> complete -> invoiced | cancelled
    status_history: JSONB array recording each transition with timestamp,
                    user_id, and optional reason (for audit trail).
    priority: low / medium / high / urgent
    search_vector: populated by DB trigger on INSERT/UPDATE of description/notes
    version: used for optimistic locking in JobTransitionRequest (Pitfall 2)

    Relationships:
    - client: nullable — job may exist before client is assigned
    - contractor: nullable — quote phase may not have contractor yet
    - bookings: one-to-many — single or multi-day bookings for this job.
      Uses primaryjoin with foreign() because Booking.job_id has no ORM-level
      ForeignKey() — the FK exists only in the DB (added in migration 0008).
    - job_requests: one-to-many — requests that converted to this job
    - ratings: one-to-many — star ratings (max 2: one per direction)
    """

    __tablename__ = "jobs"

    description: Mapped[str] = mapped_column(Text, nullable=False)
    trade_type: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="quote")
    status_history: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )
    priority: Mapped[str] = mapped_column(Text, nullable=False, server_default="medium")
    client_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=True,
    )
    contractor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=True,
    )
    purchase_order_number: Mapped[str | None] = mapped_column(Text, nullable=True)
    external_reference: Mapped[str | None] = mapped_column(Text, nullable=True)
    tags: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    estimated_duration_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    scheduled_completion_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    # search_vector is managed by DB trigger — read-only from ORM perspective
    # Using Text as a stand-in; the actual TSVECTOR type is not needed for ORM reads
    # since full-text search is executed via raw SQL in the repository layer.

    # GPS columns added in migration 0009 for field workflow location tracking
    gps_latitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)
    gps_longitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)
    gps_address: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status IN ('quote','scheduled','in_progress','complete','invoiced','cancelled')",
            name="jobs_status_check",
        ),
        CheckConstraint(
            "priority IN ('low','medium','high','urgent')",
            name="jobs_priority_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    client: Mapped[User | None] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[client_id],
        lazy="raise",
    )
    contractor: Mapped[User | None] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )
    bookings: Mapped[list[Booking]] = relationship(  # type: ignore[name-defined]
        "Booking",
        primaryjoin="foreign(Booking.job_id) == Job.id",
        lazy="raise",
    )
    job_requests: Mapped[list[JobRequest]] = relationship(
        "JobRequest",
        back_populates="converted_job",
        foreign_keys="[JobRequest.converted_job_id]",
        lazy="raise",
    )
    ratings: Mapped[list[Rating]] = relationship(
        "Rating",
        back_populates="job",
        lazy="raise",
    )
    job_notes: Mapped[list[JobNote]] = relationship(
        "JobNote",
        back_populates="job",
        lazy="raise",
    )
    time_entries: Mapped[list[TimeEntry]] = relationship(
        "TimeEntry",
        back_populates="job",
        lazy="raise",
    )


class ClientProfile(TenantScopedModel):
    """CRM record linking a user to a tenant's client roster.

    One record per user per company (user_id UNIQUE enforced at DB level).
    average_rating is denormalized from the ratings table and updated by
    the application when a new rating is added.
    preferred_contractor_id: optional FK — client's preferred contractor.
    """

    __tablename__ = "client_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
        unique=True,
    )
    billing_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    tags: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
    admin_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    referral_source: Mapped[str | None] = mapped_column(Text, nullable=True)
    preferred_contractor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=True,
    )
    preferred_contact_method: Mapped[str | None] = mapped_column(Text, nullable=True)
    average_rating: Mapped[Decimal | None] = mapped_column(Numeric(3, 2), nullable=True)

    # Relationships
    user: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[user_id],
        lazy="raise",
    )
    preferred_contractor: Mapped[User | None] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[preferred_contractor_id],
        lazy="raise",
    )
    properties: Mapped[list[ClientProperty]] = relationship(
        "ClientProperty",
        back_populates="client_profile",
        primaryjoin="ClientProfile.user_id == foreign(ClientProperty.client_id)",
        lazy="raise",
    )


class ClientProperty(TenantScopedModel):
    """Property/job-site association for a client.

    A client may own multiple properties (job sites). is_default marks the
    primary property. nickname is a human-readable label (e.g., 'Home', 'Office').
    """

    __tablename__ = "client_properties"

    client_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    job_site_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("job_sites.id"),
        nullable=False,
    )
    nickname: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    # Relationships
    client: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[client_id],
        lazy="raise",
    )
    job_site: Mapped[JobSite] = relationship(  # type: ignore[name-defined]
        "JobSite",
        foreign_keys=[job_site_id],
        lazy="raise",
    )
    client_profile: Mapped[ClientProfile | None] = relationship(
        "ClientProfile",
        primaryjoin="foreign(ClientProperty.client_id) == ClientProfile.user_id",
        back_populates="properties",
        lazy="raise",
    )


class JobRequest(TenantScopedModel):
    """Inbound request from a client, convertible to a Job.

    Can be submitted anonymously (client_id NULL, submitted_name/email/phone set)
    or by an authenticated client (client_id set).
    When accepted: converted_job_id is set to the resulting Job.id.
    urgency: client-indicated (normal / urgent) — not the same as job priority.
    """

    __tablename__ = "job_requests"

    client_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=True,
    )
    description: Mapped[str] = mapped_column(Text, nullable=False)
    trade_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    urgency: Mapped[str] = mapped_column(Text, nullable=False, server_default="normal")
    preferred_date_start: Mapped[date | None] = mapped_column(Date, nullable=True)
    preferred_date_end: Mapped[date | None] = mapped_column(Date, nullable=True)
    budget_min: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    budget_max: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    photos: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="pending")
    decline_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    decline_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    converted_job_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("jobs.id"),
        nullable=True,
    )
    submitted_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    submitted_email: Mapped[str | None] = mapped_column(Text, nullable=True)
    submitted_phone: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "urgency IN ('normal','urgent')",
            name="job_requests_urgency_check",
        ),
        CheckConstraint(
            "status IN ('pending','accepted','declined','info_requested')",
            name="job_requests_status_check",
        ),
    )

    # Relationships
    client: Mapped[User | None] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[client_id],
        lazy="raise",
    )
    converted_job: Mapped[Job | None] = relationship(
        "Job",
        foreign_keys=[converted_job_id],
        back_populates="job_requests",
        lazy="raise",
    )


class Rating(TenantScopedModel):
    """Star rating for a completed job.

    direction: who is rating whom.
    - admin_to_client: company/admin rates the client's conduct
    - client_to_company: client rates the company's service

    UNIQUE (job_id, direction): one rating per direction per job (enforced at DB level).
    stars: 1-5 integer (enforced at DB level via CHECK constraint).
    """

    __tablename__ = "ratings"

    job_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("jobs.id"),
        nullable=False,
    )
    rater_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    ratee_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    direction: Mapped[str] = mapped_column(Text, nullable=False)
    stars: Mapped[int] = mapped_column(Integer, nullable=False)
    review_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "direction IN ('admin_to_client','client_to_company')",
            name="ratings_direction_check",
        ),
        CheckConstraint(
            "stars BETWEEN 1 AND 5",
            name="ratings_stars_check",
        ),
        UniqueConstraint("job_id", "direction", name="ratings_job_id_direction_key"),
    )

    # Relationships
    job: Mapped[Job] = relationship(
        "Job",
        foreign_keys=[job_id],
        back_populates="ratings",
        lazy="raise",
    )
    rater: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[rater_id],
        lazy="raise",
    )
    ratee: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[ratee_id],
        lazy="raise",
    )


# ---------------------------------------------------------------------------
# Phase 6 — Field workflow models (migration 0009)
# ---------------------------------------------------------------------------


class JobNote(TenantScopedModel):
    """A note written by a contractor or admin on a job.

    Each note belongs to a job and has an author (user). Optional file
    attachments are stored in the attachments table (linked via note_id).
    body: plain-text content (max 2000 chars enforced at API/Pydantic layer).
    version: used for sync delta tracking and optimistic locking.
    deleted_at: soft-delete — notes are never hard-deleted.
    """

    __tablename__ = "job_notes"

    job_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("jobs.id"),
        nullable=False,
    )
    author_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    job: Mapped[Job] = relationship(
        "Job",
        foreign_keys=[job_id],
        back_populates="job_notes",
        lazy="raise",
    )
    author: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[author_id],
        lazy="raise",
    )
    attachments: Mapped[list[Attachment]] = relationship(
        "Attachment",
        back_populates="note",
        lazy="raise",
    )


class Attachment(TenantScopedModel):
    """A file attachment linked to a job note.

    attachment_type: photo / pdf / drawing (enforced via DB CHECK constraint).
    remote_url: path to the file served by the static files endpoint
      (e.g. /files/attachments/{note_id}/{filename}).
    sort_order: display ordering within a note (default 0).
    caption: optional human-readable label.
    """

    __tablename__ = "attachments"

    note_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("job_notes.id"),
        nullable=False,
    )
    attachment_type: Mapped[str] = mapped_column(Text, nullable=False)
    remote_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint(
            "attachment_type IN ('photo','pdf','drawing')",
            name="attachments_type_check",
        ),
    )

    # Relationships
    note: Mapped[JobNote] = relationship(
        "JobNote",
        foreign_keys=[note_id],
        back_populates="attachments",
        lazy="raise",
    )


class TimeEntry(TenantScopedModel):
    """A contractor clock-in/clock-out work session for a job.

    clocked_in_at: when the contractor started work (required).
    clocked_out_at: when the contractor stopped (null = still active).
    duration_seconds: computed on clock-out (may differ from simple diff due to
      break time or admin adjustments).
    session_status: active (still clocked in) / completed (clocked out normally) /
      adjusted (admin-edited the times after the fact).
    adjustment_log: JSONB array of admin edits, each entry records:
      {adjusted_by, reason, old_clocked_in_at, old_clocked_out_at,
       new_clocked_in_at, new_clocked_out_at, timestamp}
    """

    __tablename__ = "time_entries"

    job_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("jobs.id"),
        nullable=False,
    )
    contractor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    clocked_in_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    clocked_out_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    session_status: Mapped[str] = mapped_column(Text, nullable=False, server_default="active")
    adjustment_log: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )

    __table_args__ = (
        CheckConstraint(
            "session_status IN ('active','completed','adjusted')",
            name="time_entries_session_status_check",
        ),
    )

    # Relationships
    job: Mapped[Job] = relationship(
        "Job",
        foreign_keys=[job_id],
        back_populates="time_entries",
        lazy="raise",
    )
    contractor: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )
