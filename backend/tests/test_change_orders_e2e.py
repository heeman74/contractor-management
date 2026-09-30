"""E2E: change orders — quote-variant amendments to an existing project.

A change order (quote_kind='change_order') is raised against an existing project
from an in-progress job. On client approval it adds a new job (or extends the
originating job), shifts the project schedule, and rolls its amount into the
project budget.
"""

from __future__ import annotations

from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.main import app as fastapi_app
from tests.quote_client_helpers import ensure_client

_ADMIN_EMAIL = "admin@tenant-a.com"
_ADMIN_PASSWORD = "TestPass123!"

# labor 8x$80 + material 5x$40 = $840 (no tax/discount) -> the change order total.
_CO_TOTAL = Decimal("840.00")
_CO_LINE_ITEMS = [
    {
        "item_type": "labor",
        "description": "Replace rotted subfloor",
        "quantity": "8.000",
        "unit": "hr",
        "unit_price": "80.00",
        "sort_order": 0,
    },
    {
        "item_type": "material",
        "description": "Plywood sheets",
        "quantity": "5.000",
        "unit": "ea",
        "unit_price": "40.00",
        "sort_order": 1,
    },
]


async def _create_project(client: AsyncClient, *, target_end_date: str | None = None) -> dict:
    body: dict = {"name": "Kitchen Reno"}
    if target_end_date:
        body["target_end_date"] = target_end_date
    resp = await client.post("/api/v1/projects/", json=body)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _create_job(
    client: AsyncClient,
    *,
    project_id: str,
    trade_type: str = "Carpentry",
    client_id: str | None = None,
) -> dict:
    body: dict = {
        "description": "Frame walls",
        "trade_type": trade_type,
        "project_id": project_id,
    }
    # Defaulted rather than left unset: a change-order quote gets sent, and
    # sending now requires a client.
    body["client_id"] = client_id or await ensure_client(client)
    resp = await client.post("/api/v1/jobs/", json=body)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _co_body(
    *,
    project_id: str,
    originating_job_id: str,
    co_target: str,
    reason: str = "Rotted subfloor found during demo",
    schedule_days: int | None = None,
) -> dict:
    body: dict = {
        "quote_kind": "change_order",
        "project_id": project_id,
        "originating_job_id": originating_job_id,
        "co_target": co_target,
        "change_reason": reason,
        "line_items": _CO_LINE_ITEMS,
    }
    if schedule_days is not None:
        body["schedule_impact_days"] = schedule_days
    return body


async def _create_co(client: AsyncClient, **kwargs) -> dict:
    resp = await client.post("/api/v1/quotes/", json=_co_body(**kwargs))
    assert resp.status_code == 201, resp.text
    return resp.json()


def _finance_headers(company_id: str) -> dict:
    """Header for a project_manager token — finance.manage/view (owner is excluded)."""
    return {
        "Authorization": f"Bearer {create_access_token(uuid4(), UUID(company_id), ['project_manager'])}"
    }


async def _client_role_token(admin_client: AsyncClient, user_id: str) -> str:
    await admin_client.post(
        f"/api/v1/users/{user_id}/roles", json={"user_id": user_id, "role": "client"}
    )
    resp = await admin_client.post(
        "/api/v1/auth/login", json={"email": _ADMIN_EMAIL, "password": _ADMIN_PASSWORD}
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["access_token"]


async def _send_and_approve(admin_client: AsyncClient, user_id: str, quote_id: str) -> dict:
    # Address the quote to the user who is about to approve it. Approval is
    # restricted to the quote's client, so a token that merely carries the client
    # role is no longer enough — which is the point: before, any client of the
    # company could approve a quote priced for somebody else.
    addressed = await admin_client.patch(f"/api/v1/quotes/{quote_id}", json={"client_id": user_id})
    assert addressed.status_code == 200, addressed.text

    send = await admin_client.post(f"/api/v1/quotes/{quote_id}/send")
    assert send.status_code == 200, send.text
    token = await _client_role_token(admin_client, user_id)
    async with AsyncClient(
        transport=ASGITransport(app=fastapi_app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as client:
        approve = await client.post(f"/api/v1/quotes/{quote_id}/approve")
    assert approve.status_code == 200, approve.text
    return approve.json()


@pytest.mark.asyncio
async def test_change_order_new_job_created_on_approval(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    user_id = seed_two_tenants["tenant_a_user_id"]
    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"], trade_type="Carpentry")

    co = await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="new_job",
    )
    assert co["quote_kind"] == "change_order"
    assert co["co_number"] == 1

    approved = await _send_and_approve(tenant_a_client, user_id, co["id"])
    assert approved["status"] == "approved"
    assert approved["created_job_id"], "a new job should have been created"

    jobs = (await tenant_a_client.get(f"/api/v1/jobs/?project_id={project['id']}")).json()
    assert len(jobs) == 2  # originating + change-order job
    new_job = next(j for j in jobs if j["id"] == approved["created_job_id"])
    assert new_job["trade_type"] == "Carpentry"  # inherits the originating job's trade
    assert "Rotted subfloor" in new_job["description"]
    assert "Plywood sheets" in (new_job["notes"] or "")


@pytest.mark.asyncio
async def test_change_order_extends_existing_job(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    user_id = seed_two_tenants["tenant_a_user_id"]
    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"])

    co = await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="existing_job",
    )
    approved = await _send_and_approve(tenant_a_client, user_id, co["id"])
    assert approved["created_job_id"] is None

    jobs = (await tenant_a_client.get(f"/api/v1/jobs/?project_id={project['id']}")).json()
    assert len(jobs) == 1  # no new job
    updated = (await tenant_a_client.get(f"/api/v1/jobs/{job['id']}")).json()
    assert "[CO-1]" in (updated["notes"] or "")


@pytest.mark.asyncio
async def test_change_order_extends_project_schedule(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    user_id = seed_two_tenants["tenant_a_user_id"]
    project = await _create_project(tenant_a_client, target_end_date="2026-08-01")
    job = await _create_job(tenant_a_client, project_id=project["id"])

    co = await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="new_job",
        schedule_days=5,
    )
    await _send_and_approve(tenant_a_client, user_id, co["id"])

    updated = (await tenant_a_client.get(f"/api/v1/projects/{project['id']}")).json()
    assert updated["target_end_date"] == "2026-08-06"  # +5 days


@pytest.mark.asyncio
async def test_change_order_rolls_into_project_budget(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    user_id = seed_two_tenants["tenant_a_user_id"]
    finance = _finance_headers(seed_two_tenants["tenant_a_id"])
    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"])

    budget = await tenant_a_client.post(
        "/api/v1/budgets/",
        json={"project_id": project["id"], "total": "10000.00"},
        headers=finance,
    )
    assert budget.status_code == 201, budget.text

    co = await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="new_job",
    )
    await _send_and_approve(tenant_a_client, user_id, co["id"])

    financials = (
        await tenant_a_client.get(f"/api/v1/projects/{project['id']}/financials", headers=finance)
    ).json()
    assert Decimal(financials["breakdown"]["budget"]["total"]) == Decimal("10000.00") + _CO_TOTAL


@pytest.mark.asyncio
async def test_change_order_numbers_are_sequential_per_project(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"])

    co1 = await _create_co(
        tenant_a_client, project_id=project["id"], originating_job_id=job["id"], co_target="new_job"
    )
    co2 = await _create_co(
        tenant_a_client, project_id=project["id"], originating_job_id=job["id"], co_target="new_job"
    )
    assert co1["co_number"] == 1
    assert co2["co_number"] == 2


@pytest.mark.asyncio
async def test_change_order_validation(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"])
    base = {
        "quote_kind": "change_order",
        "project_id": project["id"],
        "originating_job_id": job["id"],
        "co_target": "new_job",
        "line_items": [],
    }
    for missing in ("project_id", "originating_job_id", "co_target"):
        body = {k: v for k, v in base.items() if k != missing}
        resp = await tenant_a_client.post("/api/v1/quotes/", json=body)
        assert resp.status_code == 422, f"missing {missing}: {resp.text}"

    # project_id is only valid on a change order, never a standard quote.
    resp = await tenant_a_client.post(
        "/api/v1/quotes/",
        json={"quote_kind": "standard", "project_id": project["id"], "line_items": []},
    )
    assert resp.status_code == 422, resp.text


@pytest.fixture
def _stub_pdf(monkeypatch):
    """Stub the HTML->PDF step (no libpango in this env)."""
    from app.features.pdf.service import PdfService

    monkeypatch.setattr(PdfService, "_html_to_pdf", staticmethod(lambda html: b"%PDF-1.4 co"))


@pytest.mark.asyncio
@pytest.mark.usefixtures("_stub_pdf")
async def test_change_order_can_be_turned_into_a_signable_contract(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    user_id = seed_two_tenants["tenant_a_user_id"]
    project = await _create_project(tenant_a_client)
    # The originating job carries the client — the contract signer comes from it.
    job = await _create_job(tenant_a_client, project_id=project["id"], client_id=user_id)

    co = await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="new_job",
    )
    await _send_and_approve(tenant_a_client, user_id, co["id"])

    gen = await tenant_a_client.post("/api/v1/contracts", json={"quote_id": co["id"]})
    assert gen.status_code == 201, gen.text
    contract = gen.json()
    assert contract["quote_id"] == co["id"]
    assert contract["job_id"] == job["id"]  # traced back to the originating job
    assert contract["unsigned_pdf_url"] is not None
    # The signer identity was resolved from the originating job's client.
    assert "admin@tenant-a.com" in contract["terms_snapshot"]


@pytest.mark.asyncio
async def test_list_change_orders_for_project(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"])
    await _create_co(
        tenant_a_client, project_id=project["id"], originating_job_id=job["id"], co_target="new_job"
    )
    await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="existing_job",
    )

    resp = await tenant_a_client.get(f"/api/v1/quotes/change-orders?project_id={project['id']}")
    assert resp.status_code == 200, resp.text
    change_orders = resp.json()
    assert [c["co_number"] for c in change_orders] == [1, 2]  # ordered by CO number
    assert all(c["quote_kind"] == "change_order" for c in change_orders)
    assert all(c["total"] for c in change_orders)  # totals available for the summary


@pytest.mark.asyncio
async def test_change_order_pdf_carries_a_co_header(
    tenant_a_client: AsyncClient, seed_two_tenants: dict, monkeypatch
):
    from app.features.pdf.service import PdfService

    captured: dict = {}

    def _capture_html(html: str) -> bytes:
        captured["html"] = html
        return b"%PDF-1.4 co"

    monkeypatch.setattr(PdfService, "_html_to_pdf", staticmethod(_capture_html))

    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"])
    co = await _create_co(
        tenant_a_client, project_id=project["id"], originating_job_id=job["id"], co_target="new_job"
    )

    pdf = await tenant_a_client.get(f"/api/v1/quotes/{co['id']}/pdf")
    assert pdf.status_code == 200, pdf.text
    assert pdf.headers["content-type"] == "application/pdf"
    # The rendered document is titled as a change order, not a quote.
    assert "CHANGE ORDER" in captured["html"]
    assert f"CO-{co['co_number']}" in captured["html"]


@pytest.mark.asyncio
async def test_change_order_cannot_target_another_tenants_project(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    project = await _create_project(tenant_a_client)
    job = await _create_job(tenant_a_client, project_id=project["id"])

    # Tenant B cannot raise a change order against tenant A's project (RLS hides it).
    resp = await tenant_b_client.post(
        "/api/v1/quotes/",
        json=_co_body(project_id=project["id"], originating_job_id=job["id"], co_target="new_job"),
    )
    assert resp.status_code == 404, resp.text


@pytest.mark.asyncio
async def test_revising_a_change_order_keeps_it_a_change_order(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """A revised CO is still CO-N against the same project and originating job.

    Without the carry-forward, revise produced a plain `standard` quote: the
    client saw "Quote v2" instead of "Change Order CO-1", and re-approving it
    created no job and shifted no schedule.
    """
    user_id = seed_two_tenants["tenant_a_user_id"]
    project = await _create_project(tenant_a_client, target_end_date="2026-12-01")
    job = await _create_job(tenant_a_client, project_id=project["id"])

    co = await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="new_job",
        schedule_days=5,
    )
    approved = await _send_and_approve(tenant_a_client, user_id, co["id"])

    revision = await tenant_a_client.post(
        f"/api/v1/quotes/{approved['id']}/revise", json={"line_items": _CO_LINE_ITEMS}
    )
    assert revision.status_code == 201, revision.text
    revised = revision.json()

    assert revised["quote_kind"] == "change_order"
    assert revised["co_number"] == approved["co_number"]
    assert revised["originating_job_id"] == approved["originating_job_id"]
    assert revised["co_target"] == approved["co_target"]
    assert revised["change_reason"] == approved["change_reason"]
    assert revised["schedule_impact_days"] == approved["schedule_impact_days"]


@pytest.mark.asyncio
async def test_reapproving_a_revised_change_order_adds_the_work_once(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Re-approval amends; it does not re-run the whole change order.

    The first approval creates the job, shifts the schedule and raises the
    budget. Approving a revision of it must add only the difference — running
    the full path again would stand up a second job for the same work and count
    its amount into the budget twice.
    """
    user_id = seed_two_tenants["tenant_a_user_id"]
    finance = _finance_headers(seed_two_tenants["tenant_a_id"])
    project = await _create_project(tenant_a_client, target_end_date="2026-12-01")
    job = await _create_job(tenant_a_client, project_id=project["id"])

    budget = await tenant_a_client.post(
        "/api/v1/budgets/",
        json={"project_id": project["id"], "total": "10000.00"},
        headers=finance,
    )
    assert budget.status_code == 201, budget.text

    co = await _create_co(
        tenant_a_client,
        project_id=project["id"],
        originating_job_id=job["id"],
        co_target="new_job",
        schedule_days=5,
    )
    approved = await _send_and_approve(tenant_a_client, user_id, co["id"])
    jobs_after_first = len((await tenant_a_client.get("/api/v1/jobs/")).json())

    # Same line items, so the revision's own delta is zero on every axis.
    revision = (
        await tenant_a_client.post(
            f"/api/v1/quotes/{approved['id']}/revise", json={"line_items": _CO_LINE_ITEMS}
        )
    ).json()
    await _send_and_approve(tenant_a_client, user_id, revision["id"])

    jobs_after_second = len((await tenant_a_client.get("/api/v1/jobs/")).json())
    assert jobs_after_second == jobs_after_first, "re-approval created a duplicate job"

    financials = (
        await tenant_a_client.get(f"/api/v1/projects/{project['id']}/financials", headers=finance)
    ).json()
    assert Decimal(financials["breakdown"]["budget"]["total"]) == Decimal("10000.00") + _CO_TOTAL

    project_after = (await tenant_a_client.get(f"/api/v1/projects/{project['id']}")).json()
    assert project_after["target_end_date"] == "2026-12-06", "schedule shifted twice"
