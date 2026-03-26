"""DailyChecklist ORM model — AI-generated per-contractor daily task lists.

Each record represents one contractor's checklist for a specific trade scope on a given date.
Idempotent: the unique constraint allows safe upsert (re-generate without duplicates).
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Boolean, Date, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base_models import TenantScopedModel


class DailyChecklist(TenantScopedModel):
    """AI-generated daily task checklist for a contractor on a specific trade scope.

    checklist_json: structured JSON matching ChecklistItemSchema
    summary_text: plain-English summary pushed via FCM ("You have 5 tasks today: ...")
    is_pushed: True after FCM notification has been dispatched

    Unique constraint prevents duplicate checklists for the same contractor + scope + date.
    ON CONFLICT DO UPDATE allows safe idempotent regeneration (cron re-runs, backfill).
    """

    __tablename__ = "daily_checklists"

    contractor_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    trade_scope_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    checklist_date: Mapped[date] = mapped_column(Date, nullable=False)
    checklist_json: Mapped[dict] = mapped_column(
        JSONB, nullable=False, server_default="'{}'::jsonb"
    )
    summary_text: Mapped[str] = mapped_column(Text, nullable=False)
    is_pushed: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    __table_args__ = (
        UniqueConstraint(
            "company_id",
            "contractor_id",
            "trade_scope_id",
            "checklist_date",
            name="uq_daily_checklist_contractor_scope_date",
        ),
    )
