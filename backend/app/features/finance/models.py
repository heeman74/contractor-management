"""SQLAlchemy ORM models for the finance domain.

Five models correspond to the tables created in migration 0032:
  - CostCategory              — company-scoped cost category catalog (4 protected
                                 system categories seeded per company: labor,
                                 materials, subcontractor, other)
  - CostEntry                 — an actual cost anchored to a job XOR a trade scope
  - LaborRate                 — effective-dated hourly cost for a worker (per D-07/D-08,
                                 keeps historical margins reproducible after rate changes)
  - Budget                    — a budget anchored to a project XOR a trade scope
  - BudgetCategoryBreakdown   — per-category allocation of a budget's total

CostReceipt corresponds to the table created in migration 0034 (Phase 31) — a
zero-to-many receipt attachment on a CostEntry (D-04).

No CRUD layer (repository/service/router) ships for CostEntry/CostCategory/Budget
in Phase 30 — see 31-01-PLAN.md/31-02-PLAN.md for the finance CRUD layer.

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import Boolean, Date, ForeignKey, Index, Numeric, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel


class CostCategory(TenantScopedModel):
    """Company-scoped cost category catalog.

    is_system: True for the four protected default categories (labor, materials,
    subcontractor, other) seeded per company by migration 0032 — these cannot be
    deleted (delete-guard enforced by the Phase 31 service layer, not the DB).

    UNIQUE(company_id, name): prevents duplicate category names per company.
    """

    __tablename__ = "cost_categories"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    __table_args__ = (
        UniqueConstraint("company_id", "name", name="uq_cost_categories_company_name"),
    )


class CostEntry(TenantScopedModel):
    """An actual cost incurred against a job or a trade scope.

    job_id XOR trade_scope_id: exactly one must be set (schema validator enforces
    this — see CostEntryCreate.validate_fields). Soft-anchor style, consistent with
    the polymorphic Quote/Invoice anchors — no relationship() is declared for
    job_id/trade_scope_id to avoid lazy-load footguns on the anchor side.

    Relationships:
    - category: many-to-one FK to cost_categories
    """

    __tablename__ = "cost_entries"

    job_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("jobs.id", ondelete="CASCADE"),
        nullable=True,
    )
    trade_scope_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="CASCADE"),
        nullable=True,
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("cost_categories.id"),
        nullable=False,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    incurred_date: Mapped[date] = mapped_column(Date, nullable=False)
    vendor: Mapped[str | None] = mapped_column(Text, nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    category: Mapped[CostCategory] = relationship(
        "CostCategory",
        foreign_keys=[category_id],
        lazy="raise",
    )


class CostReceipt(TenantScopedModel):
    """A receipt image/document attached to a cost entry (zero-to-many, D-04).

    Served through the authenticated /files/cost-receipts/{cost_entry_id}/{filename}
    route (serve_router.py, added in Plan 31-02). Upload/serve endpoints land in
    Plan 31-02 — this plan only defines the table + RLS + model.
    """

    __tablename__ = "cost_receipts"

    cost_entry_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("cost_entries.id", ondelete="CASCADE"),
        nullable=False,
    )
    remote_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    cost_entry: Mapped[CostEntry] = relationship(
        "CostEntry",
        foreign_keys=[cost_entry_id],
        lazy="raise",
    )


class LaborRate(TenantScopedModel):
    """Effective-dated hourly cost for a worker.

    Per D-07/D-08: an append-only, effective-dated table (not a mutable single
    column on User) so historical margins stay reproducible after a worker's rate
    changes. user_id is a soft FK (no hard FK) to the worker, consistent with the
    TaskNote.author_id pattern elsewhere in the codebase.
    """

    __tablename__ = "labor_rates"

    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    hourly_cost: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    effective_from: Mapped[date] = mapped_column(Date, nullable=False)

    __table_args__ = (
        Index(
            "ix_labor_rates_company_user_effective",
            "company_id",
            "user_id",
            "effective_from",
        ),
    )


class Budget(TenantScopedModel):
    """A budget anchored to a project or a trade scope.

    project_id XOR trade_scope_id: exactly one must be set (schema validator
    enforces this — see BudgetCreate.validate_fields). IMPORTANT ASYMMETRY vs
    CostEntry: Budget anchors on project_id (not job_id) per D-09.

    Relationships:
    - breakdowns: one-to-many — per-category allocation of this budget's total
    """

    __tablename__ = "budgets"

    project_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("projects.id", ondelete="CASCADE"),
        nullable=True,
    )
    trade_scope_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trade_scopes.id", ondelete="CASCADE"),
        nullable=True,
    )
    total: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    breakdowns: Mapped[list[BudgetCategoryBreakdown]] = relationship(
        "BudgetCategoryBreakdown",
        back_populates="budget",
        cascade="all, delete-orphan",
        lazy="raise",
    )


class BudgetCategoryBreakdown(TenantScopedModel):
    """Per-category allocation of a budget's total.

    The sum of a budget's breakdown amounts must not exceed the budget total
    (schema validator enforces this — see BudgetCreate.validate_fields).

    Relationships:
    - budget: many-to-one FK to budgets
    - category: many-to-one FK to cost_categories
    """

    __tablename__ = "budget_category_breakdowns"

    budget_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("budgets.id", ondelete="CASCADE"),
        nullable=False,
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("cost_categories.id"),
        nullable=False,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    budget: Mapped[Budget] = relationship(
        "Budget",
        foreign_keys=[budget_id],
        back_populates="breakdowns",
        lazy="raise",
    )
    category: Mapped[CostCategory] = relationship(
        "CostCategory",
        foreign_keys=[category_id],
        lazy="raise",
    )
