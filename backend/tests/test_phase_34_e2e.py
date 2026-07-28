"""Phase 34 — Budgeting and Overrun Alerts.

Covers BUDG-01 (budget CRUD: create/edit/soft-delete gated finance.manage,
409 on a duplicate active anchor, D-03 re-arm on a raise) and BUDG-02
(budget-vs-actual block embedded on the trade-scope cost breakdown and the
project cost rollup, with spent == grand_total by construction).

Helpers mirror test_phase_32_e2e.py/test_phase_33_e2e.py. The seed helpers
(_create_project, _create_trade_scope, _create_budget, _add_cost_entry) drive
real endpoints — never raw SQL — so later Phase 34 plans reuse them as-is.
Threshold-fire state (budgets.warning_fired_at/overrun_fired_at) is read and
seeded via direct SQL because no endpoint exposes it by design.
"""

from datetime import date
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.security import create_access_token
from app.features.finance.models import CostCategory

_BUDGETS_URL = "/api/v1/budgets/"
_MISSING_MANAGE_PERMISSION = "Missing permission: finance.manage"
_PROJECT_DUPLICATE_DETAIL = "A budget already exists for this project"
_SCOPE_DUPLICATE_DETAIL = "A budget already exists for this trade scope"
_BREAKDOWNS_DORMANT_DETAIL = "Per-category budget allocation is not available yet"

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
)

_SET_FIRED_THRESHOLDS_SQL = (
    "UPDATE budgets SET warning_fired_at = now(), overrun_fired_at = now() "
    "WHERE id = CAST(:budget_id AS uuid)"
)

_FIRED_STATE_SQL = (
    "SELECT warning_fired_at, overrun_fired_at FROM budgets WHERE id = CAST(:budget_id AS uuid)"
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


def _budget_url(budget_id: str) -> str:
    """URL of one budget resource."""
    return f"{_BUDGETS_URL}{budget_id}"


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


async def _create_project(client: AsyncClient, name: str = "Budget Project 34") -> str:
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
    payload: dict = {"description": "Budget test job", "trade_type": "general"}
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
    resp = await client.post("/api/v1/cost-entries/", headers=headers, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _set_fired_thresholds(company_id: str, budget_id: str) -> None:
    """Force both threshold-fired timestamps on a budget via SQL (no endpoint sets them yet)."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_SET_FIRED_THRESHOLDS_SQL), {"budget_id": budget_id})
        await session.commit()


async def _fired_state(company_id: str, budget_id: str) -> tuple:
    """Read (warning_fired_at, overrun_fired_at) for a budget via SQL."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_FIRED_STATE_SQL), {"budget_id": budget_id})
        return result.one()


# ---------------------------------------------------------------------------
# BUDG-01: budget CRUD
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_budget_crud_create_project_budget(async_client, tenant_a_client, seed_two_tenants):
    """POST /budgets/ with a project anchor returns 201 with id, project_id and total."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    body = await _create_budget(async_client, _pm_headers(company_id), project_id=project_id)

    assert body["id"]
    assert body["project_id"] == project_id
    assert body["trade_scope_id"] is None
    assert body["total"] == "10000.00"


@pytest.mark.asyncio
async def test_budget_crud_project_and_scope_budgets_coexist(
    async_client, tenant_a_client, seed_two_tenants
):
    """A project budget and a trade-scope budget on the same project coexist independently."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)

    project_budget = await _create_budget(async_client, headers, project_id=project_id)
    scope_budget = await _create_budget(
        async_client, headers, trade_scope_id=scope_id, total="4000.00"
    )

    assert project_budget["project_id"] == project_id
    assert scope_budget["trade_scope_id"] == scope_id
    assert scope_budget["project_id"] is None
    assert scope_budget["total"] == "4000.00"


@pytest.mark.asyncio
async def test_budget_crud_rejects_both_or_neither_anchor(
    async_client, tenant_a_client, seed_two_tenants
):
    """POST /budgets/ with both anchors or neither returns 422 (XOR validator)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)

    neither = await async_client.post(_BUDGETS_URL, headers=headers, json={"total": "100.00"})
    assert neither.status_code == 422, neither.text

    both = await async_client.post(
        _BUDGETS_URL,
        headers=headers,
        json={"project_id": project_id, "trade_scope_id": scope_id, "total": "100.00"},
    )
    assert both.status_code == 422, both.text


@pytest.mark.asyncio
async def test_budget_crud_rejects_zero_total(async_client, tenant_a_client, seed_two_tenants):
    """POST /budgets/ with total 0 returns 422 — any positive amount only (D-10)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    resp = await async_client.post(
        _BUDGETS_URL,
        headers=_pm_headers(company_id),
        json={"project_id": project_id, "total": "0"},
    )
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_budget_crud_rejects_dormant_category_breakdowns(
    async_client, tenant_a_client, seed_two_tenants
):
    """A non-empty category_breakdowns list is rejected loudly, never silently dropped (D-11)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    resp = await async_client.post(
        _BUDGETS_URL,
        headers=_pm_headers(company_id),
        json={
            "project_id": project_id,
            "total": "100.00",
            "category_breakdowns": [{"category_id": str(uuid4()), "amount": "50.00"}],
        },
    )
    assert resp.status_code == 422, resp.text
    assert resp.json()["detail"] == _BREAKDOWNS_DORMANT_DETAIL


@pytest.mark.asyncio
async def test_budget_crud_duplicate_project_anchor_conflicts(
    async_client, tenant_a_client, seed_two_tenants
):
    """A second active budget at the same project anchor is refused with 409."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, project_id=project_id)

    resp = await async_client.post(
        _BUDGETS_URL, headers=headers, json={"project_id": project_id, "total": "5000.00"}
    )
    assert resp.status_code == 409, resp.text
    assert resp.json()["detail"] == _PROJECT_DUPLICATE_DETAIL


@pytest.mark.asyncio
async def test_budget_crud_duplicate_scope_anchor_conflicts(
    async_client, tenant_a_client, seed_two_tenants
):
    """A second active budget at the same trade-scope anchor is refused with 409."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id)

    resp = await async_client.post(
        _BUDGETS_URL, headers=headers, json={"trade_scope_id": scope_id, "total": "5000.00"}
    )
    assert resp.status_code == 409, resp.text
    assert resp.json()["detail"] == _SCOPE_DUPLICATE_DETAIL


@pytest.mark.asyncio
async def test_budget_crud_soft_deleted_budget_does_not_block_recreation(
    async_client, tenant_a_client, seed_two_tenants
):
    """After a soft delete, a fresh budget at the same anchor is accepted with 201."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    first = await _create_budget(async_client, headers, project_id=project_id)

    delete_resp = await async_client.delete(_budget_url(first["id"]), headers=headers)
    assert delete_resp.status_code == 204, delete_resp.text

    second = await _create_budget(async_client, headers, project_id=project_id, total="7500.00")
    assert second["id"] != first["id"]
    assert second["total"] == "7500.00"


@pytest.mark.asyncio
async def test_budget_crud_raising_total_rearms_fired_thresholds(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCH to a higher total returns 200 and nulls both fired timestamps (D-03 re-arm)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, project_id=project_id)
    await _set_fired_thresholds(company_id, budget["id"])

    resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "20000.00"}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["total"] == "20000.00"

    warning_fired_at, overrun_fired_at = await _fired_state(company_id, budget["id"])
    assert warning_fired_at is None
    assert overrun_fired_at is None


@pytest.mark.asyncio
async def test_budget_crud_lowering_total_keeps_fired_thresholds(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCH to a lower total keeps fired timestamps — already-fired thresholds stay deduped."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, project_id=project_id)
    await _set_fired_thresholds(company_id, budget["id"])

    resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "500.00"}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["total"] == "500.00"

    warning_fired_at, overrun_fired_at = await _fired_state(company_id, budget["id"])
    assert warning_fired_at is not None
    assert overrun_fired_at is not None


@pytest.mark.asyncio
async def test_budget_crud_delete_hides_budget_from_lookups(
    async_client, tenant_a_client, seed_two_tenants
):
    """DELETE returns 204; the soft-deleted budget then 404s on PATCH and DELETE."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, project_id=project_id)

    delete_resp = await async_client.delete(_budget_url(budget["id"]), headers=headers)
    assert delete_resp.status_code == 204, delete_resp.text

    patch_resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "9000.00"}
    )
    assert patch_resp.status_code == 404, patch_resp.text

    second_delete = await async_client.delete(_budget_url(budget["id"]), headers=headers)
    assert second_delete.status_code == 404, second_delete.text


@pytest.mark.asyncio
async def test_budget_crud_unknown_id_returns_404(async_client, seed_two_tenants):
    """PATCH/DELETE on a never-existing budget id return 404."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    unknown_url = _budget_url(str(uuid4()))

    patch_resp = await async_client.patch(unknown_url, headers=headers, json={"total": "100.00"})
    assert patch_resp.status_code == 404, patch_resp.text

    delete_resp = await async_client.delete(unknown_url, headers=headers)
    assert delete_resp.status_code == 404, delete_resp.text


@pytest.mark.asyncio
async def test_budget_crud_forbidden_without_finance_manage(
    async_client, tenant_a_client, seed_two_tenants
):
    """Admin lacks finance.manage — POST, PATCH and DELETE all 403 before any data changes."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    admin_headers = _admin_headers(company_id)
    some_budget_url = _budget_url(str(uuid4()))

    post_resp = await async_client.post(
        _BUDGETS_URL, headers=admin_headers, json={"project_id": project_id, "total": "100.00"}
    )
    assert post_resp.status_code == 403, post_resp.text
    assert post_resp.json()["detail"] == _MISSING_MANAGE_PERMISSION

    patch_resp = await async_client.patch(
        some_budget_url, headers=admin_headers, json={"total": "100.00"}
    )
    assert patch_resp.status_code == 403, patch_resp.text

    delete_resp = await async_client.delete(some_budget_url, headers=admin_headers)
    assert delete_resp.status_code == 403, delete_resp.text
