"""SQLAlchemy ORM models for the foreman role feature.

Two models correspond to tables created in migration 0025_foreman_role:
  - ProjectAssignment    — maps a foreman user to a project
  - ProjectStatusUpdate  — daily site status report written by a foreman

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.projects.models import Project
    from app.features.users.models import User


class ProjectAssignment(TenantScopedModel):
    """Maps a user (foreman) to a project with a project-level role.

    role: currently only 'foreman' — extensible for future project-level roles.
    assigned_at: when the assignment was created (distinct from created_at for audit).

    Partial unique index (in migration): one active assignment per
    (company_id, project_id, user_id, role) WHERE deleted_at IS NULL.

    Relationships:
    - project: many-to-one FK to projects
    - user: many-to-one FK to users
    """

    __tablename__ = "project_assignments"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(Text, nullable=False)
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default="now()",
    )

    __table_args__ = (
        CheckConstraint(
            "role IN ('foreman', 'lead', 'inspector', 'project_manager', 'contractor')",
            name="project_assignments_role_check",
        ),
    )

    # Relationships — lazy="raise" per CLAUDE.md
    project: Mapped[Project] = relationship(
        "Project",
        foreign_keys=[project_id],
        lazy="raise",
    )
    user: Mapped[User] = relationship(
        "User",
        foreign_keys=[user_id],
        lazy="raise",
    )


class ProjectStatusUpdate(TenantScopedModel):
    """Daily site status report written by a foreman.

    status_text: free-form daily status summary (required).
    weather_conditions: optional site weather conditions.
    workers_on_site: optional headcount for the day.
    safety_incidents: number of safety incidents (default 0).
    blockers: optional text describing current blockers.
    photos: JSONB array of photo URLs.
    report_date: the date this report covers (default today).

    Relationships:
    - project: many-to-one FK to projects
    - author: many-to-one FK to users (the foreman who wrote the report)
    """

    __tablename__ = "project_status_updates"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
    )
    author_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    status_text: Mapped[str] = mapped_column(Text, nullable=False)
    weather_conditions: Mapped[str | None] = mapped_column(Text, nullable=True)
    workers_on_site: Mapped[int | None] = mapped_column(Integer, nullable=True)
    safety_incidents: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    blockers: Mapped[str | None] = mapped_column(Text, nullable=True)
    photos: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")
    report_date: Mapped[date] = mapped_column(Date, nullable=False, server_default="CURRENT_DATE")

    # Relationships — lazy="raise" per CLAUDE.md
    project: Mapped[Project] = relationship(
        "Project",
        foreign_keys=[project_id],
        lazy="raise",
    )
    author: Mapped[User] = relationship(
        "User",
        foreign_keys=[author_id],
        lazy="raise",
    )
