"""Phase 35 — Web Financial Dashboard.

Covers MARG-04 (company rollup, project financials, margin trend, finance.view
gating, and the D-03 performance evidence).

Helpers mirror test_phase_34_e2e.py: they drive real endpoints, never raw SQL,
so later Phase 35 plans reuse them as-is. Two deliberate exceptions:

- Quote approval is a raw UPDATE, never POST /quotes/{id}/approve — the endpoint
  demands a sent/viewed transition and creates jobs for project-level quotes,
  both of which would pollute these fixtures (33-02 lesson).
- The high-volume money/time rows of the D-03 seed are bulk-inserted with one
  multi-row statement per table. WHY: ~4,000 sequential HTTP calls would dominate
  the very request latency that seed exists to measure. Structure rows
  (projects/scopes/jobs/budgets) still go through the shipped endpoints so real
  validation runs against them.
"""

import contextlib
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import event, select, text

from app.core.database import async_session_factory, engine
from app.core.security import create_access_token
from app.features.finance.models import CostCategory

_SECONDS_PER_HOUR = 3600
_MISSING_VIEW_PERMISSION = "Missing permission: finance.view"

# Phase 35 endpoint URLs. The three financial endpoints land in later plans; the
# constants are declared here so no call site in this file ever carries a bare
# path literal.
_COMPANY_FINANCIALS_URL = "/api/v1/financials/company"
_PROJECTS_URL = "/api/v1/projects/"
_BUDGETS_URL = "/api/v1/budgets/"
_COST_ENTRIES_URL = "/api/v1/cost-entries/"
_INVOICES_URL = "/api/v1/invoices/"
_QUOTES_URL = "/api/v1/quotes/"

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
)

_TIME_ENTRY_SEED_SQL = (
    "INSERT INTO time_entries (company_id, job_id, contractor_id, clocked_in_at, "
    "clocked_out_at, duration_seconds, session_status, deleted_at) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:contractor_id AS uuid), :clocked_in_at, :clocked_out_at, "
    ":duration_seconds, 'completed', NULL)"
)

_JOB_COMPLETE_SQL = "UPDATE jobs SET status = 'complete' WHERE id = CAST(:job_id AS uuid)"

_QUOTE_APPROVE_SQL = (
    "UPDATE quotes SET status = 'approved', approved_at = :approved_at "
    "WHERE id = CAST(:quote_id AS uuid)"
)

_QUOTE_APPROVE_WITH_PROJECT_SQL = (
    "UPDATE quotes SET status = 'approved', approved_at = :approved_at, "
    "project_id = CAST(:project_id AS uuid) WHERE id = CAST(:quote_id AS uuid)"
)


def _token(company_id: str, roles: list[str]) -> str:
    """Mint an access token for a synthetic user with the given roles."""
    return create_access_token(uuid4(), UUID(company_id), roles)


def _pm_headers(company_id: str) -> dict:
    """Authorization header for a project_manager token (finance.view + finance.manage)."""
    return {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}


def _admin_headers(company_id: str) -> dict:
    """Authorization header for an admin token (excluded from finance.* by default)."""
    return {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}


def _project_financials_url(project_id: str) -> str:
    """URL of one project's financial detail (endpoint lands in a later Phase 35 plan)."""
    return f"/api/v1/projects/{project_id}/financials"


def _project_trend_url(project_id: str) -> str:
    """URL of one project's margin trend series (endpoint lands in a later Phase 35 plan)."""
    return f"{_project_financials_url(project_id)}/trend"


@contextlib.contextmanager
def _count_sql_statements() -> Iterator[list[str]]:
    """Record every SQL statement issued while the block runs.

    The D-03 N+1 guard: a wall-clock ceiling alone cannot prove the company
    rollup is constant in project count, but a statement count can. Listens on
    engine.sync_engine because SQLAlchemy's event API is synchronous by design
    (same reason app/core/tenant.py's after_begin listener is sync).
    """
    statements: list[str] = []

    def _record(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement)

    event.listen(engine.sync_engine, "before_cursor_execute", _record)
    try:
        yield statements
    finally:
        event.remove(engine.sync_engine, "before_cursor_execute", _record)


async def _seed_cost_categories(company_id: str) -> None:
    """Seed the 4 protected system cost categories for a company (mirrors migration 0032)."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_COST_CATEGORY_SEED_SQL), {"company_id": company_id})
        await session.commit()


async def _category_id(company_id: str, name: str) -> str:
    """Look up a seeded cost category's id by name."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(
            select(CostCategory).where(
                CostCategory.company_id == company_id, CostCategory.name == name
            )
        )
        return str(result.scalar_one().id)


async def _create_project(client: AsyncClient, name: str = "Financials Project 35") -> str:
    """Create a project through the API and return its id."""
    resp = await client.post(_PROJECTS_URL, json={"name": name, "status": "active"})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient, project_id: str, trade_name: str = "Plumbing"
) -> str:
    """Create a trade scope on a project through the API and return its id."""
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name, "trade_color": "#2196F3"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_job(client: AsyncClient, project_id: str | None = None) -> str:
    """Create a job through the API, optionally linked to a project, and return its id."""
    payload: dict = {"description": "Financials test job", "trade_type": "general"}
    if project_id is not None:
        payload["project_id"] = project_id
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_budget(
    client: AsyncClient,
    headers: dict,
    *,
    project_id: str | None = None,
    trade_scope_id: str | None = None,
    total: str = "10000.00",
) -> dict:
    """Create a budget through the API at one anchor and return the response body."""
    payload: dict = {"total": total}
    if project_id is not None:
        payload["project_id"] = project_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    resp = await client.post(_BUDGETS_URL, headers=headers, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _add_cost_entry(
    client: AsyncClient,
    headers: dict,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    category_id: str,
    amount: str,
) -> str:
    """Create a cost entry through the API at one anchor and return its id."""
    payload: dict = {
        "category_id": category_id,
        "amount": amount,
        "incurred_date": date(2026, 6, 1).isoformat(),
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    resp = await client.post(_COST_ENTRIES_URL, headers=headers, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_user(client: AsyncClient, email: str) -> str:
    """Create a company user via the users API and return its id."""
    resp = await client.post("/api/v1/users/", json={"email": email})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _post_rate(
    client: AsyncClient, headers: dict, user_id: str, hourly_cost: str, effective_from: date
) -> None:
    """Append an effective-dated labor rate for a worker (finance.rates.manage caller)."""
    resp = await client.post(
        "/api/v1/labor-rates/",
        headers=headers,
        json={
            "user_id": user_id,
            "hourly_cost": hourly_cost,
            "effective_from": effective_from.isoformat(),
        },
    )
    assert resp.status_code == 201, resp.text


async def _seed_time_entry(
    company_id: str,
    job_id: str,
    contractor_id: str,
    hours: int,
    *,
    clocked_in_at: datetime,
) -> None:
    """Insert a completed tracked-time row directly, so tests control the work day."""
    duration_seconds = hours * _SECONDS_PER_HOUR
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_TIME_ENTRY_SEED_SQL),
            {
                "company_id": company_id,
                "job_id": job_id,
                "contractor_id": contractor_id,
                "clocked_in_at": clocked_in_at,
                "clocked_out_at": clocked_in_at,
                "duration_seconds": duration_seconds,
            },
        )
        await session.commit()


async def _project_rollup(client: AsyncClient, headers: dict, project_id: str) -> dict:
    """GET a project's cost rollup as a finance.view holder."""
    resp = await client.get(f"{_PROJECTS_URL}{project_id}/cost-entries", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


# ---------------------------------------------------------------------------
# Dated revenue seeders — the anchors every Phase 35 revenue assertion needs
# ---------------------------------------------------------------------------


def _material_line_item(amount: str) -> dict:
    """One material line item — the only revenue shape these fixtures need."""
    return {
        "item_type": "material",
        "description": "Phase 35 revenue item",
        "quantity": "1.000",
        "unit": "each",
        "unit_price": amount,
    }


async def _mark_job_complete(company_id: str, job_id: str) -> None:
    """Force a job to 'complete' via SQL so a manual invoice can be posted on it.

    SQL, not the jobs API: walking quote -> scheduled -> in_progress -> complete
    would drag scheduling fixtures into every financial test.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_JOB_COMPLETE_SQL), {"job_id": job_id})
        await session.commit()


async def _approve_quote(
    company_id: str,
    quote_id: str,
    *,
    approved_at: datetime | None,
    project_id: str | None = None,
) -> None:
    """Force a quote to approved via SQL, optionally binding a project-level quote.

    approved_at=None deliberately leaves the column NULL — the fixture for the
    approved-but-undated quote that the trend bucketing must not silently drop.
    """
    statement = _QUOTE_APPROVE_SQL if project_id is None else _QUOTE_APPROVE_WITH_PROJECT_SQL
    params: dict = {"quote_id": quote_id, "approved_at": approved_at}
    if project_id is not None:
        params["project_id"] = project_id
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(statement), params)
        await session.commit()


async def _create_approved_quote(
    client: AsyncClient,
    company_id: str,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    project_id: str | None = None,
    amount: str,
    approved_at: datetime | None = None,
) -> str:
    """Create a quote at one anchor and force it to approved, returning its id.

    Omitting both job_id and trade_scope_id makes a project-level quote; pass
    project_id to bind it to the project it covers.
    """
    payload: dict = {"line_items": [_material_line_item(amount)]}
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    if job_id is None and trade_scope_id is None:
        payload["title"] = "Phase 35 project quote"
    resp = await client.post(_QUOTES_URL, json=payload)
    assert resp.status_code == 201, resp.text

    quote_id = resp.json()["id"]
    await _approve_quote(company_id, quote_id, approved_at=approved_at, project_id=project_id)
    return quote_id


async def _create_invoice(
    client: AsyncClient,
    company_id: str,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    amount: str,
    issued_at: datetime,
) -> str:
    """Create an invoice at one anchor on a caller-chosen issue date and return its id.

    Job-anchored invoices require a 'complete' job (shipped generate_manual rule),
    so the job is completed first; trade-scope anchors have no status machine.
    """
    if job_id is not None:
        await _mark_job_complete(company_id, job_id)
    payload: dict = {
        "issued_at": issued_at.isoformat(),
        "line_items": [_material_line_item(amount)],
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    resp = await client.post(_INVOICES_URL, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


# ---------------------------------------------------------------------------
# _seed_company_portfolio — the D-03 measurement scale
# ---------------------------------------------------------------------------

_TRADE_NAMES = ("Plumbing", "Electrical", "Framing", "Drywall")
_SCOPES_PER_PROJECT = len(_TRADE_NAMES)
_JOBS_PER_PROJECT = 2
_COST_ENTRIES_PER_PROJECT = 20
_JOB_ANCHORED_COST_ENTRIES_PER_PROJECT = _COST_ENTRIES_PER_PROJECT // 2
_TIME_ENTRIES_PER_JOB = 25
_HOURS_PER_TIME_ENTRY = 2
_CONTRACTORS_PER_COMPANY = 2

# 'labor' is deliberately absent: a labor-categorised cost entry folds into the
# derived labor row (Phase 32), which would blur the cost-entry vs derived-labor
# distinction every rollup assertion here depends on.
_SEEDED_CATEGORY_NAMES = ("materials", "subcontractor", "other")

_COST_ENTRY_AMOUNT = Decimal("100.00")
_SEED_HOURLY_COST = "20.00"
_SEED_INVOICE_AMOUNT = Decimal("3000.00")
_SEED_QUOTE_AMOUNT = Decimal("2000.00")

# A routable-looking domain: email-validator rejects the reserved .test TLD.
_CONTRACTOR_EMAIL_DOMAIN = "portfolio-contractors.com"

_SEED_YEAR = 2026
_SEED_MONTHS = (1, 2, 3, 4, 5, 6)
_SEED_DAY_OF_MONTH = 15
_SEED_HOUR_OF_DAY = 9
_RATE_EFFECTIVE_FROM = date(_SEED_YEAR - 1, 1, 1)

# Attention-tier fixtures. Spend per project is
# _COST_ENTRIES_PER_PROJECT * _COST_ENTRY_AMOUNT ($2,000.00) plus derived labor
# (_JOBS_PER_PROJECT * _TIME_ENTRIES_PER_JOB * _HOURS_PER_TIME_ENTRY hours at
# _SEED_HOURLY_COST = $2,000.00), so every project spends $4,000.00.
_OVERRUN_PROJECT_INDEX = 0
_WARNING_PROJECT_INDEX = 1
_OVERRUN_BUDGET_TOTAL = "3000.00"
_WARNING_BUDGET_TOTAL = "4500.00"
_HEALTHY_BUDGET_TOTAL = "20000.00"
_SCOPE_BUDGET_TOTAL = "5000.00"

# Invoices and quotes sit on different anchors so a seeded project resolves both
# an invoiced and a quoted anchor (revenue_basis "mixed").
_INVOICE_ANCHOR_INDEX = 0
_QUOTE_ANCHOR_INDEX = 1

_COST_ENTRY_BULK_SQL = (
    "INSERT INTO cost_entries "
    "(company_id, job_id, trade_scope_id, category_id, amount, incurred_date) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:trade_scope_id AS uuid), CAST(:category_id AS uuid), :amount, :incurred_date)"
)

_INVOICE_BULK_SQL = (
    "INSERT INTO invoices "
    "(id, company_id, job_id, trade_scope_id, invoice_number, status, issued_at) "
    "VALUES (CAST(:id AS uuid), CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:trade_scope_id AS uuid), :invoice_number, 'unpaid', :issued_at)"
)

_INVOICE_LINE_ITEM_BULK_SQL = (
    "INSERT INTO invoice_line_items "
    "(company_id, invoice_id, item_type, description, quantity, unit, unit_price) "
    "VALUES (CAST(:company_id AS uuid), CAST(:document_id AS uuid), 'material', "
    "'Portfolio revenue line', 1, 'each', :unit_price)"
)

_QUOTE_BULK_SQL = (
    "INSERT INTO quotes (id, company_id, job_id, trade_scope_id, status, approved_at) "
    "VALUES (CAST(:id AS uuid), CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:trade_scope_id AS uuid), 'approved', :approved_at)"
)

_QUOTE_LINE_ITEM_BULK_SQL = (
    "INSERT INTO quote_line_items "
    "(company_id, quote_id, item_type, description, quantity, unit, unit_price) "
    "VALUES (CAST(:company_id AS uuid), CAST(:document_id AS uuid), 'material', "
    "'Portfolio revenue line', 1, 'each', :unit_price)"
)


@dataclass(frozen=True)
class _ProjectStructure:
    """One seeded project's endpoint-created skeleton."""

    project_id: str
    scope_ids: list[str]
    job_ids: list[str]


@dataclass(frozen=True)
class _PortfolioSeed:
    """Everything the bulk row builders need to fabricate a company's money rows."""

    company_id: str
    category_ids: list[str]
    contractor_ids: list[str]
    structures: list[_ProjectStructure]


@dataclass(frozen=True)
class _RevenueRows:
    """A revenue table's documents plus their line items, ready for executemany."""

    documents: list[dict]
    line_items: list[dict]


def _seed_date(sequence: int) -> date:
    """Spread seeded rows across _SEED_MONTHS so the margin trend gets real buckets."""
    return date(_SEED_YEAR, _SEED_MONTHS[sequence % len(_SEED_MONTHS)], _SEED_DAY_OF_MONTH)


def _seed_datetime(sequence: int) -> datetime:
    """Timezone-aware UTC instant on the same month spread as _seed_date."""
    day = _seed_date(sequence)
    return datetime(day.year, day.month, day.day, _SEED_HOUR_OF_DAY, tzinfo=UTC)


def _project_budget_total(project_index: int) -> str:
    """Budget total that puts the nth seeded project in its attention tier."""
    if project_index == _OVERRUN_PROJECT_INDEX:
        return _OVERRUN_BUDGET_TOTAL
    if project_index == _WARNING_PROJECT_INDEX:
        return _WARNING_BUDGET_TOTAL
    return _HEALTHY_BUDGET_TOTAL


def _cost_entry_anchor(
    structure: _ProjectStructure, sequence: int
) -> tuple[str | None, str | None]:
    """(job_id, trade_scope_id) for the nth cost entry — the first half sit on jobs."""
    if sequence < _JOB_ANCHORED_COST_ENTRIES_PER_PROJECT:
        return structure.job_ids[sequence % _JOBS_PER_PROJECT], None
    return None, structure.scope_ids[sequence % _SCOPES_PER_PROJECT]


def _cost_entry_rows(seed: _PortfolioSeed) -> list[dict]:
    """Half job-anchored, half scope-anchored cost entries spread over _SEED_MONTHS."""
    rows: list[dict] = []
    for structure in seed.structures:
        for sequence in range(_COST_ENTRIES_PER_PROJECT):
            job_id, trade_scope_id = _cost_entry_anchor(structure, sequence)
            rows.append(
                {
                    "company_id": seed.company_id,
                    "job_id": job_id,
                    "trade_scope_id": trade_scope_id,
                    "category_id": seed.category_ids[sequence % len(seed.category_ids)],
                    "amount": _COST_ENTRY_AMOUNT,
                    "incurred_date": _seed_date(sequence),
                }
            )
    return rows


def _time_entry_rows(seed: _PortfolioSeed) -> list[dict]:
    """_TIME_ENTRIES_PER_JOB completed sessions per job, alternating rated contractors."""
    rows: list[dict] = []
    for structure in seed.structures:
        for job_index, job_id in enumerate(structure.job_ids):
            for sequence in range(_TIME_ENTRIES_PER_JOB):
                clocked_in_at = _seed_datetime(sequence)
                contractor_index = (job_index + sequence) % len(seed.contractor_ids)
                rows.append(
                    {
                        "company_id": seed.company_id,
                        "job_id": job_id,
                        "contractor_id": seed.contractor_ids[contractor_index],
                        "clocked_in_at": clocked_in_at,
                        "clocked_out_at": clocked_in_at + timedelta(hours=_HOURS_PER_TIME_ENTRY),
                        "duration_seconds": _HOURS_PER_TIME_ENTRY * _SECONDS_PER_HOUR,
                    }
                )
    return rows


def _revenue_anchors(
    structure: _ProjectStructure, anchor_index: int
) -> list[tuple[str | None, str | None]]:
    """One job anchor and one trade-scope anchor for a project's revenue documents."""
    return [
        (structure.job_ids[anchor_index], None),
        (None, structure.scope_ids[anchor_index]),
    ]


def _line_item_row(seed: _PortfolioSeed, document_id: str, unit_price: Decimal) -> dict:
    """The single material line carrying a seeded document's whole amount."""
    return {
        "company_id": seed.company_id,
        "document_id": document_id,
        "unit_price": unit_price,
    }


def _invoice_rows(seed: _PortfolioSeed) -> _RevenueRows:
    """One job-anchored and one scope-anchored invoice per project, issued in range."""
    rows = _RevenueRows(documents=[], line_items=[])
    for structure in seed.structures:
        for job_id, trade_scope_id in _revenue_anchors(structure, _INVOICE_ANCHOR_INDEX):
            sequence = len(rows.documents)
            document_id = str(uuid4())
            rows.documents.append(
                {
                    "id": document_id,
                    "company_id": seed.company_id,
                    "job_id": job_id,
                    "trade_scope_id": trade_scope_id,
                    "invoice_number": f"INV-P35-{sequence:05d}",
                    "issued_at": _seed_datetime(sequence),
                }
            )
            rows.line_items.append(_line_item_row(seed, document_id, _SEED_INVOICE_AMOUNT))
    return rows


def _quote_rows(seed: _PortfolioSeed) -> _RevenueRows:
    """One job-anchored and one scope-anchored approved quote per project, dated in range."""
    rows = _RevenueRows(documents=[], line_items=[])
    for structure in seed.structures:
        for job_id, trade_scope_id in _revenue_anchors(structure, _QUOTE_ANCHOR_INDEX):
            sequence = len(rows.documents)
            document_id = str(uuid4())
            rows.documents.append(
                {
                    "id": document_id,
                    "company_id": seed.company_id,
                    "job_id": job_id,
                    "trade_scope_id": trade_scope_id,
                    "approved_at": _seed_datetime(sequence),
                }
            )
            rows.line_items.append(_line_item_row(seed, document_id, _SEED_QUOTE_AMOUNT))
    return rows


async def _bulk_insert_portfolio_rows(seed: _PortfolioSeed) -> None:
    """Insert the portfolio's money and time rows — one multi-row statement per table."""
    invoices = _invoice_rows(seed)
    quotes = _quote_rows(seed)
    batches = (
        (_COST_ENTRY_BULK_SQL, _cost_entry_rows(seed)),
        (_TIME_ENTRY_SEED_SQL, _time_entry_rows(seed)),
        (_INVOICE_BULK_SQL, invoices.documents),
        (_INVOICE_LINE_ITEM_BULK_SQL, invoices.line_items),
        (_QUOTE_BULK_SQL, quotes.documents),
        (_QUOTE_LINE_ITEM_BULK_SQL, quotes.line_items),
    )
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{seed.company_id}'"))
        for statement, rows in batches:
            await session.execute(text(statement), rows)
        await session.commit()


async def _seed_rated_contractors(client: AsyncClient, headers: dict) -> list[str]:
    """Create the portfolio's contractors, each rated from before every seeded work day."""
    contractor_ids: list[str] = []
    for _ in range(_CONTRACTORS_PER_COMPANY):
        email = f"portfolio-{uuid4().hex}@{_CONTRACTOR_EMAIL_DOMAIN}"
        contractor_id = await _create_user(client, email)
        await _post_rate(client, headers, contractor_id, _SEED_HOURLY_COST, _RATE_EFFECTIVE_FROM)
        contractor_ids.append(contractor_id)
    return contractor_ids


async def _seed_project_structure(
    client: AsyncClient, headers: dict, project_index: int
) -> _ProjectStructure:
    """Create one project's scopes, jobs and budgets through the shipped endpoints."""
    project_id = await _create_project(client, name=f"Portfolio Project {project_index}")
    scope_ids = [
        await _create_trade_scope(client, project_id, trade_name=trade_name)
        for trade_name in _TRADE_NAMES
    ]
    job_ids = [await _create_job(client, project_id) for _ in range(_JOBS_PER_PROJECT)]
    await _create_budget(
        client, headers, project_id=project_id, total=_project_budget_total(project_index)
    )
    for scope_id in scope_ids:
        await _create_budget(client, headers, trade_scope_id=scope_id, total=_SCOPE_BUDGET_TOTAL)
    return _ProjectStructure(project_id=project_id, scope_ids=scope_ids, job_ids=job_ids)


async def _seed_company_portfolio(
    client: AsyncClient, headers: dict, company_id: str, *, project_count: int
) -> list[str]:
    """Seed `project_count` fully-populated projects and return their ids.

    Per project: 4 trade scopes, 2 jobs, 20 cost entries, 50 completed time
    entries, 2 invoices, 2 approved quotes, 1 project budget, 4 scope budgets
    (~2,250 rows at project_count=25 — the D-03 measurement scale).

    Structure rows (projects/scopes/jobs/budgets) go through the shipped
    endpoints so real validation runs; the high-volume money/time rows are
    bulk-inserted with one multi-row statement per table because ~2,000
    sequential HTTP calls would dominate the very latency this seeds for.

    `client` carries the tenant's own auth for the structure endpoints;
    `headers` carries a finance.* holder's token and overrides it per request
    on the finance-gated ones.
    """
    await _seed_cost_categories(company_id)
    seed = _PortfolioSeed(
        company_id=company_id,
        category_ids=[await _category_id(company_id, name) for name in _SEEDED_CATEGORY_NAMES],
        contractor_ids=await _seed_rated_contractors(client, headers),
        structures=[
            await _seed_project_structure(client, headers, project_index)
            for project_index in range(project_count)
        ],
    )
    await _bulk_insert_portfolio_rows(seed)
    return [structure.project_id for structure in seed.structures]


# ---------------------------------------------------------------------------
# Harness self-tests — the helpers are proven against SHIPPED endpoints before
# any Phase 35 endpoint exists
# ---------------------------------------------------------------------------

_SMOKE_PROJECT_COUNT = 2


@pytest.mark.asyncio
async def test_sql_statement_counter_records_statements(async_client, seed_two_tenants):
    """The counter records inside its block and detaches on exit — no leak into other tests."""
    headers = _pm_headers(seed_two_tenants["tenant_a_id"])

    with _count_sql_statements() as statements:
        resp = await async_client.get(_PROJECTS_URL, headers=headers)
        assert resp.status_code == 200, resp.text

    assert statements
    assert any("FROM projects" in statement for statement in statements)

    recorded_while_listening = len(statements)
    resp = await async_client.get(_PROJECTS_URL, headers=headers)
    assert resp.status_code == 200, resp.text
    assert len(statements) == recorded_while_listening


@pytest.mark.asyncio
async def test_revenue_seeders_land_at_anchors_the_shipped_rollup_resolves(
    tenant_a_client, seed_two_tenants
):
    """The new dated invoice/quote seeders produce revenue the shipped rollup confirms."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    category_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client, project_id)

    await _add_cost_entry(
        tenant_a_client, headers, job_id=job_id, category_id=category_id, amount="250.00"
    )
    await _create_budget(tenant_a_client, headers, project_id=project_id, total="2000.00")
    await _create_invoice(
        tenant_a_client,
        company_id,
        job_id=job_id,
        amount="1000.00",
        issued_at=datetime(2026, 3, 15, 9, tzinfo=UTC),
    )
    await _create_approved_quote(
        tenant_a_client,
        company_id,
        trade_scope_id=scope_id,
        amount="500.00",
        approved_at=datetime(2026, 4, 15, 9, tzinfo=UTC),
    )

    body = await _project_rollup(tenant_a_client, headers, project_id)

    assert Decimal(body["total"]) == Decimal("250.00")
    assert Decimal(body["budget"]["total"]) == Decimal("2000.00")
    assert body["margin"]["revenue_basis"] == "mixed"
    assert Decimal(body["margin"]["revenue"]) == Decimal("1500.00")


@pytest.mark.asyncio
async def test_undated_approved_quote_keeps_a_null_approved_at(tenant_a_client, seed_two_tenants):
    """approved_at=None leaves the column NULL — the undated-approval trend fixture."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)

    quote_id = await _create_approved_quote(
        tenant_a_client, company_id, trade_scope_id=scope_id, amount="750.00"
    )

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(
            text("SELECT status, approved_at FROM quotes WHERE id = CAST(:quote_id AS uuid)"),
            {"quote_id": quote_id},
        )
        status, approved_at = result.one()

    assert status == "approved"
    assert approved_at is None


@pytest.mark.asyncio
async def test_seed_company_portfolio_matches_shipped_project_rollup(
    tenant_a_client, seed_two_tenants
):
    """The portfolio seeder's figures are confirmed by the SHIPPED project rollup.

    This is what makes a scaffolding-only plan verifiable: none of the three
    Phase 35 endpoints exist yet, so the seeder is proven against Phase 32/33/34
    output instead.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)

    project_ids = await _seed_company_portfolio(
        tenant_a_client, headers, company_id, project_count=_SMOKE_PROJECT_COUNT
    )
    body = await _project_rollup(tenant_a_client, headers, project_ids[_OVERRUN_PROJECT_INDEX])

    assert len(body["entries"]) == _COST_ENTRIES_PER_PROJECT
    assert Decimal(body["grand_total"]) > Decimal(body["total"])
    assert Decimal(body["budget"]["total"]) == Decimal(
        _project_budget_total(_OVERRUN_PROJECT_INDEX)
    )
    assert body["margin"]["revenue"] is not None
    assert body["margin"]["revenue_basis"] in {"invoiced", "mixed"}


@pytest.mark.asyncio
async def test_seed_company_portfolio_is_tenant_isolated(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """A portfolio seeded into tenant A is invisible to tenant B (RLS)."""
    tenant_a_id = seed_two_tenants["tenant_a_id"]
    tenant_b_id = seed_two_tenants["tenant_b_id"]

    tenant_a_projects = await _seed_company_portfolio(
        tenant_a_client, _pm_headers(tenant_a_id), tenant_a_id, project_count=1
    )
    await _seed_company_portfolio(
        tenant_b_client, _pm_headers(tenant_b_id), tenant_b_id, project_count=1
    )

    resp = await tenant_b_client.get(_PROJECTS_URL)
    assert resp.status_code == 200, resp.text

    visible_project_ids = {project["id"] for project in resp.json()}
    assert visible_project_ids
    assert tenant_a_projects[0] not in visible_project_ids
