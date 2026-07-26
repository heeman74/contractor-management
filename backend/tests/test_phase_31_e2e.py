"""Phase 31 — Actual Cost Capture: cost-entry CRUD, gating, rollup, RLS, receipts.

Covers COST-01/COST-02 (materials/subcontractor/other cost entries anchored to a
job XOR a trade scope), success criterion 4 (403 for non-finance callers on every
cost-entry endpoint), D-05 (soft-delete drops out of lists/rollup), D-02/D-05
(project rollup combines trade-scope + job costs), and API-level RLS isolation.

COST-03 (receipt upload/list/delete/serve, Plan 31-02) extends this same file.

New companies created via /auth/register (seed_two_tenants) are NOT auto-seeded
with cost_categories — only companies that existed at migration-0032-run-time are
(see test_phase_30_e2e.py::test_cost_categories_seeded_per_company). Every test
here seeds categories explicitly via _seed_cost_categories, mirroring that file.
"""

from datetime import date
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.security import create_access_token
from app.features.finance.models import CostCategory

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
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


async def _create_project(client: AsyncClient, name: str = "Test Project 31") -> str:
    resp = await client.post("/api/v1/projects/", json={"name": name, "status": "active"})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient, project_id: str, trade_name: str = "Plumbing"
) -> str:
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name, "trade_color": "#2196F3"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_job(client: AsyncClient, project_id: str | None = None) -> str:
    payload: dict = {"description": "Test job", "trade_type": "general"}
    if project_id is not None:
        payload["project_id"] = project_id
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _cost_entry_payload(category_id: str, **overrides) -> dict:
    payload = {
        "category_id": category_id,
        "amount": "125.50",
        "incurred_date": date.today().isoformat(),
        "vendor": "Acme Supply Co",
        "note": "Test cost entry",
    }
    payload.update(overrides)
    return payload


async def _create_cost_entry(
    client: AsyncClient, headers: dict, category_id: str, job_id: str
) -> str:
    resp = await client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(category_id, job_id=job_id),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


# ---------------------------------------------------------------------------
# COST-01: materials cost entry on job / trade scope
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_materials_cost_entry_on_job(async_client, tenant_a_client, seed_two_tenants):
    """COST-01: Owner/PM can POST a materials cost entry anchored to a job and read it back."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")

    headers = _pm_headers(company_id)
    create_resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(materials_id, job_id=job_id),
    )
    assert create_resp.status_code == 201, create_resp.text
    body = create_resp.json()
    assert body["job_id"] == job_id
    assert body["trade_scope_id"] is None
    assert body["amount"] == "125.50"
    assert body["vendor"] == "Acme Supply Co"
    assert body["category_name"] == "materials"

    get_resp = await async_client.get(f"/api/v1/cost-entries/{body['id']}", headers=headers)
    assert get_resp.status_code == 200, get_resp.text
    assert get_resp.json()["id"] == body["id"]
    assert get_resp.json()["amount"] == "125.50"


@pytest.mark.asyncio
async def test_create_materials_cost_entry_on_trade_scope(
    async_client, tenant_a_client, seed_two_tenants
):
    """COST-01: Owner/PM can POST a cost entry anchored to a trade scope."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")

    headers = _pm_headers(company_id)
    resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(materials_id, trade_scope_id=scope_id),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["trade_scope_id"] == scope_id
    assert body["job_id"] is None

    list_resp = await async_client.get(
        "/api/v1/cost-entries/", headers=headers, params={"trade_scope_id": scope_id}
    )
    assert list_resp.status_code == 200, list_resp.text
    assert [e["id"] for e in list_resp.json()] == [body["id"]]


@pytest.mark.asyncio
async def test_cost_entry_rejects_both_or_neither_anchor(
    async_client, tenant_a_client, seed_two_tenants
):
    """A cost entry with both or neither job_id/trade_scope_id is rejected (422)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    materials_id = await _category_id(company_id, "materials")

    headers = _pm_headers(company_id)

    neither_resp = await async_client.post(
        "/api/v1/cost-entries/", headers=headers, json=_cost_entry_payload(materials_id)
    )
    assert neither_resp.status_code == 422, neither_resp.text

    both_resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(materials_id, job_id=job_id, trade_scope_id=scope_id),
    )
    assert both_resp.status_code == 422, both_resp.text


# ---------------------------------------------------------------------------
# COST-02: subcontractor / other category cost entries
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_subcontractor_cost_entry(async_client, tenant_a_client, seed_two_tenants):
    """COST-02: Owner/PM can create subcontractor cost entries via category_id."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    subcontractor_id = await _category_id(company_id, "subcontractor")

    headers = _pm_headers(company_id)
    resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(subcontractor_id, job_id=job_id),
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["category_name"] == "subcontractor"


@pytest.mark.asyncio
async def test_create_other_category_cost_entry(async_client, tenant_a_client, seed_two_tenants):
    """COST-02: Owner/PM can create 'other' category cost entries via category_id."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    other_id = await _category_id(company_id, "other")

    headers = _pm_headers(company_id)
    resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(other_id, job_id=job_id),
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["category_name"] == "other"


# ---------------------------------------------------------------------------
# D-05: soft-delete excludes from lists + rollup
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_soft_deleted_cost_entry_excluded_from_lists_and_rollup(
    async_client, tenant_a_client, seed_two_tenants
):
    """Soft-deleted cost entries disappear from lists and the project rollup."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    materials_id = await _category_id(company_id, "materials")

    headers = _pm_headers(company_id)
    create_resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(materials_id, job_id=job_id),
    )
    assert create_resp.status_code == 201, create_resp.text
    entry_id = create_resp.json()["id"]

    rollup_before = await async_client.get(
        f"/api/v1/projects/{project_id}/cost-entries", headers=headers
    )
    assert rollup_before.status_code == 200, rollup_before.text
    assert rollup_before.json()["total"] == "125.50"

    delete_resp = await async_client.delete(f"/api/v1/cost-entries/{entry_id}", headers=headers)
    assert delete_resp.status_code == 204, delete_resp.text

    list_resp = await async_client.get(
        "/api/v1/cost-entries/", headers=headers, params={"job_id": job_id}
    )
    assert list_resp.status_code == 200, list_resp.text
    assert list_resp.json() == []

    get_resp = await async_client.get(f"/api/v1/cost-entries/{entry_id}", headers=headers)
    assert get_resp.status_code == 404, get_resp.text

    rollup_after = await async_client.get(
        f"/api/v1/projects/{project_id}/cost-entries", headers=headers
    )
    assert rollup_after.status_code == 200, rollup_after.text
    assert rollup_after.json()["total"] == "0"
    assert rollup_after.json()["entries"] == []


# ---------------------------------------------------------------------------
# D-02/D-05: project rollup combines trade-scope costs + job(project_id) costs
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_project_rollup_combines_scope_and_job_costs(
    async_client, tenant_a_client, seed_two_tenants
):
    """Project rollup = trade-scope-anchored costs + costs on jobs whose project_id = project."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id)
    job_id = await _create_job(tenant_a_client, project_id=project_id)
    unrelated_job_id = await _create_job(tenant_a_client)  # no project_id — must NOT roll up
    materials_id = await _category_id(company_id, "materials")

    headers = _pm_headers(company_id)
    scope_entry = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(materials_id, trade_scope_id=scope_id, amount="200.00"),
    )
    assert scope_entry.status_code == 201, scope_entry.text

    job_entry = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(materials_id, job_id=job_id, amount="50.25"),
    )
    assert job_entry.status_code == 201, job_entry.text

    unrelated_entry = await async_client.post(
        "/api/v1/cost-entries/",
        headers=headers,
        json=_cost_entry_payload(materials_id, job_id=unrelated_job_id, amount="999.00"),
    )
    assert unrelated_entry.status_code == 201, unrelated_entry.text

    rollup_resp = await async_client.get(
        f"/api/v1/projects/{project_id}/cost-entries", headers=headers
    )
    assert rollup_resp.status_code == 200, rollup_resp.text
    body = rollup_resp.json()
    assert body["project_id"] == project_id
    assert body["total"] == "250.25"
    entry_ids = {e["id"] for e in body["entries"]}
    assert entry_ids == {scope_entry.json()["id"], job_entry.json()["id"]}
    assert unrelated_entry.json()["id"] not in entry_ids


# ---------------------------------------------------------------------------
# RLS isolation at the API level
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_cost_entry_api_rls_isolation(async_client, tenant_a_client, seed_two_tenants):
    """Tenant B cannot read Tenant A's cost entries via the REST endpoints."""
    tenant_a_id = seed_two_tenants["tenant_a_id"]
    tenant_b_id = seed_two_tenants["tenant_b_id"]
    await _seed_cost_categories(tenant_a_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(tenant_a_id, "materials")

    a_headers = _pm_headers(tenant_a_id)
    create_resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=a_headers,
        json=_cost_entry_payload(materials_id, job_id=job_id),
    )
    assert create_resp.status_code == 201, create_resp.text
    entry_id = create_resp.json()["id"]

    b_headers = _pm_headers(tenant_b_id)
    b_get = await async_client.get(f"/api/v1/cost-entries/{entry_id}", headers=b_headers)
    assert b_get.status_code == 404, b_get.text

    b_list = await async_client.get(
        "/api/v1/cost-entries/", headers=b_headers, params={"job_id": job_id}
    )
    assert b_list.status_code == 200, b_list.text
    assert b_list.json() == []


# ---------------------------------------------------------------------------
# Success criterion 4: 403 for non-finance callers on every cost endpoint
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_non_finance_role_403_on_every_cost_endpoint(
    async_client, tenant_a_client, seed_two_tenants
):
    """A user without finance.* gets 403 on every cost-entry, rollup, and category endpoint.

    admin is excluded from finance.* by default (Phase 30) — used here as the
    non-finance role, mirroring test_phase_30_e2e.py's FINANCE_KEYS assertions.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")

    pm_headers = _pm_headers(company_id)
    seed_resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=pm_headers,
        json=_cost_entry_payload(materials_id, job_id=job_id),
    )
    assert seed_resp.status_code == 201, seed_resp.text
    entry_id = seed_resp.json()["id"]
    project_id = await _create_project(tenant_a_client)

    admin_headers = _admin_headers(company_id)

    create_resp = await async_client.post(
        "/api/v1/cost-entries/",
        headers=admin_headers,
        json=_cost_entry_payload(materials_id, job_id=job_id),
    )
    assert create_resp.status_code == 403, create_resp.text

    list_resp = await async_client.get(
        "/api/v1/cost-entries/", headers=admin_headers, params={"job_id": job_id}
    )
    assert list_resp.status_code == 403, list_resp.text

    get_resp = await async_client.get(f"/api/v1/cost-entries/{entry_id}", headers=admin_headers)
    assert get_resp.status_code == 403, get_resp.text

    patch_resp = await async_client.patch(
        f"/api/v1/cost-entries/{entry_id}", headers=admin_headers, json={"vendor": "Nope"}
    )
    assert patch_resp.status_code == 403, patch_resp.text

    delete_resp = await async_client.delete(
        f"/api/v1/cost-entries/{entry_id}", headers=admin_headers
    )
    assert delete_resp.status_code == 403, delete_resp.text

    rollup_resp = await async_client.get(
        f"/api/v1/projects/{project_id}/cost-entries", headers=admin_headers
    )
    assert rollup_resp.status_code == 403, rollup_resp.text

    categories_resp = await async_client.get("/api/v1/cost-categories/", headers=admin_headers)
    assert categories_resp.status_code == 403, categories_resp.text


# ---------------------------------------------------------------------------
# COST-03: receipt upload, fetch, multiple receipts, cross-tenant 404, 403 gating
# ---------------------------------------------------------------------------

_RECEIPT_PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


@pytest.mark.asyncio
async def test_upload_and_fetch_cost_receipt(async_client, tenant_a_client, seed_two_tenants):
    """COST-03: Owner/PM can upload a receipt and fetch it back through /files/cost-receipts/..."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    entry_id = await _create_cost_entry(async_client, headers, materials_id, job_id)

    upload_resp = await async_client.post(
        f"/api/v1/cost-entries/{entry_id}/receipts",
        headers=headers,
        files={"file": ("receipt.png", _RECEIPT_PNG_BYTES, "image/png")},
        data={"caption": "Lumber receipt"},
    )
    assert upload_resp.status_code == 201, upload_resp.text
    body = upload_resp.json()
    assert body["cost_entry_id"] == entry_id
    assert body["caption"] == "Lumber receipt"
    remote_url = body["remote_url"]
    assert remote_url.startswith("/files/cost-receipts/")

    fetch_resp = await async_client.get(remote_url, headers=headers)
    assert fetch_resp.status_code == 200, fetch_resp.text


@pytest.mark.asyncio
async def test_multiple_receipts_per_cost_entry(async_client, tenant_a_client, seed_two_tenants):
    """COST-03: a cost entry can hold multiple receipts (zero-to-many)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")
    headers = _pm_headers(company_id)
    entry_id = await _create_cost_entry(async_client, headers, materials_id, job_id)

    for filename in ("receipt-1.png", "receipt-2.png"):
        resp = await async_client.post(
            f"/api/v1/cost-entries/{entry_id}/receipts",
            headers=headers,
            files={"file": (filename, _RECEIPT_PNG_BYTES, "image/png")},
        )
        assert resp.status_code == 201, resp.text

    list_resp = await async_client.get(f"/api/v1/cost-entries/{entry_id}/receipts", headers=headers)
    assert list_resp.status_code == 200, list_resp.text
    assert len(list_resp.json()) == 2


@pytest.mark.asyncio
async def test_other_tenant_cannot_fetch_cost_receipt(
    async_client, tenant_a_client, seed_two_tenants
):
    """COST-03: Tenant B cannot fetch Tenant A's receipt file — 404, not the bytes."""
    tenant_a_id = seed_two_tenants["tenant_a_id"]
    tenant_b_id = seed_two_tenants["tenant_b_id"]
    await _seed_cost_categories(tenant_a_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(tenant_a_id, "materials")
    a_headers = _pm_headers(tenant_a_id)
    entry_id = await _create_cost_entry(async_client, a_headers, materials_id, job_id)

    upload_resp = await async_client.post(
        f"/api/v1/cost-entries/{entry_id}/receipts",
        headers=a_headers,
        files={"file": ("receipt.png", _RECEIPT_PNG_BYTES, "image/png")},
    )
    assert upload_resp.status_code == 201, upload_resp.text
    remote_url = upload_resp.json()["remote_url"]

    b_headers = _pm_headers(tenant_b_id)
    b_fetch = await async_client.get(remote_url, headers=b_headers)
    assert b_fetch.status_code == 404, b_fetch.text


@pytest.mark.asyncio
async def test_non_finance_role_403_on_every_receipt_endpoint(
    async_client, tenant_a_client, seed_two_tenants
):
    """COST-03: a user without finance.* gets 403 on upload/list/delete receipt endpoints."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    job_id = await _create_job(tenant_a_client)
    materials_id = await _category_id(company_id, "materials")
    pm_headers = _pm_headers(company_id)
    entry_id = await _create_cost_entry(async_client, pm_headers, materials_id, job_id)

    upload_resp = await async_client.post(
        f"/api/v1/cost-entries/{entry_id}/receipts",
        headers=pm_headers,
        files={"file": ("receipt.png", _RECEIPT_PNG_BYTES, "image/png")},
    )
    assert upload_resp.status_code == 201, upload_resp.text
    receipt_id = upload_resp.json()["id"]

    admin_headers = _admin_headers(company_id)

    forbidden_upload = await async_client.post(
        f"/api/v1/cost-entries/{entry_id}/receipts",
        headers=admin_headers,
        files={"file": ("receipt.png", _RECEIPT_PNG_BYTES, "image/png")},
    )
    assert forbidden_upload.status_code == 403, forbidden_upload.text

    forbidden_list = await async_client.get(
        f"/api/v1/cost-entries/{entry_id}/receipts", headers=admin_headers
    )
    assert forbidden_list.status_code == 403, forbidden_list.text

    forbidden_delete = await async_client.delete(
        f"/api/v1/cost-entries/{entry_id}/receipts/{receipt_id}", headers=admin_headers
    )
    assert forbidden_delete.status_code == 403, forbidden_delete.text
