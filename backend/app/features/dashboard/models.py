"""DashboardAlert ORM model — schedule slip and rescheduling alerts for GCs.

Each alert captures a detected schedule problem, an AI-generated impact explanation,
and optional rescheduling suggestions that the GC can accept or dismiss.
"""

from __future__ import annotations

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.projects.models import Project, TradeScope


class DashboardAlert(TenantScopedModel):
    """AI-generated alert for schedule slips, dependency risks, and rescheduling suggestions.

    severity: info | warning | critical — drives visual presentation in the dashboard
    alert_type: schedule_slip | rescheduling_suggestion | dependency_risk | budget_warning | budget_overrun
    days_behind: how many calendar days the affected trade scope is behind schedule
    impact_text: plain-English AI explanation of what this slip means for the project
    remediation_text: AI-generated suggestion for how to address the issue
    affected_scope_ids: JSONB array of trade_scope_id UUIDs affected downstream
    rescheduling_payload: JSONB with [{task_id, new_start_date, new_due_date, reason}]
    rescheduling_accepted: True = applied, False = dismissed, None = pending
    """

    __tablename__ = "dashboard_alerts"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
    )
    trade_scope_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="SET NULL"),
        nullable=True,
    )
    severity: Mapped[str] = mapped_column(Text, nullable=False)
    alert_type: Mapped[str] = mapped_column(Text, nullable=False)
    days_behind: Mapped[int | None] = mapped_column(Integer, nullable=True)
    impact_text: Mapped[str] = mapped_column(Text, nullable=False)
    remediation_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    affected_scope_ids: Mapped[list] = mapped_column(
        JSONB, nullable=False, server_default="'[]'::jsonb"
    )
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    rescheduling_payload: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    rescheduling_accepted: Mapped[bool | None] = mapped_column(Boolean, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "severity IN ('info','warning','critical')",
            name="dashboard_alerts_severity_check",
        ),
        CheckConstraint(
            "alert_type IN ('schedule_slip','rescheduling_suggestion','dependency_risk',"
            "'budget_warning','budget_overrun')",
            name="dashboard_alerts_alert_type_check",
        ),
    )

    # BP-1: Relationships with lazy="raise" per CLAUDE.md rules
    project: Mapped[Project] = relationship(  # type: ignore[name-defined]
        "Project",
        foreign_keys=[project_id],
        lazy="raise",
    )
    trade_scope: Mapped[TradeScope | None] = relationship(  # type: ignore[name-defined]
        "TradeScope",
        foreign_keys=[trade_scope_id],
        lazy="raise",
    )
