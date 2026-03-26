"""DailyChecklist ORM model — AI-generated per-contractor daily task lists.

Each record represents one contractor's checklist for a specific trade scope on a given date.
Idempotent: the unique constraint allows safe upsert (re-generate without duplicates).
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Date, ForeignKey, Index, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.projects.models import Project, TradeScope
    from app.features.users.models import User


class DailyChecklist(TenantScopedModel):
    """AI-generated daily task checklist for a contractor on a specific trade scope.

    checklist_json: structured JSON matching ChecklistItemSchema
    summary_text: plain-English summary pushed via FCM ("You have 5 tasks today: ...")
    is_pushed: True after FCM notification has been dispatched

    Unique constraint prevents duplicate checklists for the same contractor + scope + date.
    ON CONFLICT DO UPDATE allows safe idempotent regeneration (cron re-runs, backfill).
    """

    __tablename__ = "daily_checklists"

    contractor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
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
    checklist_date: Mapped[date] = mapped_column(Date, nullable=False)
    checklist_json: Mapped[dict] = mapped_column(
        JSONB, nullable=False, server_default="'{}'::jsonb"
    )
    summary_text: Mapped[str] = mapped_column(Text, nullable=False)
    is_pushed: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    # BP-8: Partial unique index (WHERE deleted_at IS NULL) instead of plain unique constraint.
    # Allows soft-deleted rows to coexist when regenerating checklists.
    __table_args__ = (
        Index(
            "uq_daily_checklist_contractor_scope_date",
            "company_id",
            "contractor_id",
            "trade_scope_id",
            "checklist_date",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )

    # BP-1: Relationships with lazy="raise" per CLAUDE.md rules
    contractor: Mapped[User] = relationship(  # type: ignore[name-defined]
        "User",
        foreign_keys=[contractor_id],
        lazy="raise",
    )
    project: Mapped[Project] = relationship(  # type: ignore[name-defined]
        "Project",
        foreign_keys=[project_id],
        lazy="raise",
    )
    trade_scope: Mapped[TradeScope] = relationship(  # type: ignore[name-defined]
        "TradeScope",
        foreign_keys=[trade_scope_id],
        lazy="raise",
    )
