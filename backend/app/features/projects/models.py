"""SQLAlchemy ORM models for the v3.0 project data model.

Six models correspond to the tables created in migration 0015:
  - Project            — top-level project entity with status machine
  - TradeCatalog       — company-configurable reference table for trade types
  - TradeScope         — a single trade assigned to a project (with optional contractor)
  - Task               — individual work item within a trade scope
  - TaskAttachment     — photo/video/document attached to a task
  - UserTradeSpecialty — join table linking contractors to their trade specialties

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
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
    from app.features.users.models import User


class Project(TenantScopedModel):
    """Top-level project entity.

    status: 6-value state machine — draft -> planning -> active -> on_hold
            -> complete -> archived
    status_history: JSONB array recording each transition with timestamp,
                    user_id, and optional reason (for audit trail).
    Semi-automatic transitions: Draft->Planning when first trade scope added,
    Planning->Active when first task started. GC must manually complete/archive.

    Relationships:
    - client: nullable FK to users — reuses CRM data
    - trade_scopes: one-to-many — all scopes under this project
    """

    __tablename__ = "projects"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    address: Mapped[str | None] = mapped_column(Text, nullable=True)
    client_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=True,
    )
    target_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    target_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="draft")
    status_history: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('draft','planning','active','on_hold','complete','archived')",
            name="projects_status_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    client: Mapped[User | None] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[client_id],
        lazy="raise",
    )
    trade_scopes: Mapped[list[TradeScope]] = relationship(
        "TradeScope",
        back_populates="project",
        lazy="raise",
    )


class TradeCatalog(TenantScopedModel):
    """Company-configurable reference table for trade types.

    Each entry has a name and color. GC can pick from catalog OR type an
    ad-hoc trade when creating a scope. Ad-hoc trades trigger a
    "Save to catalog?" prompt — not auto-saved.

    UNIQUE(company_id, name): prevents duplicate trade names per company.
    Data migration 0015 seeds this from Jobs.trade_type and Companies.trade_types.
    """

    __tablename__ = "trade_catalog"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    color: Mapped[str] = mapped_column(Text, nullable=False, server_default="'#9E9E9E'")

    __table_args__ = (UniqueConstraint("company_id", "name", name="uq_trade_catalog_company_name"),)


class TradeScope(TenantScopedModel):
    """A single trade assigned to a project.

    One contractor per trade scope. If two electricians needed, create two
    scopes (e.g. "Electrical - Main", "Electrical - Low Voltage").
    contractor_id is nullable — GC assigns later.

    status: not_started -> in_progress -> complete -> approved
    status_override: when True, GC has manually set status (overrides computed value)
    sort_order: display ordering within a project

    Relationships:
    - project: many-to-one FK to projects
    - contractor: nullable FK to users
    - trade_catalog: nullable FK — null when ad-hoc trade used
    - tasks: one-to-many — all tasks under this scope
    """

    __tablename__ = "trade_scopes"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
    )
    trade_catalog_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_catalog.id"),
        nullable=True,
    )
    trade_name: Mapped[str] = mapped_column(Text, nullable=False)
    trade_color: Mapped[str] = mapped_column(Text, nullable=False, server_default="'#9E9E9E'")
    contractor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=True,
    )
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="not_started")
    status_override: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint(
            "status IN ('not_started','in_progress','complete','approved')",
            name="trade_scopes_status_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    project: Mapped[Project] = relationship(
        "Project",
        back_populates="trade_scopes",
        lazy="raise",
    )
    contractor: Mapped[User | None] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )
    trade_catalog: Mapped[TradeCatalog | None] = relationship(
        "TradeCatalog",
        foreign_keys=[trade_catalog_id],
        lazy="raise",
    )
    tasks: Mapped[list[Task]] = relationship(
        "Task",
        back_populates="trade_scope",
        lazy="raise",
    )


class Task(TenantScopedModel):
    """Individual work item within a trade scope.

    Full construction task fields: title, description, estimated_hours,
    estimated_cost, sort_order, status, materials_needed (structured JSONB),
    photo_required, assigned_to, due_date, priority, depends_on (JSONB).

    Flat list within trade scope — no sub-tasks.
    Blocked status is auto-computed from unresolved dependencies (Phase 20).

    depends_on: JSONB array of task IDs for intra-scope dependencies.
    materials_needed: JSONB array [{name, quantity, unit}].

    Relationships:
    - trade_scope: many-to-one FK to trade_scopes
    - assignee: nullable FK to users
    - attachments: one-to-many — photos/videos/documents for this task
    """

    __tablename__ = "tasks"

    trade_scope_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="CASCADE"),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="not_started")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    priority: Mapped[str] = mapped_column(Text, nullable=False, server_default="'medium'")
    estimated_hours: Mapped[Decimal | None] = mapped_column(Numeric(6, 2), nullable=True)
    estimated_cost: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    photo_required: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    assigned_to: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=True,
    )
    materials_needed: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )
    depends_on: Mapped[list] = mapped_column(JSONB, nullable=False, server_default="'[]'::jsonb")

    __table_args__ = (
        CheckConstraint(
            "status IN ('not_started','in_progress','complete','blocked')",
            name="tasks_status_check",
        ),
        CheckConstraint(
            "priority IN ('low','medium','high','urgent')",
            name="tasks_priority_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    trade_scope: Mapped[TradeScope] = relationship(
        "TradeScope",
        back_populates="tasks",
        lazy="raise",
    )
    assignee: Mapped[User | None] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[assigned_to],
        lazy="raise",
    )
    attachments: Mapped[list[TaskAttachment]] = relationship(
        "TaskAttachment",
        back_populates="task",
        lazy="raise",
    )


class TaskAttachment(TenantScopedModel):
    """File attachment linked to a task.

    attachment_type: photo / video / document (distinct from existing
    Attachment model which supports photo/pdf/drawing — different types).

    remote_url: path served by the static files endpoint.
    local_path: device-local path for offline access on mobile.
    sort_order: display ordering within a task (default 0).

    Separate table from existing `attachments` — independent lifecycle
    and different attachment_type CHECK values (includes 'video').

    Relationships:
    - task: many-to-one FK to tasks
    """

    __tablename__ = "task_attachments"

    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
    )
    attachment_type: Mapped[str] = mapped_column(Text, nullable=False)
    remote_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    local_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint(
            "attachment_type IN ('photo','video','document')",
            name="task_attachments_type_check",
        ),
    )

    # Relationships
    task: Mapped[Task] = relationship(
        "Task",
        back_populates="attachments",
        lazy="raise",
    )


class UserTradeSpecialty(TenantScopedModel):
    """Join table linking contractors to their trade specialties.

    UNIQUE(user_id, trade_catalog_id): prevents duplicate specialty entries.
    This is a join table (not JSONB on User) because it must be queryable —
    when GC assigns a scope, the endpoint can return matching contractors first.

    Relationships:
    - user: FK to users
    - trade: FK to trade_catalog
    """

    __tablename__ = "user_trade_specialties"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    trade_catalog_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_catalog.id"),
        nullable=False,
    )

    __table_args__ = (UniqueConstraint("user_id", "trade_catalog_id", name="uq_user_trade"),)

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    user: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[user_id],
        lazy="raise",
    )
    trade: Mapped[TradeCatalog] = relationship(
        "TradeCatalog",
        foreign_keys=[trade_catalog_id],
        lazy="raise",
    )
