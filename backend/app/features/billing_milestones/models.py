"""SQLAlchemy ORM model for billing milestones.

BillingMilestone represents a named payment milestone within a trade scope,
with a percentage of the total scope value and an invoiced flag for double-billing prevention.

All CLAUDE.md rules apply:
- Model inherits TenantScopedModel (provides id, company_id, version, timestamps)
- relationship() uses lazy="raise" to surface accidental lazy loads loudly
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, Numeric, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.projects.models import TradeScope


class BillingMilestone(TenantScopedModel):
    """A named payment milestone within a trade scope.

    Milestones define when payment is due during a trade's work lifecycle.
    percentage: share of the total scope contract value (0 < percentage <= 100).
    is_invoiced: set to True atomically when an invoice is generated for this milestone;
                 prevents double-billing via atomic UPDATE ... WHERE is_invoiced=FALSE.
    sort_order: display ordering within a trade scope.

    Relationships:
    - trade_scope: many-to-one FK to trade_scopes (ON DELETE CASCADE)
    """

    __tablename__ = "billing_milestones"

    trade_scope_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    percentage: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_invoiced: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint(
            "percentage > 0 AND percentage <= 100",
            name="billing_milestones_percentage_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    trade_scope: Mapped[TradeScope] = relationship(  # type: ignore[name-defined]
        "TradeScope",
        foreign_keys=[trade_scope_id],
        lazy="raise",
    )
