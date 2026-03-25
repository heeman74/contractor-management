"""SQLAlchemy ORM models for the GC Inspection Workflow.

Three models for Phase 24:
  - TaskInspection  — approve/reject record for a completed task
  - SiteWalkFlag    — issue flagged during a GC site walk
  - PunchListItem   — defect item that must be resolved before scope closeout

All models inherit TenantScopedModel (provides id, company_id, version, timestamps).
All relationships use lazy="raise" per CLAUDE.md rules.
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import CheckConstraint, Date, ForeignKey, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base_models import TenantScopedModel


class TaskInspection(TenantScopedModel):
    """Approve or reject record created when a GC inspects a completed task.

    decision: 'approved' or 'rejected'
    checklist_results: JSONB array of [{item: str, checked: bool}]
    rejection_reason: short reason code (e.g. "poor_quality")
    rejection_comment: longer free-text explanation
    rejection_photo_url: optional URL to a rejection evidence photo

    inspector_id is a soft FK — no hard FK to avoid cross-feature coupling
    (consistent with TaskNote.author_id pattern in Phase 22).

    If decision == 'rejected', the parent Task's status is set to 'rejected'
    by InspectionService, and successor tasks are re-blocked.
    """

    __tablename__ = "task_inspections"

    task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tasks.id", ondelete="CASCADE"),
        nullable=False,
    )
    inspector_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    decision: Mapped[str] = mapped_column(Text, nullable=False)
    checklist_results: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )
    rejection_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    rejection_comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    rejection_photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "decision IN ('approved','rejected')",
            name="task_inspections_decision_check",
        ),
    )


class SiteWalkFlag(TenantScopedModel):
    """An issue flagged by the GC during a site walk.

    severity: low / medium / high
    status:   open -> converted (when turned into a punch list item)
              open -> dismissed (when GC decides no action needed)

    flagged_by is a soft FK (no hard FK, consistent with TaskNote pattern).
    photo_url and annotation_data are nullable — flags may or may not have photos.
    """

    __tablename__ = "site_walk_flags"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
    )
    flagged_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    description: Mapped[str] = mapped_column(Text, nullable=False)
    severity: Mapped[str] = mapped_column(Text, nullable=False, server_default="'medium'")
    location_label: Mapped[str | None] = mapped_column(Text, nullable=True)
    photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    annotation_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="'open'")

    __table_args__ = (
        CheckConstraint(
            "severity IN ('low','medium','high')",
            name="site_walk_flags_severity_check",
        ),
        CheckConstraint(
            "status IN ('open','converted','dismissed')",
            name="site_walk_flags_status_check",
        ),
    )


class PunchListItem(TenantScopedModel):
    """A defect or open item that must be resolved before trade scope closeout.

    priority: low / medium / high / urgent
    status:   open -> in_progress -> resolved -> verified

    source_flag_id: nullable soft FK to site_walk_flags — set when the punch
    item was created by converting a flag. No hard FK to keep tables decoupled.

    created_by and assigned_to are soft FKs (no hard FK, consistent with pattern).
    """

    __tablename__ = "punch_list_items"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
    )
    trade_scope_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    assigned_to: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
    )
    description: Mapped[str] = mapped_column(Text, nullable=False)
    priority: Mapped[str] = mapped_column(Text, nullable=False, server_default="'medium'")
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="'open'")
    photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    annotation_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    source_flag_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
    )
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "priority IN ('low','medium','high','urgent')",
            name="punch_list_items_priority_check",
        ),
        CheckConstraint(
            "status IN ('open','in_progress','resolved','verified')",
            name="punch_list_items_status_check",
        ),
    )
