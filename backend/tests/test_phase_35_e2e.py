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
from datetime import UTC, date, datetime
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
# Harness self-tests — the helpers are proven against SHIPPED endpoints before
# any Phase 35 endpoint exists
# ---------------------------------------------------------------------------


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
