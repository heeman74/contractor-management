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

import asyncio
from datetime import UTC, date, datetime
from unittest.mock import patch
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.security import create_access_token
from app.core.tenant import set_current_tenant_id
from app.features.finance.budget_repository import BudgetRepository
from app.features.finance.budget_service import BudgetService
from app.features.finance.models import CostCategory
from app.features.rbac.repository import RbacRepository

_BUDGETS_URL = "/api/v1/budgets/"
_SECONDS_PER_HOUR = 3600
_MISSING_MANAGE_PERMISSION = "Missing permission: finance.manage"
_MISSING_VIEW_PERMISSION = "Missing permission: finance.view"
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

_ALERT_ROWS_SQL = (
    "SELECT alert_type, severity, impact_text, project_id, trade_scope_id "
    "FROM dashboard_alerts ORDER BY created_at, alert_type"
)

_ASSIGN_ROLE_SQL = (
    "INSERT INTO user_roles (company_id, user_id, role) "
    "VALUES (CAST(:company_id AS uuid), CAST(:user_id AS uuid), :role)"
)

_SEND_BUDGET_PUSH_TARGET = (
    "app.features.notifications.service.NotificationService.send_budget_alert_notification"
)

_TIME_ENTRY_SEED_SQL = (
    "INSERT INTO time_entries (company_id, job_id, contractor_id, clocked_in_at, "
    "clocked_out_at, duration_seconds, session_status, deleted_at) "
    "VALUES (CAST(:company_id AS uuid), CAST(:job_id AS uuid), "
    "CAST(:contractor_id AS uuid), :clocked_in_at, :clocked_out_at, "
    ":duration_seconds, 'completed', NULL)"
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


# ---------------------------------------------------------------------------
# BUDG-02: budget-vs-actual block on the breakdown/rollup responses
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_budget_vs_actual_scope_breakdown_spent_equals_grand_total(
    async_client, tenant_a_client, seed_two_tenants
):
    """The scope breakdown's budget block reuses the response's own grand_total as spent."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    subcontractor_id = await _category_id(company_id, "subcontractor")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="2000.00"
    )
    await _add_cost_entry(
        async_client,
        headers,
        trade_scope_id=scope_id,
        category_id=subcontractor_id,
        amount="1500.00",
    )
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")

    body = await _scope_breakdown(async_client, headers, scope_id)
    budget = body["budget"]
    assert budget is not None, body
    assert budget["total"] == "10000.00"
    assert body["grand_total"] == "3500.00"
    assert budget["spent"] == body["grand_total"]
    assert budget["remaining"] == "6500.00"
    assert budget["percent_used"] == "35.0"


@pytest.mark.asyncio
async def test_budget_vs_actual_project_rollup_spent_includes_derived_labor(
    async_client, tenant_a_client, seed_two_tenants
):
    """The project rollup's budget block counts cost entries plus derived labor as spent."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    worker_id = await _create_user(tenant_a_client, "worker-budget-34@tenant-a.com")
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="300.00"
    )
    await _add_cost_entry(
        async_client, headers, job_id=job_id, category_id=materials_id, amount="100.00"
    )
    await _post_rate(async_client, headers, worker_id, "50.00", date(2026, 1, 1))
    await _seed_time_entry(
        company_id, job_id, worker_id, 1, clocked_in_at=datetime(2026, 6, 10, 15, 0, tzinfo=UTC)
    )
    await _create_budget(async_client, headers, project_id=project_id, total="1000.00")

    body = await _project_rollup(async_client, headers, project_id)
    budget = body["budget"]
    assert budget is not None, body
    assert body["grand_total"] == "450.00"
    assert budget["spent"] == body["grand_total"]
    assert budget["total"] == "1000.00"
    assert budget["remaining"] == "550.00"
    assert budget["percent_used"] == "45.0"


@pytest.mark.asyncio
async def test_budget_vs_actual_over_budget_is_never_clamped(
    async_client, tenant_a_client, seed_two_tenants
):
    """Spend above total yields a negative remaining and a percent over 100 — honest (D-10)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="1200.00"
    )
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="1000.00")

    body = await _scope_breakdown(async_client, headers, scope_id)
    budget = body["budget"]
    assert budget is not None, body
    assert budget["spent"] == body["grand_total"] == "1200.00"
    assert budget["remaining"] == "-200.00"
    assert budget["percent_used"] == "120.0"


@pytest.mark.asyncio
async def test_budget_vs_actual_key_is_present_and_null_without_budget(
    async_client, tenant_a_client, seed_two_tenants
):
    """With no budget at the anchor the budget key is present and null on both responses."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)

    scope_body = await _scope_breakdown(async_client, headers, scope_id)
    assert "budget" in scope_body
    assert scope_body["budget"] is None

    rollup_body = await _project_rollup(async_client, headers, project_id)
    assert "budget" in rollup_body
    assert rollup_body["budget"] is None


@pytest.mark.asyncio
async def test_budget_vs_actual_soft_deleted_budget_behaves_like_none(
    async_client, tenant_a_client, seed_two_tenants
):
    """A soft-deleted budget disappears from the breakdown exactly like no budget."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, trade_scope_id=scope_id)

    with_budget = await _scope_breakdown(async_client, headers, scope_id)
    assert with_budget["budget"] is not None

    delete_resp = await async_client.delete(_budget_url(budget["id"]), headers=headers)
    assert delete_resp.status_code == 204, delete_resp.text

    after_delete = await _scope_breakdown(async_client, headers, scope_id)
    assert after_delete["budget"] is None


@pytest.mark.asyncio
async def test_budget_vs_actual_job_breakdown_never_carries_budget(
    async_client, tenant_a_client, seed_two_tenants
):
    """The job breakdown never carries a non-null budget block — budgets anchor project/scope."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, project_id=project_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="4000.00")

    body = await _job_breakdown(async_client, headers, job_id)
    assert body.get("budget") is None


@pytest.mark.asyncio
async def test_budget_vs_actual_forbidden_without_finance_view(
    async_client, tenant_a_client, seed_two_tenants
):
    """Admin lacks finance.view — the budget-bearing reads still 403 (unchanged gating)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    admin_headers = _admin_headers(company_id)

    scope_resp = await async_client.get(
        f"/api/v1/trade-scopes/{scope_id}/cost-breakdown", headers=admin_headers
    )
    assert scope_resp.status_code == 403, scope_resp.text
    assert scope_resp.json()["detail"] == _MISSING_VIEW_PERMISSION

    rollup_resp = await async_client.get(
        f"/api/v1/projects/{project_id}/cost-entries", headers=admin_headers
    )
    assert rollup_resp.status_code == 403, rollup_resp.text


# ---------------------------------------------------------------------------
# BUDG-03: alert evaluation — exactly-once threshold firing + locked copy
# ---------------------------------------------------------------------------


async def _alert_rows(company_id: str) -> list:
    """Read (alert_type, severity, impact_text, project_id, trade_scope_id) rows via SQL."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_ALERT_ROWS_SQL))
        return result.all()


async def _evaluate_in_own_session(company_id: str, budget_id: str) -> int:
    """Evaluate one budget in an independent session/transaction (the cron/mutation shape)."""
    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        budget = await BudgetRepository(db).active_by_id_or_404(UUID(budget_id))
        fired = await BudgetService(db).evaluate_budget(budget)
        await db.commit()  # REQUIRED: without a commit the loser blocks on the row lock
        return len(fired)


async def _seed_scope_budget_with_spend(
    async_client: AsyncClient,
    tenant_a_client: AsyncClient,
    company_id: str,
    *,
    total: str = "10000.00",
    amount: str = "8200.00",
) -> tuple[str, str, str]:
    """Seed project 'Riverside Remodel' + 'Plumbing' scope + scope budget + one cost entry.

    Returns (project_id, scope_id, budget_id).
    """
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client, name="Riverside Remodel")
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, trade_scope_id=scope_id, total=total)
    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount=amount
    )
    return project_id, scope_id, budget["id"]


@pytest.mark.asyncio
async def test_alerts_warning_crossing_writes_locked_copy(
    async_client, tenant_a_client, seed_two_tenants
):
    """Crossing 80% creates one budget_warning alert with the verbatim UI-SPEC scope copy."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id, scope_id, budget_id = await _seed_scope_budget_with_spend(
        async_client, tenant_a_client, company_id
    )

    fired_count = await _evaluate_in_own_session(company_id, budget_id)

    assert fired_count == 1
    rows = await _alert_rows(company_id)
    assert len(rows) == 1
    alert_type, severity, impact_text, alert_project_id, alert_scope_id = rows[0]
    assert alert_type == "budget_warning"
    assert severity == "warning"
    assert impact_text == (
        "Riverside Remodel — Plumbing scope has spent $8,200 of its $10,000 budget (82%)."
    )
    assert str(alert_project_id) == project_id
    assert str(alert_scope_id) == scope_id


@pytest.mark.asyncio
async def test_alerts_reevaluation_fires_each_threshold_only_once(
    async_client, tenant_a_client, seed_two_tenants
):
    """Re-running evaluation with unchanged spend never creates a second alert (keystone 1)."""
    company_id = seed_two_tenants["tenant_a_id"]
    _, _, budget_id = await _seed_scope_budget_with_spend(async_client, tenant_a_client, company_id)

    first = await _evaluate_in_own_session(company_id, budget_id)
    second = await _evaluate_in_own_session(company_id, budget_id)

    assert first == 1
    assert second == 0
    assert len(await _alert_rows(company_id)) == 1


@pytest.mark.asyncio
async def test_alerts_jump_past_both_thresholds_fires_warning_and_overrun(
    async_client, tenant_a_client, seed_two_tenants
):
    """A 0% -> 120% jump fires one budget_warning AND one budget_overrun (critical)."""
    company_id = seed_two_tenants["tenant_a_id"]
    _, _, budget_id = await _seed_scope_budget_with_spend(
        async_client, tenant_a_client, company_id, amount="12000.00"
    )

    fired_count = await _evaluate_in_own_session(company_id, budget_id)

    assert fired_count == 2
    rows = await _alert_rows(company_id)
    by_type = {row.alert_type: row for row in rows}
    assert set(by_type) == {"budget_warning", "budget_overrun"}
    assert by_type["budget_warning"].severity == "warning"
    assert by_type["budget_overrun"].severity == "critical"
    assert by_type["budget_overrun"].impact_text == (
        "Riverside Remodel — Plumbing scope has exceeded its $10,000 budget — $12,000 spent (120%)."
    )


@pytest.mark.asyncio
async def test_alerts_raising_budget_rearms_and_next_crossing_alerts_again(
    async_client, tenant_a_client, seed_two_tenants
):
    """Raising the total re-arms (D-03): crossing 80% of the NEW total fires a fresh warning."""
    company_id = seed_two_tenants["tenant_a_id"]
    _, scope_id, budget_id = await _seed_scope_budget_with_spend(
        async_client, tenant_a_client, company_id
    )
    headers = _pm_headers(company_id)
    assert await _evaluate_in_own_session(company_id, budget_id) == 1

    patch_resp = await async_client.patch(
        _budget_url(budget_id), headers=headers, json={"total": "20000.00"}
    )
    assert patch_resp.status_code == 200, patch_resp.text
    materials_id = await _category_id(company_id, "materials")
    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="8000.00"
    )

    assert await _evaluate_in_own_session(company_id, budget_id) == 1
    warning_rows = [r for r in await _alert_rows(company_id) if r.alert_type == "budget_warning"]
    assert len(warning_rows) == 2


@pytest.mark.asyncio
async def test_alerts_lowering_budget_below_spend_fires_on_next_evaluation(
    async_client, tenant_a_client, seed_two_tenants
):
    """Lowering the total below spend fires the crossed thresholds next evaluation (D-10)."""
    company_id = seed_two_tenants["tenant_a_id"]
    _, _, budget_id = await _seed_scope_budget_with_spend(
        async_client, tenant_a_client, company_id, amount="5000.00"
    )
    assert await _evaluate_in_own_session(company_id, budget_id) == 0

    patch_resp = await async_client.patch(
        _budget_url(budget_id), headers=_pm_headers(company_id), json={"total": "4000.00"}
    )
    assert patch_resp.status_code == 200, patch_resp.text

    assert await _evaluate_in_own_session(company_id, budget_id) == 2
    rows = await _alert_rows(company_id)
    assert {row.alert_type for row in rows} == {"budget_warning", "budget_overrun"}


@pytest.mark.asyncio
async def test_alerts_concurrent_evaluations_fire_exactly_once(
    async_client, tenant_a_client, seed_two_tenants
):
    """Two racing evaluations in SEPARATE transactions yield one alert, not two."""
    company_id = seed_two_tenants["tenant_a_id"]
    _, _, budget_id = await _seed_scope_budget_with_spend(async_client, tenant_a_client, company_id)

    results = await asyncio.gather(
        _evaluate_in_own_session(company_id, budget_id),
        _evaluate_in_own_session(company_id, budget_id),
    )

    assert sum(results) == 1
    rows = await _alert_rows(company_id)
    assert [row.alert_type for row in rows] == ["budget_warning"]
    warning_fired_at, overrun_fired_at = await _fired_state(company_id, budget_id)
    assert warning_fired_at is not None
    assert overrun_fired_at is None


@pytest.mark.asyncio
async def test_alerts_soft_deleted_anchor_produces_no_alert(
    async_client, tenant_a_client, seed_two_tenants
):
    """A budget whose scope was soft-deleted evaluates to nothing — no alert, no claim burned."""
    company_id = seed_two_tenants["tenant_a_id"]
    _, scope_id, budget_id = await _seed_scope_budget_with_spend(
        async_client, tenant_a_client, company_id
    )
    delete_resp = await tenant_a_client.delete(f"/api/v1/trade-scopes/{scope_id}")
    assert delete_resp.status_code == 204, delete_resp.text

    assert await _evaluate_in_own_session(company_id, budget_id) == 0

    assert await _alert_rows(company_id) == []
    warning_fired_at, overrun_fired_at = await _fired_state(company_id, budget_id)
    assert warning_fired_at is None
    assert overrun_fired_at is None


@pytest.mark.asyncio
async def test_alerts_dashboard_visibility_follows_finance_view(
    async_client, tenant_a_client, seed_two_tenants
):
    """GET /dashboard/alerts includes budget alerts for finance.view holders only (keystone 3)."""
    company_id = seed_two_tenants["tenant_a_id"]
    _, _, budget_id = await _seed_scope_budget_with_spend(async_client, tenant_a_client, company_id)
    assert await _evaluate_in_own_session(company_id, budget_id) == 1

    pm_resp = await async_client.get("/api/v1/dashboard/alerts", headers=_pm_headers(company_id))
    assert pm_resp.status_code == 200, pm_resp.text
    pm_types = [alert["alert_type"] for alert in pm_resp.json()]
    assert "budget_warning" in pm_types

    admin_resp = await async_client.get(
        "/api/v1/dashboard/alerts", headers=_admin_headers(company_id)
    )
    assert admin_resp.status_code == 200, admin_resp.text
    admin_types = [alert["alert_type"] for alert in admin_resp.json()]
    assert "budget_warning" not in admin_types
    assert "budget_overrun" not in admin_types


# ---------------------------------------------------------------------------
# BUDG-03: FCM push targeting — finance.view holders from the live matrix
# ---------------------------------------------------------------------------


async def _assign_role(company_id: str, user_id: str, role: str) -> None:
    """Insert a user_roles row directly (no role-assignment endpoint exists)."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_ASSIGN_ROLE_SQL),
            {"company_id": company_id, "user_id": user_id, "role": role},
        )
        await session.commit()


async def _seed_role_holders(tenant_a_client: AsyncClient, company_id: str) -> tuple[str, str, str]:
    """Create an owner, a project_manager and a contractor user. Returns their ids."""
    owner_id = await _create_user(tenant_a_client, "owner-alerts-34@tenant-a.com")
    pm_id = await _create_user(tenant_a_client, "pm-alerts-34@tenant-a.com")
    contractor_id = await _create_user(tenant_a_client, "contractor-alerts-34@tenant-a.com")
    await _assign_role(company_id, owner_id, "owner")
    await _assign_role(company_id, pm_id, "project_manager")
    await _assign_role(company_id, contractor_id, "contractor")
    return owner_id, pm_id, contractor_id


async def _flush_background_pushes(calls: list, expected: int = 1) -> None:
    """Yield to the event loop until the fire-and-forget push task has run."""
    for _ in range(40):
        if len(calls) >= expected:
            return
        await asyncio.sleep(0.05)


@pytest.mark.asyncio
async def test_alerts_push_targets_finance_view_holders_only(
    async_client, tenant_a_client, seed_two_tenants
):
    """The push goes exactly once to owner + PM (finance.view) and never to others (keystone 3)."""
    company_id = seed_two_tenants["tenant_a_id"]
    owner_id, pm_id, contractor_id = await _seed_role_holders(tenant_a_client, company_id)
    project_id, scope_id, budget_id = await _seed_scope_budget_with_spend(
        async_client, tenant_a_client, company_id
    )
    calls: list[dict] = []

    async def _capture(**kwargs):
        calls.append(kwargs)

    with patch(_SEND_BUDGET_PUSH_TARGET, side_effect=_capture):
        assert await _evaluate_in_own_session(company_id, budget_id) == 1
        await _flush_background_pushes(calls)

    assert len(calls) == 1
    recipients = {str(user_id) for user_id in calls[0]["recipient_ids"]}
    assert owner_id in recipients
    assert pm_id in recipients
    assert contractor_id not in recipients
    assert seed_two_tenants["tenant_a_user_id"] not in recipients  # admin: no finance.view
    assert calls[0]["title"] == "Budget warning"
    assert calls[0]["body"] == (
        "Riverside Remodel — Plumbing scope has spent $8,200 of its $10,000 budget (82%)."
    )
    data = calls[0]["data"]
    assert data["type"] == "budget_alert"
    assert data["alert_type"] == "budget_warning"
    assert data["project_id"] == project_id
    assert data["trade_scope_id"] == scope_id
    assert data["alert_id"]
    assert all(isinstance(value, str) for value in data.values())


@pytest.mark.asyncio
async def test_alerts_push_respects_live_matrix_revocation(
    async_client, tenant_a_client, seed_two_tenants
):
    """Revoking finance.view from project_manager targets only the owner — live matrix, no
    hardcoded role list."""
    company_id = seed_two_tenants["tenant_a_id"]
    owner_id, pm_id, _ = await _seed_role_holders(tenant_a_client, company_id)
    _, _, budget_id = await _seed_scope_budget_with_spend(async_client, tenant_a_client, company_id)
    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        await RbacRepository(db).set_role(UUID(company_id), "project_manager", ["projects.view"])
        await db.commit()
    calls: list[dict] = []

    async def _capture(**kwargs):
        calls.append(kwargs)

    with patch(_SEND_BUDGET_PUSH_TARGET, side_effect=_capture):
        assert await _evaluate_in_own_session(company_id, budget_id) == 1
        await _flush_background_pushes(calls)

    assert len(calls) == 1
    recipients = {str(user_id) for user_id in calls[0]["recipient_ids"]}
    assert owner_id in recipients
    assert pm_id not in recipients


@pytest.mark.asyncio
async def test_alerts_push_project_budget_sends_empty_scope_id(
    async_client, tenant_a_client, seed_two_tenants
):
    """A project-budget push carries trade_scope_id "" and the project-variant copy."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_role_holders(tenant_a_client, company_id)
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client, name="Riverside Remodel")
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, project_id=project_id, total="1000.00")
    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="900.00"
    )
    calls: list[dict] = []

    async def _capture(**kwargs):
        calls.append(kwargs)

    with patch(_SEND_BUDGET_PUSH_TARGET, side_effect=_capture):
        assert await _evaluate_in_own_session(company_id, budget["id"]) == 1
        await _flush_background_pushes(calls)

    assert len(calls) == 1
    assert calls[0]["title"] == "Budget warning"
    assert calls[0]["body"] == "Riverside Remodel has spent $900 of its $1,000 budget (90%)."
    data = calls[0]["data"]
    assert data["project_id"] == project_id
    assert data["trade_scope_id"] == ""


@pytest.mark.asyncio
async def test_alerts_push_failure_never_breaks_evaluation(
    async_client, tenant_a_client, seed_two_tenants
):
    """A raising notification never breaks evaluation — the alert row is still committed."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_role_holders(tenant_a_client, company_id)
    _, _, budget_id = await _seed_scope_budget_with_spend(async_client, tenant_a_client, company_id)

    async def _explode(**kwargs):
        raise RuntimeError("Simulated FCM network failure")

    with patch(_SEND_BUDGET_PUSH_TARGET, side_effect=_explode):
        assert await _evaluate_in_own_session(company_id, budget_id) == 1
        await asyncio.sleep(0.2)

    rows = await _alert_rows(company_id)
    assert [row.alert_type for row in rows] == ["budget_warning"]
    warning_fired_at, _ = await _fired_state(company_id, budget_id)
    assert warning_fired_at is not None


@pytest.mark.asyncio
async def test_alerts_push_skipped_silently_without_firebase_credentials(
    async_client, tenant_a_client, seed_two_tenants
):
    """With no Firebase credentials the send is skipped and evaluation still succeeds."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_role_holders(tenant_a_client, company_id)
    _, _, budget_id = await _seed_scope_budget_with_spend(async_client, tenant_a_client, company_id)

    with patch("app.features.notifications.service._get_firebase_app", return_value=None):
        assert await _evaluate_in_own_session(company_id, budget_id) == 1
        await asyncio.sleep(0.2)

    rows = await _alert_rows(company_id)
    assert [row.alert_type for row in rows] == ["budget_warning"]


# ---------------------------------------------------------------------------
# BUDG-03 (34-06): cost-mutation and budget-edit hooks evaluate automatically
# ---------------------------------------------------------------------------


async def _patch_cost_entry(
    client: AsyncClient, headers: dict, entry_id: str, amount: str
) -> None:
    """PATCH a cost entry's amount through the API."""
    resp = await client.patch(
        f"/api/v1/cost-entries/{entry_id}", headers=headers, json={"amount": amount}
    )
    assert resp.status_code == 200, resp.text


async def _delete_cost_entry(client: AsyncClient, headers: dict, entry_id: str) -> None:
    """DELETE (soft) a cost entry through the API."""
    resp = await client.delete(f"/api/v1/cost-entries/{entry_id}", headers=headers)
    assert resp.status_code == 204, resp.text


@pytest.mark.asyncio
async def test_mutation_create_scope_entry_fires_scope_warning(
    async_client, tenant_a_client, seed_two_tenants
):
    """POST /cost-entries/ pushing a scope budget to 82% fires the warning with no manual call."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client, name="Riverside Remodel")
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="8200.00"
    )

    rows = await _alert_rows(company_id)
    assert [row.alert_type for row in rows] == ["budget_warning"]
    assert str(rows[0].trade_scope_id) == scope_id


@pytest.mark.asyncio
async def test_mutation_scope_entry_leaves_under_threshold_project_budget_alone(
    async_client, tenant_a_client, seed_two_tenants
):
    """The scope's project budget is evaluated independently — under 80% it fires nothing (D-04)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")
    await _create_budget(async_client, headers, project_id=project_id, total="100000.00")

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="8200.00"
    )

    rows = await _alert_rows(company_id)
    assert [row.alert_type for row in rows] == ["budget_warning"]
    assert str(rows[0].trade_scope_id) == scope_id


@pytest.mark.asyncio
async def test_mutation_scope_entry_evaluates_scope_and_project_budgets_independently(
    async_client, tenant_a_client, seed_two_tenants
):
    """One scope-anchored POST crosses BOTH the scope and the project thresholds — two alerts."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")
    await _create_budget(async_client, headers, project_id=project_id, total="9000.00")

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="8200.00"
    )

    rows = await _alert_rows(company_id)
    assert len(rows) == 2
    assert {row.alert_type for row in rows} == {"budget_warning"}
    scope_ids = {row.trade_scope_id for row in rows}
    assert None in scope_ids  # the project budget's own alert, no cascade needed
    assert scope_id in {str(value) for value in scope_ids if value is not None}


@pytest.mark.asyncio
async def test_mutation_job_entry_evaluates_project_budget(
    async_client, tenant_a_client, seed_two_tenants
):
    """A job-anchored POST reaches the project budget via jobs.project_id."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, project_id=project_id, total="1000.00")

    await _add_cost_entry(
        async_client, headers, job_id=job_id, category_id=materials_id, amount="900.00"
    )

    rows = await _alert_rows(company_id)
    assert [row.alert_type for row in rows] == ["budget_warning"]
    assert rows[0].trade_scope_id is None


@pytest.mark.asyncio
async def test_mutation_job_without_project_evaluates_nothing(
    async_client, tenant_a_client, seed_two_tenants
):
    """A job with project_id NULL evaluates nothing and the POST still succeeds."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, job_id=job_id, category_id=materials_id, amount="900.00"
    )

    assert await _alert_rows(company_id) == []


@pytest.mark.asyncio
async def test_mutation_update_raising_amount_fires_threshold(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCH /cost-entries/{id} raising the amount past 80% fires the warning inline."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")
    entry_id = await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="5000.00"
    )
    assert await _alert_rows(company_id) == []

    await _patch_cost_entry(async_client, headers, entry_id, "8500.00")

    rows = await _alert_rows(company_id)
    assert [row.alert_type for row in rows] == ["budget_warning"]


@pytest.mark.asyncio
async def test_mutation_delete_dropping_spend_keeps_fired_state_sticky(
    async_client, tenant_a_client, seed_two_tenants
):
    """DELETE dropping spend back below 80% fires nothing new and un-fires nothing (D-01)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")
    entry_id = await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="8200.00"
    )
    assert len(await _alert_rows(company_id)) == 1

    await _delete_cost_entry(async_client, headers, entry_id)

    assert len(await _alert_rows(company_id)) == 1
    warning_fired_at, _ = await _fired_state(company_id, budget["id"])
    assert warning_fired_at is not None


@pytest.mark.asyncio
async def test_mutation_budget_edit_below_spend_fires_inline(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCH /budgets/{id} lowering the total below spend fires in the SAME request (D-10)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="5000.00"
    )
    budget = await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")
    assert await _alert_rows(company_id) == []

    patch_resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "4000.00"}
    )
    assert patch_resp.status_code == 200, patch_resp.text

    rows = await _alert_rows(company_id)
    assert {row.alert_type for row in rows} == {"budget_warning", "budget_overrun"}


@pytest.mark.asyncio
async def test_mutation_budget_edit_raise_rearms_without_firing(
    async_client, tenant_a_client, seed_two_tenants
):
    """PATCH raising the total re-arms (D-03) and fires nothing until the new thresholds cross."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    budget = await _create_budget(async_client, headers, trade_scope_id=scope_id, total="10000.00")
    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="8200.00"
    )
    assert len(await _alert_rows(company_id)) == 1

    patch_resp = await async_client.patch(
        _budget_url(budget["id"]), headers=headers, json={"total": "20000.00"}
    )
    assert patch_resp.status_code == 200, patch_resp.text

    assert len(await _alert_rows(company_id)) == 1  # 41% of the new total: nothing new
    warning_fired_at, overrun_fired_at = await _fired_state(company_id, budget["id"])
    assert warning_fired_at is None
    assert overrun_fired_at is None


@pytest.mark.asyncio
async def test_mutation_anchor_without_budget_returns_normally(
    async_client, tenant_a_client, seed_two_tenants
):
    """A cost entry at an anchor with no budget creates cleanly and fires nothing."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)

    await _add_cost_entry(
        async_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="8200.00"
    )

    assert await _alert_rows(company_id) == []
