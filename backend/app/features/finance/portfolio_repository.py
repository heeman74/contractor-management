"""PortfolioRepository — batched, company-wide finance aggregates (MARG-04).

Every method here is ONE grouped, column-only round trip covering the whole
tenant. Nothing is per project: the company overview must stay constant in
project count (CLAUDE.md's no-query-in-a-loop rule at company scale), so
`FinanceService.rollup_for_project` is never called from this path.

The traversal predicates are NOT restated here — the public module-level query
builders in `repository.py` are composed instead, so the batched path and the
shipped per-project path can only ever share one definition.

PROJECT_KEY is COALESCE(TradeScope.project_id, Job.project_id): CostEntry,
Invoice and Quote each anchor job XOR trade_scope, so at most one outer join
yields a project id, and rows where both are NULL drop out — exactly the set the
shipped `(TradeScope.project_id == pid) | (Job.project_id == pid)` filter
selects. PostgreSQL's functional-dependency shortcut does not reach an
expression over other tables, so PROJECT_KEY must appear in `group_by` as well
as `select` (RESEARCH Pitfall 7).

Row-access rule: the project key is always read from a result row BY LABEL —
`row.project_id` — never by positional index, and `to_anchored_amounts` keeps
its `row[:6]` contract untouched. Plan 35-07 appends `issued_at` / `approved_on`
at indices 6 and 7 of the same shared builders; any positional read of the
project key here would silently break when that lands.

Pitfall 8: `BaseRepository.list_all()` does NOT filter `deleted_at`, so every
query below states its soft-delete predicate at its own call site rather than
inheriting one silently.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Row, Select, func, select

from app.core.base_repository import TenantScopedRepository
from app.features.finance.labor_derivation import WorkSession
from app.features.finance.margin_math import DocumentAmounts, RevenueAnchor
from app.features.finance.models import CostCategory, CostEntry
from app.features.finance.repository import (
    approved_quote_amounts_query,
    costable_sessions_query,
    invoice_amounts_query,
    to_anchored_amounts,
    to_work_sessions,
)
from app.features.invoices.models import Invoice
from app.features.jobs.models import Job, TimeEntry
from app.features.projects.models import Project, TradeScope
from app.features.quotes.models import Quote

PROJECT_KEY = func.coalesce(TradeScope.project_id, Job.project_id)
PROJECT_KEY_COLUMN = PROJECT_KEY.label("project_id")

type _SessionColumns = tuple[uuid.UUID, datetime, int, uuid.UUID | None]
type _AnchoredAmounts = tuple[uuid.UUID, RevenueAnchor, DocumentAmounts]


def _keyed_by_project(query: Select, document: type[Invoice] | type[Quote]) -> Select:
    """Tag a document aggregate with its project via the shipped dual-outerjoin traversal."""
    return (
        query.add_columns(PROJECT_KEY_COLUMN)
        .outerjoin(TradeScope, document.trade_scope_id == TradeScope.id)
        .outerjoin(Job, document.job_id == Job.id)
        .where(document.deleted_at.is_(None), PROJECT_KEY.is_not(None))
        .group_by(PROJECT_KEY)
    )


def _session_columns(row: Row) -> _SessionColumns:
    """The four costable_sessions_query columns, read by label so appended ones cannot shift them."""
    return (row.contractor_id, row.clocked_in_at, row.duration_seconds, row.job_id)


def _to_project_anchored_amounts(row: Row) -> _AnchoredAmounts:
    """One project-keyed document aggregate as margin_math value objects."""
    anchor, amounts = to_anchored_amounts(row)
    return row.project_id, anchor, amounts


class PortfolioRepository(TenantScopedRepository[Project]):
    """Company-wide finance aggregates, each in a fixed number of round trips."""

    model = Project

    async def list_projects(self) -> list[Row]:
        """Every live project's id, name and status, alphabetically — 1 round trip."""
        result = await self.db.execute(
            select(Project.id, Project.name, Project.status)
            .where(Project.deleted_at.is_(None))
            .order_by(Project.name)
        )
        return list(result.all())

    async def category_totals_by_project(self) -> list[Row]:
        """Per-(project, anchor, category) cost sums for the whole tenant — 1 round trip.

        The anchor columns ride along so the caller can compute the D-12
        missing-cost flag per revenue anchor without a second pass.

        Pinned to FinanceService.rollup_for_project by
        test_company_rollup_matches_rollup_for_project (backend/tests/test_phase_35_e2e.py)
        — edit either side only with that test in view.
        """
        result = await self.db.execute(
            select(
                PROJECT_KEY_COLUMN,
                CostEntry.job_id,
                CostEntry.trade_scope_id,
                CostCategory.id.label("category_id"),
                CostCategory.name.label("category_name"),
                func.sum(CostEntry.amount).label("total"),
            )
            .select_from(CostEntry)
            .join(CostCategory, CostEntry.category_id == CostCategory.id)
            .outerjoin(TradeScope, CostEntry.trade_scope_id == TradeScope.id)
            .outerjoin(Job, CostEntry.job_id == Job.id)
            .where(CostEntry.deleted_at.is_(None), PROJECT_KEY.is_not(None))
            .group_by(
                PROJECT_KEY,
                CostEntry.job_id,
                CostEntry.trade_scope_id,
                CostCategory.id,
                CostCategory.name,
            )
        )
        return list(result.all())

    async def work_sessions_by_project(self) -> list[tuple[uuid.UUID, WorkSession]]:
        """Every costable session in the tenant, tagged with its job's project — 1 round trip."""
        result = await self.db.execute(
            costable_sessions_query()
            .join(Job, TimeEntry.job_id == Job.id)
            .add_columns(Job.project_id.label("project_id"))
            .where(TimeEntry.deleted_at.is_(None), Job.project_id.is_not(None))
        )
        rows = result.all()
        sessions = to_work_sessions([_session_columns(row) for row in rows])
        return [(row.project_id, session) for row, session in zip(rows, sessions, strict=True)]

    async def invoice_amounts_by_project(self) -> list[_AnchoredAmounts]:
        """Every invoice in the tenant, tagged with its project and anchor — 1 round trip."""
        result = await self.db.execute(_keyed_by_project(invoice_amounts_query(), Invoice))
        return [_to_project_anchored_amounts(row) for row in result.all()]

    async def approved_quote_amounts_by_project(self) -> list[_AnchoredAmounts]:
        """Every approved quote, tagged with project and anchor, newest first — 1 round trip.

        The builder's created_at DESC order is preserved, so the FIRST row an
        anchor yields is still that anchor's latest approved quote (D-03).
        """
        result = await self.db.execute(_keyed_by_project(approved_quote_amounts_query(), Quote))
        return [_to_project_anchored_amounts(row) for row in result.all()]

    async def project_level_approved_quotes(self) -> dict[uuid.UUID, DocumentAmounts]:
        """The latest project-anchored approved quote per project — 1 round trip.

        D-14 candidates only: job_id AND trade_scope_id both NULL. Newest-first,
        so keeping the FIRST row per project keeps the latest approval.
        """
        result = await self.db.execute(
            approved_quote_amounts_query()
            .add_columns(Quote.project_id)
            .where(
                Quote.deleted_at.is_(None),
                Quote.project_id.is_not(None),
                Quote.job_id.is_(None),
                Quote.trade_scope_id.is_(None),
            )
            .group_by(Quote.project_id)
        )
        latest: dict[uuid.UUID, DocumentAmounts] = {}
        for row in result.all():
            latest.setdefault(row.project_id, to_anchored_amounts(row)[1])
        return latest

    async def project_header(self, project_id: uuid.UUID) -> Row | None:
        """(id, name, status) for one live project, or None — RLS scopes the tenant.

        Column-only: the drill-down needs no Project relationship, and a
        cross-tenant or soft-deleted id must read as absent, not as a row.
        """
        result = await self.db.execute(
            select(Project.id, Project.name, Project.status).where(
                Project.id == project_id, Project.deleted_at.is_(None)
            )
        )
        return result.first()

    async def trade_scopes_for_project(self, project_id: uuid.UUID) -> list[Row]:
        """(id, trade_name) for a project's live trade scopes, ordered by sort_order.

        Column-only: TradeScope relationships are lazy="raise" and the drill-down
        needs none of them.
        """
        result = await self.db.execute(
            select(TradeScope.id, TradeScope.trade_name)
            .where(TradeScope.project_id == project_id, TradeScope.deleted_at.is_(None))
            .order_by(TradeScope.sort_order)
        )
        return list(result.all())

    async def trade_scope_labels(
        self, trade_scope_ids: list[uuid.UUID]
    ) -> dict[uuid.UUID, tuple[uuid.UUID, str]]:
        """(scope id -> (project id, trade name)) for scope-budget anchor labels.

        Returns {} for an empty id list so no `IN ()` round trip is ever issued.
        """
        if not trade_scope_ids:
            return {}
        result = await self.db.execute(
            select(TradeScope.id, TradeScope.project_id, TradeScope.trade_name).where(
                TradeScope.id.in_(trade_scope_ids), TradeScope.deleted_at.is_(None)
            )
        )
        return {row.id: (row.project_id, row.trade_name) for row in result.all()}
