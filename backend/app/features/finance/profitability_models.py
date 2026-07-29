"""ORM model for AI profitability findings (migration 0036).

One row per published AI profitability finding. The nightly analysis upserts on
(company_id, fingerprint) restricted to OPEN rows, so a re-detected problem
restates its text without re-arming its alert, and a resolved problem that
recurs inserts a fresh, unalerted row.

All CLAUDE.md rules apply:
- Relationships declare lazy="raise" so an accidental lazy load fails loudly
- Inherits TenantScopedModel (id, company_id, version, timestamps)
- from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, CheckConstraint, Date, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.projects.models import Project

MAX_ALERT_SUMMARY_LENGTH = 280
MAX_CORRECTIVE_ACTION_LENGTH = 280
MAX_NARRATIVE_LENGTH = 600


class AIProfitabilityFinding(TenantScopedModel):
    """One published AI profitability finding.

    signal: negative_margin | quote_gap | margin_decline — what was detected
    severity_band: warning | critical — drives alert presentation
    fingerprint: the dedup key; one open finding per (company_id, fingerprint)
    narrative / corrective_action / alert_summary: the AI-written text, length
        capped by DB CHECKs so over-length drafts are rejected, never truncated
    revenue_basis / labor_included: the honesty flags the figures were read under
    payload: the SC3 audit trail — the exact aggregates the text was grounded
        against. Without it a shipped finding cannot be re-verified against the
        figures it cited.
    alerted_at: set once, by claim_alert; a nightly restatement never re-arms it
    found_on / last_confirmed_on: first and most recent night this was detected
    """

    __tablename__ = "ai_profitability_findings"

    project_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=False,
    )
    signal: Mapped[str] = mapped_column(Text, nullable=False)
    severity_band: Mapped[str] = mapped_column(Text, nullable=False)
    fingerprint: Mapped[str] = mapped_column(Text, nullable=False)
    narrative: Mapped[str] = mapped_column(Text, nullable=False)
    corrective_action: Mapped[str] = mapped_column(Text, nullable=False)
    alert_summary: Mapped[str] = mapped_column(Text, nullable=False)
    revenue_basis: Mapped[str] = mapped_column(Text, nullable=False)
    labor_included: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    dashboard_alert_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("dashboard_alerts.id", ondelete="SET NULL"),
        nullable=True,
    )
    alerted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    found_on: Mapped[date] = mapped_column(Date, nullable=False)
    last_confirmed_on: Mapped[date] = mapped_column(Date, nullable=False)

    __table_args__ = (
        CheckConstraint(
            "signal IN ('negative_margin','quote_gap','margin_decline')",
            name="ai_profitability_findings_signal_check",
        ),
        CheckConstraint(
            "severity_band IN ('warning','critical')",
            name="ai_profitability_findings_band_check",
        ),
        CheckConstraint(
            f"char_length(alert_summary) <= {MAX_ALERT_SUMMARY_LENGTH}",
            name="ai_profitability_findings_alert_summary_length_check",
        ),
        CheckConstraint(
            f"char_length(corrective_action) <= {MAX_CORRECTIVE_ACTION_LENGTH}",
            name="ai_profitability_findings_action_length_check",
        ),
        CheckConstraint(
            f"char_length(narrative) <= {MAX_NARRATIVE_LENGTH}",
            name="ai_profitability_findings_narrative_length_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    project: Mapped[Project] = relationship(
        "Project",
        foreign_keys=[project_id],
        lazy="raise",
    )
