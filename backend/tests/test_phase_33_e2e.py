"""Phase 33 — Profit Margin Tracking.

Covers MARG-01 (job/scope margin), MARG-02 (project rollup, D-12 same
traversal), MARG-03 (incomplete-data flag). Helpers mirror
test_phase_32_e2e.py.

This file is the phase's integration contract: it is RED until 33-03 assembles
the `margin` block onto the breakdown/rollup responses. Quote approval happens
via raw SQL, never POST /quotes/{id}/approve — the endpoint demands a
sent/viewed transition and creates jobs for project-level quotes, both of which
would pollute these fixtures.
"""

from datetime import UTC, date, datetime
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.security import create_access_token
from app.features.finance.models import CostCategory

_SECONDS_PER_HOUR = 3600
_MISSING_VIEW_PERMISSION = "Missing permission: finance.view"

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
)

_COST_ENTRY_SEED_SQL = (
    "INSERT INTO cost_entries "
    "(company_id, job_id, trade_scope_id, category_id, amount, incurred_date) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:trade_scope_id AS uuid), CAST(:category_id AS uuid), :amount, :incurred_date)"
)

_TIME_ENTRY_SEED_SQL = (
    "INSERT INTO time_entries (company_id, job_id, contractor_id, clocked_in_at, "
    "clocked_out_at, duration_seconds, session_status, deleted_at) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:contractor_id AS uuid), :clocked_in_at, :clocked_out_at, "
    ":duration_seconds, 'completed', NULL)"
)

_QUOTE_APPROVE_SQL = (
    "UPDATE quotes SET status = 'approved', approved_at = now() WHERE id = CAST(:quote_id AS uuid)"
)

_JOB_COMPLETE_SQL = "UPDATE jobs SET status = 'complete' WHERE id = CAST(:job_id AS uuid)"

_QUOTE_APPROVE_WITH_PROJECT_SQL = (
    "UPDATE quotes SET status = 'approved', approved_at = now(), "
    "project_id = CAST(:project_id AS uuid) "
    "WHERE id = CAST(:quote_id AS uuid)"
)


def _token(company_id: str, roles: list[str]) -> str:
    """Mint an access token for a synthetic user with the given roles."""
    return create_access_token(uuid4(), UUID(company_id), roles)


def _pm_headers(company_id: str) -> dict:
    """Authorization header for a project_manager token (finance.view holder)."""
    return {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}


def _admin_headers(company_id: str) -> dict:
    """Authorization header for an admin token (excluded from finance.* by default)."""
    return {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}


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


async def _create_project(client: AsyncClient, name: str = "Margin Project 33") -> str:
    """Create a project through the API and return its id."""
    resp = await client.post("/api/v1/projects/", json={"name": name, "status": "active"})
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
    payload: dict = {"description": "Margin test job", "trade_type": "general"}
    if project_id is not None:
        payload["project_id"] = project_id
    resp = await client.post("/api/v1/jobs/", json=payload)
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


async def _seed_cost_entry(
    company_id: str,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    category_id: str,
    amount: str,
) -> None:
    """Insert a cost entry via raw SQL at either anchor (job XOR trade scope)."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_COST_ENTRY_SEED_SQL),
            {
                "company_id": company_id,
                "job_id": job_id,
                "trade_scope_id": trade_scope_id,
                "category_id": category_id,
                "amount": amount,
                "incurred_date": date(2026, 6, 1),
            },
        )
        await session.commit()


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


def _single_line_item(unit_price: str, quantity: str) -> dict:
    """One material line item — the only revenue shape these fixtures need."""
    return {
        "item_type": "material",
        "description": "Margin test item",
        "quantity": quantity,
        "unit": "each",
        "unit_price": unit_price,
    }


async def _mark_job_complete(company_id: str, job_id: str) -> None:
    """Force a job to 'complete' via SQL so a manual invoice can be posted on it.

    SQL, not the jobs API: walking quote→scheduled→in_progress→complete would
    drag scheduling fixtures into every margin test.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_JOB_COMPLETE_SQL), {"job_id": job_id})
        await session.commit()


async def _post_invoice(
    client: AsyncClient,
    *,
    company_id: str,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    unit_price: str,
    quantity: str = "1.000",
    tax_rate: str = "0",
    discount_type: str | None = None,
    discount_value: str = "0",
) -> dict:
    """POST /api/v1/invoices/ with a single material line item at one anchor.

    Job-anchored invoices require a 'complete' job, so the job is completed first.
    """
    if job_id is not None:
        await _mark_job_complete(company_id, job_id)
    payload: dict = {
        "tax_rate": tax_rate,
        "discount_value": discount_value,
        "line_items": [_single_line_item(unit_price, quantity)],
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    if discount_type is not None:
        payload["discount_type"] = discount_type
    resp = await client.post("/api/v1/invoices/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _post_quote(
    client: AsyncClient,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    title: str | None = None,
    unit_price: str,
    quantity: str = "1.000",
    tax_rate: str = "0",
) -> dict:
    """POST /api/v1/quotes/ — omitting both anchors makes a project-level quote."""
    payload: dict = {
        "tax_rate": tax_rate,
        "line_items": [_single_line_item(unit_price, quantity)],
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    if title is not None:
        payload["title"] = title
    resp = await client.post("/api/v1/quotes/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _approve_quote(company_id: str, quote_id: str, *, project_id: str | None = None) -> None:
    """Force a quote to approved via SQL, optionally binding a project-level quote.

    SQL, NOT POST /quotes/{id}/approve: the approve endpoint requires a
    sent/viewed transition and, for project-level quotes, creates jobs as a
    side effect — both would pollute these fixtures.
    """
    statement = _QUOTE_APPROVE_SQL if project_id is None else _QUOTE_APPROVE_WITH_PROJECT_SQL
    params: dict = {"quote_id": quote_id}
    if project_id is not None:
        params["project_id"] = project_id
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(statement), params)
        await session.commit()


async def _job_breakdown(client: AsyncClient, headers: dict, job_id: str) -> dict:
    """GET a job's cost breakdown as a finance.view holder."""
    resp = await client.get(f"/api/v1/jobs/{job_id}/cost-breakdown", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _scope_breakdown(client: AsyncClient, headers: dict, scope_id: str) -> dict:
    """GET a trade scope's cost breakdown as a finance.view holder."""
    resp = await client.get(f"/api/v1/trade-scopes/{scope_id}/cost-breakdown", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _project_rollup(client: AsyncClient, headers: dict, project_id: str) -> dict:
    """GET a project's cost rollup as a finance.view holder."""
    resp = await client.get(f"/api/v1/projects/{project_id}/cost-entries", headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


def _margin(payload: dict) -> dict:
    """Assert the margin block is present on a response and return it."""
    assert "margin" in payload, f"margin block missing from response: {payload}"
    margin = payload["margin"]
    assert margin is not None, f"margin block is null on response: {payload}"
    return margin


# ---------------------------------------------------------------------------
# MARG-01: job and trade-scope margin
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_job_margin_uses_invoiced_revenue_at_the_anchor(
    async_client, tenant_a_client, seed_two_tenants
):
    """A job with an invoice and costs reports invoiced revenue and the $/% pair."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")

    await _post_invoice(tenant_a_client, company_id=company_id, job_id=job_id, unit_price="2000.00")
    await _seed_cost_entry(company_id, job_id=job_id, category_id=materials_id, amount="500.00")

    margin = _margin(await _job_breakdown(async_client, _pm_headers(company_id), job_id))
    assert margin["revenue"] == "2000.00"
    assert margin["revenue_basis"] == "invoiced"
    assert margin["margin"] == "1500.00"
    assert margin["margin_percent"] == "75.0"
    assert margin["incomplete"] is False


@pytest.mark.asyncio
async def test_job_margin_falls_back_to_latest_approved_quote_basis(
    async_client, tenant_a_client, seed_two_tenants
):
    """With no invoice, the LATEST approved quote alone backs revenue — never a sum."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")

    first_quote = await _post_quote(tenant_a_client, job_id=job_id, unit_price="1000.00")
    second_quote = await _post_quote(tenant_a_client, job_id=job_id, unit_price="1500.00")
    await _approve_quote(company_id, first_quote["id"])
    await _approve_quote(company_id, second_quote["id"])
    await _seed_cost_entry(company_id, job_id=job_id, category_id=materials_id, amount="400.00")

    margin = _margin(await _job_breakdown(async_client, _pm_headers(company_id), job_id))
    assert margin["revenue"] == "1500.00"
    assert margin["revenue_basis"] == "quoted"


@pytest.mark.asyncio
async def test_job_margin_revenue_basis_is_pre_tax_subtotal_minus_discount(
    async_client, tenant_a_client, seed_two_tenants
):
    """D-13: revenue is subtotal minus discount, with tax excluded entirely."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)

    await _post_invoice(
        tenant_a_client,
        company_id=company_id,
        job_id=job_id,
        unit_price="1000.00",
        discount_type="percent",
        discount_value="10",
        tax_rate="8.25",
    )

    margin = _margin(await _job_breakdown(async_client, _pm_headers(company_id), job_id))
    assert margin["revenue"] == "900.00"


@pytest.mark.asyncio
async def test_trade_scope_margin_uses_scope_anchored_invoice(
    async_client, tenant_a_client, seed_two_tenants
):
    """A scope-anchored invoice backs the scope margin; labor stays job-level (D-08)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")

    await _post_invoice(
        tenant_a_client, company_id=company_id, trade_scope_id=scope_id, unit_price="1200.00"
    )
    await _seed_cost_entry(
        company_id, trade_scope_id=scope_id, category_id=materials_id, amount="200.00"
    )

    body = await _scope_breakdown(async_client, _pm_headers(company_id), scope_id)
    margin = _margin(body)
    assert margin["margin"] == "1000.00"
    assert body["labor"] is None
    assert body["labor_tracked_at_job_level"] is True


@pytest.mark.asyncio
async def test_margin_is_forbidden_for_admin_without_finance_view(
    async_client, tenant_a_client, seed_two_tenants
):
    """Admin lacks finance.view — margin-bearing endpoints 403 before any data leaks."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    admin_headers = _admin_headers(company_id)

    job_resp = await async_client.get(
        f"/api/v1/jobs/{job_id}/cost-breakdown", headers=admin_headers
    )
    assert job_resp.status_code == 403, job_resp.text
    assert job_resp.json()["detail"] == _MISSING_VIEW_PERMISSION

    project_resp = await async_client.get(
        f"/api/v1/projects/{project_id}/cost-entries", headers=admin_headers
    )
    assert project_resp.status_code == 403, project_resp.text
    assert project_resp.json()["detail"] == _MISSING_VIEW_PERMISSION


# ---------------------------------------------------------------------------
# MARG-02: project rollup through the D-12 traversal
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_project_margin_same_traversal_mixed_anchors(
    async_client, tenant_a_client, seed_two_tenants
):
    """D-12 mandate: revenue and cost net out through the same dual-outerjoin traversal."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    worker_id = await _create_user(tenant_a_client, "worker-margin-traversal@tenant-a.com")
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    materials_id = await _category_id(company_id, "materials")
    pm_headers = _pm_headers(company_id)

    await _post_invoice(
        tenant_a_client, company_id=company_id, trade_scope_id=scope_id, unit_price="1000.00"
    )
    await _seed_cost_entry(
        company_id, trade_scope_id=scope_id, category_id=materials_id, amount="300.00"
    )
    await _post_invoice(tenant_a_client, company_id=company_id, job_id=job_id, unit_price="500.00")
    await _seed_cost_entry(company_id, job_id=job_id, category_id=materials_id, amount="100.00")
    await _post_rate(async_client, pm_headers, worker_id, "50.00", date(2026, 1, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, 1, clocked_in_at=datetime(2026, 6, 10, 15, 0, tzinfo=UTC)
    )

    body = await _project_rollup(async_client, pm_headers, project_id)
    margin = _margin(body)
    assert margin["revenue"] == "1500.00"
    assert body["grand_total"] == "450.00"
    assert margin["margin"] == "1050.00"
    assert margin["margin_percent"] == "70.0"
    assert margin["revenue_basis"] == "invoiced"
    assert margin["incomplete"] is False


@pytest.mark.asyncio
async def test_project_margin_traversal_never_mixes_quote_with_invoice_at_one_anchor(
    async_client, tenant_a_client, seed_two_tenants
):
    """Pitfall 2: at one anchor, invoices win outright and the approved quote is discarded."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)

    quote = await _post_quote(tenant_a_client, trade_scope_id=scope_id, unit_price="5000.00")
    await _approve_quote(company_id, quote["id"])
    await _post_invoice(
        tenant_a_client, company_id=company_id, trade_scope_id=scope_id, unit_price="1000.00"
    )

    margin = _margin(await _project_rollup(async_client, _pm_headers(company_id), project_id))
    assert margin["revenue"] == "1000.00"


@pytest.mark.asyncio
async def test_project_margin_mixed_basis_when_one_anchor_invoiced_one_quoted(
    async_client, tenant_a_client, seed_two_tenants
):
    """One invoiced anchor plus one quoted anchor rolls up to a mixed revenue basis."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_a_id = await _create_trade_scope(tenant_a_client, project_id, trade_name="Plumbing")
    scope_b_id = await _create_trade_scope(tenant_a_client, project_id, trade_name="Electrical")

    await _post_invoice(
        tenant_a_client, company_id=company_id, trade_scope_id=scope_a_id, unit_price="1000.00"
    )
    quote = await _post_quote(tenant_a_client, trade_scope_id=scope_b_id, unit_price="2000.00")
    await _approve_quote(company_id, quote["id"])

    margin = _margin(await _project_rollup(async_client, _pm_headers(company_id), project_id))
    assert margin["revenue"] == "3000.00"
    assert margin["revenue_basis"] == "mixed"


@pytest.mark.asyncio
async def test_project_level_quote_enters_traversal_only_when_no_anchor_revenue(
    async_client, tenant_a_client, seed_two_tenants
):
    """D-14: the project-level approved quote counts only while NO anchor carries revenue."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    pm_headers = _pm_headers(company_id)

    project_quote = await _post_quote(
        tenant_a_client, title="Margin Project 33", unit_price="9000.00"
    )
    await _approve_quote(company_id, project_quote["id"], project_id=project_id)

    margin_before = _margin(await _project_rollup(async_client, pm_headers, project_id))
    assert margin_before["revenue"] == "9000.00"
    assert margin_before["revenue_basis"] == "quoted"

    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    await _post_invoice(
        tenant_a_client, company_id=company_id, trade_scope_id=scope_id, unit_price="1000.00"
    )

    margin_after = _margin(await _project_rollup(async_client, pm_headers, project_id))
    assert margin_after["revenue"] == "1000.00"


# ---------------------------------------------------------------------------
# MARG-03: incomplete-data flag — honesty over fabricated numbers
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_legacy_job_with_revenue_and_no_costs_is_flagged_never_100_percent(
    async_client, tenant_a_client, seed_two_tenants
):
    """Keystone (Pitfall 9): revenue with zero cost data flags, never a clean 100%."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)

    await _post_invoice(tenant_a_client, company_id=company_id, job_id=job_id, unit_price="2000.00")

    margin = _margin(await _job_breakdown(async_client, _pm_headers(company_id), job_id))
    assert margin["margin"] == "2000.00"
    assert margin["margin_percent"] == "100.0"
    assert margin["incomplete"] is True
    assert margin["incomplete"] is not False
    assert "no_cost_data" in margin["incomplete_reasons"]


@pytest.mark.asyncio
async def test_unrated_labor_hours_flag_the_margin_incomplete(
    async_client, tenant_a_client, seed_two_tenants
):
    """Tracked time with no effective rate flags the margin as incomplete."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    worker_id = await _create_user(tenant_a_client, "worker-margin-unrated@tenant-a.com")
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")

    await _post_invoice(tenant_a_client, company_id=company_id, job_id=job_id, unit_price="1000.00")
    await _seed_cost_entry(company_id, job_id=job_id, category_id=materials_id, amount="400.00")
    await _seed_time_entry(
        company_id, job_id, worker_id, 2, clocked_in_at=datetime(2026, 6, 10, 15, 0, tzinfo=UTC)
    )

    margin = _margin(await _job_breakdown(async_client, _pm_headers(company_id), job_id))
    assert margin["incomplete"] is True
    assert "unrated_labor" in margin["incomplete_reasons"]
    assert margin["margin"] == "600.00"


@pytest.mark.asyncio
async def test_no_revenue_source_is_not_incomplete_and_margin_is_absent(
    async_client, tenant_a_client, seed_two_tenants
):
    """D-07: no invoice and no APPROVED quote means an absent margin, not a flag."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")

    await _seed_cost_entry(company_id, job_id=job_id, category_id=materials_id, amount="500.00")
    await _post_quote(tenant_a_client, job_id=job_id, unit_price="9999.00")

    margin = _margin(await _job_breakdown(async_client, _pm_headers(company_id), job_id))
    assert margin["revenue"] is None
    assert margin["revenue_basis"] == "none"
    assert margin["margin"] is None
    assert margin["margin_percent"] is None
    assert margin["incomplete"] is False
    assert margin["incomplete_reasons"] == []


@pytest.mark.asyncio
async def test_project_incomplete_flag_propagates_from_any_contributing_anchor(
    async_client, tenant_a_client, seed_two_tenants
):
    """A healthy sibling anchor's costs never mask a legacy anchor's missing cost data."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    legacy_job_id = await _create_job(tenant_a_client, project_id=project_id)
    materials_id = await _category_id(company_id, "materials")

    await _post_invoice(
        tenant_a_client, company_id=company_id, trade_scope_id=scope_id, unit_price="1000.00"
    )
    await _seed_cost_entry(
        company_id, trade_scope_id=scope_id, category_id=materials_id, amount="300.00"
    )
    await _post_invoice(
        tenant_a_client, company_id=company_id, job_id=legacy_job_id, unit_price="500.00"
    )

    margin = _margin(await _project_rollup(async_client, _pm_headers(company_id), project_id))
    assert margin["incomplete"] is True
    assert "no_cost_data" in margin["incomplete_reasons"]
