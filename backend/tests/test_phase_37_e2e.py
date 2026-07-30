"""Phase 37 — AI Quote Planning: line-item identity, review state, D-07 send gate.

Covers FINAI-03: line items keep stable `id`s (and `field`) across an ordinary
PATCH, a line's review state is derived server-side rather than trusted from
the client, POST /quotes/{id}/send 409s while any AI-originated line is still
unreviewed, and `confidence_band`/`basis` never reach a caller without
finance.view.

No suggestion endpoint exists yet in this plan, so an AI-originated line is
seeded directly via SQL (the test_phase_36_e2e.py SET LOCAL convention) rather
than through a real suggestion run.

Per the self-contained-test-file convention the helper set is COPIED rather
than imported across test modules, so a later edit to another phase's fixture
can never silently change what this file asserts.
"""

from __future__ import annotations

import contextlib
from collections.abc import Iterator
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import CheckConstraint, event, text

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401
from app.core.database import async_session_factory, engine
from app.core.security import create_access_token
from app.core.tenant import set_current_tenant_id
from app.features.finance.margin_math import RevenueAnchor
from app.features.finance.service import FinanceService, contributing_anchor_cost
from app.features.quotes.models import QuoteLineItem
from app.features.quotes.service import UNREVIEWED_AI_LINES_DETAIL
from app.features.quotes.suggestion_repository import ComparableRows, QuoteComparableRepository
from app.features.quotes.variance_service import QuoteVarianceService

_QUOTES_URL = "/api/v1/quotes/"
_PROJECTS_URL = "/api/v1/projects/"
_TRADE_SCOPES_URL = "/api/v1/trade-scopes/"
_COST_ENTRIES_URL = "/api/v1/cost-entries/"
_INVOICES_URL = "/api/v1/invoices/"
_MISSING_VIEW_PERMISSION = "Missing permission: finance.view"

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
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

_MARK_AI_ORIGIN_SQL = (
    "UPDATE quote_line_items SET ai_origin = true, review_state = 'unreviewed', "
    "confidence_band = 'high', basis = :basis WHERE id = CAST(:id AS uuid)"
)

_LINE_ITEM_ROWS_SQL = (
    "SELECT ai_origin, review_state, confidence_band, basis FROM quote_line_items "
    "WHERE quote_id = CAST(:quote_id AS uuid) ORDER BY sort_order"
)


def _line_item(
    description: str = "Test work",
    quantity: str = "1.000",
    unit_price: str = "100.00",
    sort_order: int = 0,
    item_id: str | None = None,
) -> dict:
    """A minimal labor line item body for POST/PATCH /quotes."""
    item: dict = {
        "item_type": "labor",
        "description": description,
        "quantity": quantity,
        "unit": "hr",
        "unit_price": unit_price,
        "sort_order": sort_order,
    }
    if item_id is not None:
        item["id"] = item_id
    return item


async def _create_job(
    client: AsyncClient,
    *,
    project_id: str | None = None,
    trade_type: str = "electrical",
) -> str:
    """Create a minimal job in 'quote' status, optionally linked to a project."""
    payload: dict = {
        "description": "Phase 37 E2E Test Job",
        "trade_type": trade_type,
        "priority": "medium",
    }
    if project_id is not None:
        payload["project_id"] = project_id
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, f"Job creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_quote(client: AsyncClient, job_id: str, line_items: list[dict]) -> dict:
    """Create a draft quote for the given job with the given line items."""
    resp = await client.post(
        _QUOTES_URL,
        json={"job_id": job_id, "tax_rate": "0", "line_items": line_items},
    )
    assert resp.status_code == 201, f"Quote creation failed: {resp.text}"
    return resp.json()


async def _patch_quote(client: AsyncClient, quote_id: str, line_items: list[dict]) -> dict:
    """PATCH a draft quote's line items."""
    resp = await client.patch(f"{_QUOTES_URL}{quote_id}", json={"line_items": line_items})
    assert resp.status_code == 200, f"PATCH failed: {resp.text}"
    return resp.json()


async def _get_quote(client: AsyncClient, quote_id: str) -> dict:
    resp = await client.get(f"{_QUOTES_URL}{quote_id}")
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _create_project_quote(client: AsyncClient, line_items: list[dict]) -> dict:
    """Create a project-level draft quote (no job_id, no trade_scope_id)."""
    resp = await client.post(
        _QUOTES_URL,
        json={"title": "Phase 37 project quote", "tax_rate": "0", "line_items": line_items},
    )
    assert resp.status_code == 201, f"Quote creation failed: {resp.text}"
    return resp.json()


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
            text(
                "SELECT id FROM cost_categories "
                "WHERE company_id = CAST(:company_id AS uuid) AND name = :name"
            ),
            {"company_id": company_id, "name": name},
        )
        return str(result.scalar_one())


async def _create_project(client: AsyncClient, name: str = "Phase 37 Variance Project") -> str:
    """Create a project through the API and return its id."""
    resp = await client.post(_PROJECTS_URL, json={"name": name})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_trade_scope(client: AsyncClient, project_id: str, trade_name: str) -> str:
    """Create a trade scope on a project through the API and return its id."""
    resp = await client.post(
        _TRADE_SCOPES_URL,
        json={"project_id": project_id, "trade_name": trade_name, "trade_color": "#2196F3"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _add_cost_entry(
    client: AsyncClient,
    headers: dict,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    category_id: str,
    amount: str,
    incurred_date: date = date(2026, 6, 1),
) -> str:
    """Create a cost entry through the API at one anchor and return its id."""
    payload: dict = {
        "category_id": category_id,
        "amount": amount,
        "incurred_date": incurred_date.isoformat(),
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    resp = await client.post(_COST_ENTRIES_URL, headers=headers, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _mark_job_complete(company_id: str, job_id: str) -> None:
    """Force a job to 'complete' via SQL so a manual invoice can be posted on it."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_JOB_COMPLETE_SQL), {"job_id": job_id})
        await session.commit()


def _material_line_item(amount: str) -> dict:
    """One material line item — the only shape these revenue fixtures need."""
    return {
        "item_type": "material",
        "description": "Phase 37 revenue item",
        "quantity": "1.000",
        "unit": "each",
        "unit_price": amount,
    }


async def _create_invoice(
    client: AsyncClient,
    company_id: str,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    amount: str = "1.00",
    issued_at: datetime | None = None,
) -> str:
    """Create an invoice at one anchor — its EXISTENCE is the D-02 comparable gate.

    Job-anchored invoices require a 'complete' job (shipped generate_manual rule).
    """
    if job_id is not None:
        await _mark_job_complete(company_id, job_id)
    payload: dict = {
        "issued_at": (issued_at or datetime.now(UTC)).isoformat(),
        "line_items": [_material_line_item(amount)],
    }
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    resp = await client.post(_INVOICES_URL, json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_quote_for_scope(
    client: AsyncClient, trade_scope_id: str, line_items: list[dict]
) -> dict:
    """Create a draft quote scoped to a trade scope through the API."""
    resp = await client.post(
        f"/api/v1/trade-scopes/{trade_scope_id}/quotes",
        json={"tax_rate": "0", "line_items": line_items},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _approve_quote(
    company_id: str,
    quote_id: str,
    *,
    approved_at: datetime | None,
    project_id: str | None = None,
) -> None:
    """Force a quote to approved via SQL — the 33-02 precedent (see module docstring)."""
    statement = _QUOTE_APPROVE_SQL if project_id is None else _QUOTE_APPROVE_WITH_PROJECT_SQL
    params: dict = {"quote_id": quote_id, "approved_at": approved_at}
    if project_id is not None:
        params["project_id"] = project_id
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(statement), params)
        await session.commit()


async def _quote_variance(company_id: str, quote_id: str):
    """Call QuoteVarianceService.quote_variance directly (no endpoint exists yet in Task 2)."""
    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        return await QuoteVarianceService(db).quote_variance(UUID(quote_id))


async def _mark_ai_origin(
    company_id: str, line_item_id: str, basis: str = "Priced from last 90 days of company history"
) -> None:
    """Seed AI provenance directly — no suggestion endpoint exists yet in this plan.

    Copies the test_phase_36_e2e.py SET LOCAL convention: PostgreSQL rejects a
    parameterized SET LOCAL, so the company id is inlined as an f-string.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_MARK_AI_ORIGIN_SQL), {"id": line_item_id, "basis": basis})
        await session.commit()


async def _line_item_rows(company_id: str, quote_id: str) -> list[dict]:
    """Read a quote's line items directly off the DB, bypassing the finance scrub.

    Used to prove the revision copy actually persisted AI provenance columns —
    the API response for a non-finance-view caller would null them out.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_LINE_ITEM_ROWS_SQL), {"quote_id": quote_id})
        return [dict(row._mapping) for row in result]


def test_quote_line_review_columns_exist_with_checks():
    """The five line-item columns carry the three named CHECK constraints.

    Reads the CHECK constraint expressions directly off the ORM table so a
    later edit that drops or renames one fails this test, not just a manual
    inspection.
    """
    checks = {
        constraint.name: str(constraint.sqltext)
        for constraint in QuoteLineItem.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }

    assert "quote_line_items_review_state_check" in checks
    assert "quote_line_items_confidence_band_check" in checks
    assert "quote_line_items_basis_length_check" in checks
    assert "200" in checks["quote_line_items_basis_length_check"]


# ---------------------------------------------------------------------------
# Plan 37-04 Task 1 — anchor_cost_context equivalence guards
#
# The only thing that keeps a second definition of spend from being introduced
# by a later edit: anchor_cost_context's batched per-anchor cost must equal
# every shipped spend definition it composes rather than restates.
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_anchor_cost_context_matches_project_rollup(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id, "Plumbing")
    job_id = await _create_job(tenant_a_client, project_id=project_id, trade_type="Electrical")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=job_id, category_id=materials_id, amount="220.00"
    )
    await _add_cost_entry(
        tenant_a_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="90.00"
    )

    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        service = FinanceService(db)
        context = await service.anchor_cost_context(UUID(project_id))
        rollup = await service.rollup_for_project(UUID(project_id))

    assert context.grand_total == rollup.grand_total


@pytest.mark.asyncio
async def test_anchor_cost_context_matches_job_cost_breakdown(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    job_id = await _create_job(tenant_a_client, project_id=project_id, trade_type="Electrical")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=job_id, category_id=materials_id, amount="340.00"
    )

    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        service = FinanceService(db)
        context = await service.anchor_cost_context(UUID(project_id))
        anchor_cost = contributing_anchor_cost(RevenueAnchor(job_id=UUID(job_id)), context)
        breakdown = await service.job_cost_breakdown(UUID(job_id))

    assert anchor_cost == breakdown.grand_total


@pytest.mark.asyncio
async def test_anchor_cost_context_matches_trade_scope_spend(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id, "Plumbing")
    await _add_cost_entry(
        tenant_a_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="175.00"
    )

    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        service = FinanceService(db)
        context = await service.anchor_cost_context(UUID(project_id))
        anchor_cost = contributing_anchor_cost(
            RevenueAnchor(trade_scope_id=UUID(scope_id)), context
        )
        spend = await service.trade_scope_spend(UUID(scope_id))

    assert anchor_cost == spend


# ---------------------------------------------------------------------------
# Task 2 — id-keyed reconcile and server-side edited derivation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_line_item_ids_stable_across_patch(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(
        tenant_a_client,
        job_id,
        [_line_item("First item", sort_order=0), _line_item("Second item", sort_order=1)],
    )
    first_id, second_id = (item["id"] for item in created["line_items"])

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            _line_item("First item — revised", sort_order=0, item_id=first_id),
            _line_item("Second item", sort_order=1, item_id=second_id),
        ],
    )

    by_id = {item["id"]: item for item in patched["line_items"]}
    assert set(by_id) == {first_id, second_id}
    assert by_id[first_id]["description"] == "First item — revised"
    assert by_id[second_id]["description"] == "Second item"


@pytest.mark.asyncio
async def test_line_item_field_survives_patch(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])
    item_id = created["line_items"][0]["id"]

    line_item = _line_item("Wired item", item_id=item_id)
    line_item["field"] = "Electrical"
    patched = await _patch_quote(tenant_a_client, created["id"], [line_item])
    assert patched["line_items"][0]["field"] == "Electrical"

    fetched = await _get_quote(tenant_a_client, created["id"])
    assert fetched["line_items"][0]["field"] == "Electrical"


@pytest.mark.asyncio
async def test_line_item_without_id_is_inserted_and_absent_is_deleted(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(
        tenant_a_client,
        job_id,
        [_line_item("Keep me", sort_order=0), _line_item("Drop me", sort_order=1)],
    )
    keep_id = created["line_items"][0]["id"]

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            _line_item("Keep me", sort_order=0, item_id=keep_id),
            _line_item("Brand new", sort_order=1),
        ],
    )

    descriptions = {item["description"] for item in patched["line_items"]}
    assert descriptions == {"Keep me", "Brand new"}
    ids = {item["id"] for item in patched["line_items"]}
    assert keep_id in ids
    assert len(ids) == 2


@pytest.mark.asyncio
async def test_edited_ai_line_is_marked_edited_server_side(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            {
                **_line_item(unit_price="65.00", item_id=item_id),
                "review_state": "unreviewed",
            }
        ],
    )

    line = patched["line_items"][0]
    assert line["ai_origin"] is True
    assert line["review_state"] == "edited"


@pytest.mark.asyncio
async def test_accepted_ai_line_records_acceptance(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            {
                **_line_item(unit_price="50.00", item_id=item_id),
                "review_state": "accepted",
            }
        ],
    )

    line = patched["line_items"][0]
    assert line["ai_origin"] is True
    assert line["review_state"] == "accepted"


@pytest.mark.asyncio
async def test_non_ai_line_cannot_claim_review_state(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]

    patched = await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            {
                **_line_item(unit_price="50.00", item_id=item_id),
                "review_state": "accepted",
            }
        ],
    )

    line = patched["line_items"][0]
    assert line["ai_origin"] is False
    assert line["review_state"] == "unreviewed"


# ---------------------------------------------------------------------------
# Task 3 — D-07 send gate, revision provenance, finance scrub
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_send_blocked_by_unreviewed_ai_line(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """KEYSTONE 1: an unreviewed AI line 409s the send, and the quote stays draft."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 409, send.text
    assert send.json()["detail"] == UNREVIEWED_AI_LINES_DETAIL

    fetched = await _get_quote(tenant_a_client, created["id"])
    assert fetched["status"] == "draft"


@pytest.mark.asyncio
async def test_send_succeeds_after_every_ai_line_reviewed(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id)

    await _patch_quote(
        tenant_a_client,
        created["id"],
        [{**_line_item(unit_price="50.00", item_id=item_id), "review_state": "accepted"}],
    )

    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 200, send.text
    assert send.json()["status"] == "sent"


@pytest.mark.asyncio
async def test_send_unchanged_for_hand_built_quote(tenant_a_client: AsyncClient):
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])
    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 200, send.text
    assert send.json()["status"] == "sent"

    project_quote = await _create_project_quote(tenant_a_client, [_line_item()])
    send_project = await tenant_a_client.post(f"{_QUOTES_URL}{project_quote['id']}/send")
    assert send_project.status_code == 200, send_project.text
    assert send_project.json()["status"] == "sent"
    assert send_project.json()["job_id"] is None


@pytest.mark.asyncio
async def test_revision_copies_ai_provenance_and_resets_review_state(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="50.00")])
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id, basis="Priced from company history")

    await _patch_quote(
        tenant_a_client,
        created["id"],
        [{**_line_item(unit_price="50.00", item_id=item_id), "review_state": "accepted"}],
    )
    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 200, send.text

    revise = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/revise", json={})
    assert revise.status_code == 201, revise.text

    # Read the new revision's line item off the DB directly — the admin caller
    # in this test has no finance.view, so the API response itself nulls
    # confidence_band/basis (that scrub is proven separately, below).
    rows = await _line_item_rows(company_id, revise.json()["id"])
    assert len(rows) == 1
    new_row = rows[0]
    assert new_row["ai_origin"] is True
    assert new_row["confidence_band"] == "high"
    assert new_row["basis"] == "Priced from company history"
    assert new_row["review_state"] == "unreviewed"


@pytest.mark.asyncio
async def test_line_item_finance_fields_withheld_without_finance_view(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """An admin token holds quotes.view but not finance.view (Phase 30 exclusion)."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(
        tenant_a_client, job_id, [_line_item(description="Wired panel", unit_price="50.00")]
    )
    item_id = created["line_items"][0]["id"]
    await _mark_ai_origin(company_id, item_id, basis="Priced from company history")

    fetched = await _get_quote(tenant_a_client, created["id"])
    line = fetched["line_items"][0]
    assert line["confidence_band"] is None
    assert line["basis"] is None
    assert line["description"] == "Wired panel"
    assert line["unit_price"] == "50.00"


# ---------------------------------------------------------------------------
# Plan 37-04 Task 2 — QuoteVarianceService (one quote's quoted-vs-actual, D-14)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_quote_variance_job_anchored(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    job_id = await _create_job(tenant_a_client)
    quote = await _create_quote(
        tenant_a_client, job_id, [_line_item(quantity="2.000", unit_price="100.00")]
    )
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, job_id=job_id, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=job_id, category_id=materials_id, amount="250.00"
    )

    result = await _quote_variance(company_id, quote["id"])

    assert result.quoted == Decimal("200.00")
    assert result.actual == Decimal("250.00")
    assert result.variance == Decimal("50.00")
    assert result.labor_included is False
    assert result.scope_anchored is False
    assert result.trades == []


@pytest.mark.asyncio
async def test_quote_variance_scope_anchored_excludes_labor(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id, "Plumbing")
    quote = await _create_quote_for_scope(
        tenant_a_client, scope_id, [_line_item(quantity="1.000", unit_price="300.00")]
    )
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, trade_scope_id=scope_id, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="280.00"
    )

    result = await _quote_variance(company_id, quote["id"])

    assert result.quoted == Decimal("300.00")
    assert result.actual == Decimal("280.00")
    assert result.variance == Decimal("-20.00")
    assert result.labor_included is False
    assert result.scope_anchored is True
    assert result.trades == []


@pytest.mark.asyncio
async def test_quote_variance_null_without_invoice(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    quote = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="100.00")])
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))

    result = await _quote_variance(company_id, quote["id"])

    assert result.quoted is None
    assert result.actual is None
    assert result.variance is None
    assert result.variance_percent is None
    assert result.trades == []


@pytest.mark.asyncio
async def test_project_quote_variance_groups_by_field(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """D-14: one trades entry per field, matched to the job `_convert_project_quote` created."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    electrical_job = await _create_job(
        tenant_a_client, project_id=project_id, trade_type="Electrical"
    )
    plumbing_job = await _create_job(tenant_a_client, project_id=project_id, trade_type="Plumbing")

    electrical_item = _line_item(quantity="2.000", unit_price="100.00")
    electrical_item["field"] = "Electrical"
    plumbing_item = _line_item(quantity="3.000", unit_price="50.00")
    plumbing_item["field"] = "Plumbing"
    quote = await _create_project_quote(tenant_a_client, [electrical_item, plumbing_item])
    await _approve_quote(
        company_id, quote["id"], approved_at=datetime.now(UTC), project_id=project_id
    )

    await _create_invoice(tenant_a_client, company_id, job_id=electrical_job, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=electrical_job, category_id=materials_id, amount="220.00"
    )
    await _create_invoice(tenant_a_client, company_id, job_id=plumbing_job, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=plumbing_job, category_id=materials_id, amount="140.00"
    )

    result = await _quote_variance(company_id, quote["id"])

    by_label = {trade.label: trade for trade in result.trades}
    assert set(by_label) == {"Electrical", "Plumbing"}
    assert by_label["Electrical"].quoted == Decimal("200.00")
    assert by_label["Electrical"].actual == Decimal("220.00")
    assert by_label["Electrical"].variance == Decimal("20.00")
    assert by_label["Plumbing"].quoted == Decimal("150.00")
    assert by_label["Plumbing"].actual == Decimal("140.00")
    assert by_label["Plumbing"].variance == Decimal("-10.00")


@pytest.mark.asyncio
async def test_project_quote_variance_uninvoiced_group_reports_null(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    electrical_job = await _create_job(
        tenant_a_client, project_id=project_id, trade_type="Electrical"
    )
    plumbing_job = await _create_job(tenant_a_client, project_id=project_id, trade_type="Plumbing")

    electrical_item = _line_item(quantity="2.000", unit_price="100.00")
    electrical_item["field"] = "Electrical"
    plumbing_item = _line_item(quantity="3.000", unit_price="50.00")
    plumbing_item["field"] = "Plumbing"
    quote = await _create_project_quote(tenant_a_client, [electrical_item, plumbing_item])
    await _approve_quote(
        company_id, quote["id"], approved_at=datetime.now(UTC), project_id=project_id
    )

    # Only the electrical job gets an invoice; plumbing has cost but no invoice.
    await _create_invoice(tenant_a_client, company_id, job_id=electrical_job, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=electrical_job, category_id=materials_id, amount="220.00"
    )
    await _add_cost_entry(
        tenant_a_client, headers, job_id=plumbing_job, category_id=materials_id, amount="140.00"
    )

    result = await _quote_variance(company_id, quote["id"])

    by_label = {trade.label: trade for trade in result.trades}
    assert by_label["Electrical"].actual == Decimal("220.00")
    assert by_label["Plumbing"].quoted == Decimal("150.00")
    assert by_label["Plumbing"].actual is None
    assert by_label["Plumbing"].variance is None
    assert by_label["Plumbing"].variance_percent is None
    # Not every group is comparable, so the project-level top total is honest, not partial.
    assert result.actual is None
    assert result.variance is None


@pytest.mark.asyncio
async def test_project_quote_variance_quoted_legs_sum_to_pre_tax_total(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]

    first = _line_item(quantity="1.000", unit_price="33.33")
    first["field"] = "Electrical"
    second = _line_item(quantity="1.000", unit_price="33.33")
    second["field"] = "Plumbing"
    third = _line_item(quantity="1.000", unit_price="33.34")
    third["field"] = "Carpentry"
    quote = await _create_project_quote(tenant_a_client, [first, second, third])
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))

    result = await _quote_variance(company_id, quote["id"])

    assert sum((trade.quoted for trade in result.trades), Decimal("0")) == Decimal("100.00")
    assert result.quoted == Decimal("100.00")


# ---------------------------------------------------------------------------
# Plan 37-04 Task 3 — the two variance endpoints, finance-gated
# ---------------------------------------------------------------------------


def _quote_variance_url(quote_id: str) -> str:
    return f"{_QUOTES_URL}{quote_id}/variance"


def _project_quote_variance_url(project_id: str) -> str:
    return f"{_PROJECTS_URL}{project_id}/financials/quote-variance"


@pytest.mark.asyncio
async def test_quote_variance_requires_finance_view(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    quote = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="100.00")])
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, job_id=job_id, amount="10.00")

    denied = await tenant_a_client.get(
        _quote_variance_url(quote["id"]), headers=_admin_headers(company_id)
    )
    assert denied.status_code == 403, denied.text
    assert denied.json()["detail"] == _MISSING_VIEW_PERMISSION

    allowed = await tenant_a_client.get(
        _quote_variance_url(quote["id"]), headers=_pm_headers(company_id)
    )
    assert allowed.status_code == 200, allowed.text
    body = allowed.json()
    assert body["quoted"] == "100.00"
    assert body["scope_anchored"] is False
    assert body["trades"] == []


@pytest.mark.asyncio
async def test_project_quote_variance_requires_finance_view(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    denied = await tenant_a_client.get(
        _project_quote_variance_url(project_id), headers=_admin_headers(company_id)
    )
    assert denied.status_code == 403, denied.text
    assert denied.json()["detail"] == _MISSING_VIEW_PERMISSION

    allowed = await tenant_a_client.get(
        _project_quote_variance_url(project_id), headers=_pm_headers(company_id)
    )
    assert allowed.status_code == 200, allowed.text


@pytest.mark.asyncio
async def test_project_quote_variance_lists_invoiced_anchors_with_total(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    job_id = await _create_job(tenant_a_client, project_id=project_id, trade_type="Electrical")
    scope_id = await _create_trade_scope(tenant_a_client, project_id, "Plumbing")

    job_quote = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="200.00")])
    await _approve_quote(company_id, job_quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, job_id=job_id, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=job_id, category_id=materials_id, amount="220.00"
    )

    scope_quote = await _create_quote_for_scope(
        tenant_a_client, scope_id, [_line_item(unit_price="300.00")]
    )
    await _approve_quote(company_id, scope_quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, trade_scope_id=scope_id, amount="10.00")
    await _add_cost_entry(
        tenant_a_client,
        headers,
        trade_scope_id=scope_id,
        category_id=materials_id,
        amount="280.00",
    )

    resp = await tenant_a_client.get(_project_quote_variance_url(project_id), headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()

    by_label = {row["label"]: row for row in body["scopes"]}
    assert set(by_label) == {"Electrical", "Plumbing"}
    assert by_label["Electrical"]["quoted"] == "200.00"
    assert by_label["Electrical"]["actual"] == "220.00"
    assert by_label["Plumbing"]["quoted"] == "300.00"
    assert by_label["Plumbing"]["actual"] == "280.00"
    assert body["total"]["label"] == "Project total"
    assert body["total"]["quoted"] == "500.00"
    assert body["total"]["actual"] == "500.00"
    assert body["total"]["variance"] == "0.00"
    assert body["has_scope_anchored_rows"] is True


@pytest.mark.asyncio
async def test_project_quote_variance_empty_without_invoiced_anchor(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    resp = await tenant_a_client.get(
        _project_quote_variance_url(project_id), headers=_pm_headers(company_id)
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["scopes"] == []
    assert body["total"]["quoted"] is None
    assert body["total"]["actual"] is None
    assert body["labor_included"] is False
    assert body["has_scope_anchored_rows"] is False


@pytest.mark.asyncio
async def test_project_quote_variance_is_tenant_isolated(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    tenant_b_id = seed_two_tenants["tenant_b_id"]
    project_id = await _create_project(tenant_a_client)

    resp = await tenant_b_client.get(
        _project_quote_variance_url(project_id), headers=_pm_headers(tenant_b_id)
    )
    assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# Plan 37-07 Task 1 — QuoteComparableRepository: bounded, same-trade comparables
# ---------------------------------------------------------------------------

_ROOFING_TRADE = "Roofing"


@contextlib.contextmanager
def _count_sql_statements() -> Iterator[list[str]]:
    """Record every SQL statement issued while the block runs (35-08 recipe).

    Listens on engine.sync_engine because SQLAlchemy's event API is synchronous
    by design (same reason app/core/tenant.py's after_begin listener is sync).
    """
    statements: list[str] = []

    def _record(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement)

    event.listen(engine.sync_engine, "before_cursor_execute", _record)
    try:
        yield statements
    finally:
        event.remove(engine.sync_engine, "before_cursor_execute", _record)


async def _seed_roofing_comparable(
    client: AsyncClient, headers: dict, company_id: str, materials_id: str, *, index: int
) -> None:
    """One same-trade, invoiced, costed anchor — a comparable for _ROOFING_TRADE."""
    job_id = await _create_job(client, trade_type=_ROOFING_TRADE)
    quote = await _create_quote(
        client, job_id, [_line_item(unit_price="100.00", quantity=f"{index + 1}.000")]
    )
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(client, company_id, job_id=job_id, amount="10.00")
    await _add_cost_entry(client, headers, job_id=job_id, category_id=materials_id, amount="220.00")


async def _seed_roofing_comparables(
    client: AsyncClient, headers: dict, company_id: str, count: int
) -> None:
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")
    for index in range(count):
        await _seed_roofing_comparable(client, headers, company_id, materials_id, index=index)


async def _comparables_for_trade(company_id: str, trade: str) -> ComparableRows:
    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        return await QuoteComparableRepository(db).comparables_for_trade(trade)


async def _statements_for_comparables(company_id: str, trade: str) -> list[str]:
    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        repository = QuoteComparableRepository(db)
        with _count_sql_statements() as statements:
            await repository.comparables_for_trade(trade)
    return statements


@pytest.mark.asyncio
async def test_comparable_query_count_constant(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
):
    """The repository's round-trip count does not grow with comparable count —
    the invariance is the contract; the absolute is whatever this run measures."""
    small_company_id = seed_two_tenants["tenant_a_id"]
    large_company_id = seed_two_tenants["tenant_b_id"]

    await _seed_roofing_comparables(
        tenant_a_client, _pm_headers(small_company_id), small_company_id, count=3
    )
    await _seed_roofing_comparables(
        tenant_b_client, _pm_headers(large_company_id), large_company_id, count=12
    )

    small_statements = await _statements_for_comparables(small_company_id, _ROOFING_TRADE)
    large_statements = await _statements_for_comparables(large_company_id, _ROOFING_TRADE)

    assert len(large_statements) == len(small_statements), (
        f"comparable query issued {len(large_statements) - len(small_statements)} more "
        "statements at 12 comparables than at 3 — a per-comparable query has crept in"
    )


@pytest.mark.asyncio
async def test_comparable_cost_equivalence(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """A comparable's actual cost is pinned equal to the shipped contributing_anchor_cost."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    project_id = await _create_project(tenant_a_client)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    job_id = await _create_job(tenant_a_client, project_id=project_id, trade_type=_ROOFING_TRADE)
    quote = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="100.00")])
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, job_id=job_id, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, job_id=job_id, category_id=materials_id, amount="340.00"
    )

    rows = await _comparables_for_trade(company_id, _ROOFING_TRADE)
    assert len(rows.anchors) == 1

    async with async_session_factory() as db:
        set_current_tenant_id(UUID(company_id))
        context = await FinanceService(db).anchor_cost_context(UUID(project_id))
        expected = contributing_anchor_cost(RevenueAnchor(job_id=UUID(job_id)), context)

    assert rows.anchors[0].actual_cost == expected


@pytest.mark.asyncio
async def test_zero_cost_anchor_excluded(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """PITFALLS #9: an invoiced anchor with zero recorded cost is not a comparable."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    quote = await _create_quote(tenant_a_client, job_id, [_line_item(unit_price="100.00")])
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, job_id=job_id, amount="10.00")
    # No cost entry recorded for this anchor.

    rows = await _comparables_for_trade(company_id, _ROOFING_TRADE)

    assert rows.anchors == ()


@pytest.mark.asyncio
async def test_uninvoiced_anchor_excluded(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """An anchor with cost but no invoice is not "completed", per D-02."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    await _add_cost_entry(
        tenant_a_client, headers, job_id=job_id, category_id=materials_id, amount="220.00"
    )
    # No invoice ever issued for this anchor.

    rows = await _comparables_for_trade(company_id, _ROOFING_TRADE)

    assert rows.anchors == ()


@pytest.mark.asyncio
async def test_scope_anchor_contributes_no_labor(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Trap 6: a trade-scope anchor structurally carries no labor cost."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")

    project_id = await _create_project(tenant_a_client)
    scope_id = await _create_trade_scope(tenant_a_client, project_id, _ROOFING_TRADE)
    quote = await _create_quote_for_scope(
        tenant_a_client, scope_id, [_line_item(unit_price="100.00")]
    )
    await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
    await _create_invoice(tenant_a_client, company_id, trade_scope_id=scope_id, amount="10.00")
    await _add_cost_entry(
        tenant_a_client, headers, trade_scope_id=scope_id, category_id=materials_id, amount="280.00"
    )

    rows = await _comparables_for_trade(company_id, _ROOFING_TRADE)

    assert len(rows.anchors) == 1
    assert rows.anchors[0].is_job_anchored is False
    assert rows.anchors[0].labor_cost == Decimal("0")
