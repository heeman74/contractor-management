"""Phase 37 — AI Quote Planning: line-item identity, review state, D-07 send gate.

Covers FINAI-03: line items keep stable `id`s (and `field`) across an ordinary
PATCH, a line's review state is derived server-side rather than trusted from
the client, POST /quotes/{id}/send 409s while any AI-originated line is still
unreviewed, and `confidence_band`/`basis` never reach a caller without
finance.view.

Earlier sections (37-01/04/07) seed an AI-originated line directly via SQL
(the test_phase_36_e2e.py SET LOCAL convention) since no suggestion endpoint
existed yet; the 37-09 section at the bottom drives the real endpoint behind
a mocked Claude client instead.

Per the self-contained-test-file convention the helper set is COPIED rather
than imported across test modules, so a later edit to another phase's fixture
can never silently change what this file asserts.
"""

from __future__ import annotations

import contextlib
import json
from collections.abc import Iterator, Sequence
from datetime import UTC, date, datetime
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest
import structlog
from httpx import AsyncClient
from sqlalchemy import CheckConstraint, event, text

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401
from app.core.database import async_session_factory, engine
from app.core.security import create_access_token
from app.core.tenant import set_current_tenant_id
from app.features.finance.margin_math import RevenueAnchor
from app.features.finance.service import FinanceService, contributing_anchor_cost
from app.features.quotes.models import Quote, QuoteLineItem
from app.features.quotes.quote_history_math import (
    MIN_COMPARABLES_FOR_SUGGESTION,
    summarize_comparables,
)
from app.features.quotes.router import SUGGEST_DENY_DETAIL
from app.features.quotes.service import UNREVIEWED_AI_LINES_DETAIL
from app.features.quotes.suggestion_payload import build_suggestion_payload, jsonb_payload
from app.features.quotes.suggestion_repository import ComparableRows, QuoteComparableRepository
from app.features.quotes.suggestion_service import DROPPED_SUGGESTION_LOG_TEMPLATE
from app.features.quotes.variance_service import QuoteVarianceService
from tests.quote_client_helpers import ensure_client

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
        # Quotes here get sent, and sending requires a client.
        "client_id": await ensure_client(client),
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
        json={
            "title": "Phase 37 project quote",
            "tax_rate": "0",
            # No job to inherit a client from; sending requires one.
            "client_id": await ensure_client(client),
            "line_items": line_items,
        },
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
        json={
            "tax_rate": "0",
            "client_id": await ensure_client(client),
            "line_items": line_items,
        },
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


# ---------------------------------------------------------------------------
# Plan 37-09 — the suggest endpoint: cold-start/trade-unresolved refusals,
# draft-only, the compound permission, and a grounded end-to-end suggestion.
# ---------------------------------------------------------------------------


def _make_mock_anthropic_response(content: dict | str) -> MagicMock:
    """Build a mock Anthropic message response with content[0].text.

    Copied (not imported) from test_phase_26_e2e.py per the self-contained-
    test-file convention this module's docstring states.
    """
    content_text = json.dumps(content) if isinstance(content, dict) else content

    mock_content = MagicMock()
    mock_content.text = content_text

    mock_response = MagicMock()
    mock_response.content = [mock_content]
    return mock_response


def _suggest_url(quote_id: str) -> str:
    return f"{_QUOTES_URL}{quote_id}/suggest-line-items"


def _gc_headers(company_id: str) -> dict:
    """Authorization header for a gc token (neither finance.view nor quotes.edit
    by default)."""
    return {"Authorization": f"Bearer {_token(company_id, ['gc'])}"}


_GRANT_GC_FINANCE_VIEW_SQL = (
    "UPDATE company_role_permissions SET permissions = permissions || "
    "'[\"finance.view\"]'::jsonb WHERE role = 'gc'"
)


async def _grant_gc_finance_view(company_id: str) -> None:
    """Seed finance.view onto the gc role for one tenant — no default role holds
    finance.view without quotes.edit, so this is the only honest fixture for
    the "granted finance access but not quote management" direction."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(_GRANT_GC_FINANCE_VIEW_SQL))
        await session.commit()


@pytest.mark.asyncio
async def test_cold_start_never_calls_claude(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """KEYSTONE 3: a trade below the comparable threshold refuses without ever
    awaiting the Claude client."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client, trade_type="Drywall")
    created = await _create_quote(tenant_a_client, job_id, [])

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock()
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(
            _suggest_url(created["id"]), headers=_pm_headers(company_id)
        )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["refusal_reason"] == "insufficient_history"
    assert body["trade_name"] == "Drywall"
    assert body["comparable_count"] == 0
    assert body["required_count"] == MIN_COMPARABLES_FOR_SUGGESTION
    assert body["suggested_line_count"] == 0
    create.assert_not_awaited()


@pytest.mark.asyncio
async def test_trade_unresolved_never_calls_claude(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """A project-level quote whose lines all carry an empty field refuses
    before ever fetching a comparable or awaiting the Claude client."""
    company_id = seed_two_tenants["tenant_a_id"]
    quote = await _create_project_quote(tenant_a_client, [_line_item()])

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock()
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(
            _suggest_url(quote["id"]), headers=_pm_headers(company_id)
        )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["refusal_reason"] == "trade_unresolved"
    assert body["trade_name"] is None
    assert body["comparable_count"] is None
    assert body["required_count"] is None
    assert body["suggested_line_count"] == 0
    create.assert_not_awaited()


@pytest.mark.asyncio
async def test_suggest_draft_only(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """Suggesting is refused on any quote that is not a draft."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])
    send = await tenant_a_client.post(f"{_QUOTES_URL}{created['id']}/send")
    assert send.status_code == 200, send.text

    resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=_pm_headers(company_id))
    assert resp.status_code == 409, resp.text


@pytest.mark.asyncio
async def test_suggest_requires_both_permissions(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Both halves of D-10's compound permission are enforced independently:
    quotes.edit alone (admin) and finance.view alone (gc, seeded) each 403."""
    company_id = seed_two_tenants["tenant_a_id"]
    job_id = await _create_job(tenant_a_client)
    created = await _create_quote(tenant_a_client, job_id, [_line_item()])

    admin_denied = await tenant_a_client.post(
        _suggest_url(created["id"]), headers=_admin_headers(company_id)
    )
    assert admin_denied.status_code == 403, admin_denied.text
    assert admin_denied.json()["detail"] == SUGGEST_DENY_DETAIL

    await _grant_gc_finance_view(company_id)
    gc_denied = await tenant_a_client.post(
        _suggest_url(created["id"]), headers=_gc_headers(company_id)
    )
    assert gc_denied.status_code == 403, gc_denied.text
    assert gc_denied.json()["detail"] == SUGGEST_DENY_DETAIL


@pytest.mark.asyncio
async def test_suggest_prefills_line_items_from_history(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """A mocked Claude reply whose figures all come from the payload persists
    one AI line, reports a matching suggested_line_count, and the persisted
    basis carries the server-composed sample-count prefix."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    mock_reply = _make_mock_anthropic_response(
        {
            "lines": [
                {
                    "item_type": "labor",
                    "description": "Roofing labor, priced from company history",
                    "quantity": 2,
                    "unit": "hr",
                    "unit_price": 100.00,
                    "basis": "priced consistently with recent roofing jobs",
                }
            ]
        }
    )

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        mock_client.return_value.messages.create = AsyncMock(return_value=mock_reply)
        resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["refusal_reason"] is None
    assert body["trade_name"] == _ROOFING_TRADE
    assert body["comparable_count"] == 3
    assert body["suggested_line_count"] == 1

    rows = await _line_item_rows(company_id, created["id"])
    assert len(rows) == 1
    row = rows[0]
    assert row["ai_origin"] is True
    assert row["review_state"] == "unreviewed"
    assert row["confidence_band"] is not None
    assert row["basis"].startswith(f"median of 3 comparable {_ROOFING_TRADE} scopes")


# ---------------------------------------------------------------------------
# Plan 37-11 Task 1 — Keystones 2 and 2b: an ungrounded structured field and an
# ungrounded basis figure are both blocked, fail-closed, with a retry budget
# of exactly one and a logged drop naming the offender.
#
# Keystone 2 asserts on a STRUCTURED field, not on prose: validate_grounding
# returns ok=True for text with no figures at all, so a basis-only assertion
# can pass for the wrong reason (Pitfall 4 — the same false-green class 36-02
# already recorded).
# ---------------------------------------------------------------------------

_CONCRETE_TRADE = "Concrete"


async def _seed_concrete_comparables(
    client: AsyncClient, headers: dict, company_id: str, *, count: int = 3
) -> None:
    """Same-trade comparables with a FIXED unit_price/quantity/actual-cost
    across every anchor — the resulting payload's allowed sets are exact
    singletons a test can assert precise figures against, no median spread to
    account for. actual-cost 12.00 lands in the payload's MONEY set while the
    trade's own variance percent (not 12) lands in the PERCENT set — the exact
    shape Trap 5's typed-grounding fix exists to keep apart.
    """
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")
    for _ in range(count):
        job_id = await _create_job(client, trade_type=_CONCRETE_TRADE)
        quote = await _create_quote(
            client, job_id, [_line_item(unit_price="100.00", quantity="1.000")]
        )
        await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
        await _create_invoice(client, company_id, job_id=job_id, amount="10.00")
        await _add_cost_entry(
            client, headers, job_id=job_id, category_id=materials_id, amount="12.00"
        )


def _logged_events(logs: Sequence[dict]) -> list[str]:
    """Every rendered log line a block emitted, in order.

    structlog.testing.capture_logs, never the stdlib pytest logging fixture:
    this app binds structlog to the stdlib bridge, which defers %-formatting
    to the handler, so that fixture captures ZERO records from this
    configuration (verified empirically in 36-07) and an assertion built on
    it would pass vacuously.
    """
    return [entry["event"] for entry in logs]


def _grounded_roofing_reply(
    *,
    unit_price: object = 100.00,
    quantity: object = 2,
    basis: str = "priced consistently with recent roofing jobs",
) -> MagicMock:
    """One suggested roofing line, its fields overridable per test — the
    payload from `_seed_roofing_comparables(count=3)` makes 100.00/2 the only
    grounded unit_price/quantity pair."""
    return _make_mock_anthropic_response(
        {
            "lines": [
                {
                    "item_type": "labor",
                    "description": "Roofing labor",
                    "quantity": quantity,
                    "unit": "hr",
                    "unit_price": unit_price,
                    "basis": basis,
                }
            ]
        }
    )


@pytest.mark.asyncio
async def test_ungrounded_line_blocked(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """KEYSTONE 2: a structured unit_price absent from the payload's allowed
    set is blocked and no line is persisted."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock(return_value=_grounded_roofing_reply(unit_price=999.99))
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["refusal_reason"] == "ungrounded"
    assert body["suggested_line_count"] == 0
    assert create.await_count == 2

    rows = await _line_item_rows(company_id, created["id"])
    assert rows == []


@pytest.mark.asyncio
async def test_ungrounded_quantity_blocked(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """The same fail-closed path for a structured quantity outside the closed set."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock(return_value=_grounded_roofing_reply(quantity=999))
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["refusal_reason"] == "ungrounded"
    assert body["suggested_line_count"] == 0
    assert create.await_count == 2

    rows = await _line_item_rows(company_id, created["id"])
    assert rows == []


@pytest.mark.asyncio
async def test_cent_level_price_drift_blocked(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """Structured membership is EXACT: a unit_price one cent off an allowed
    price is blocked — unlike the whole-dollar loosening money PROSE gets from
    validate_typed_grounding, a structured field is a number the model copied,
    never one it formatted for a sentence."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock(return_value=_grounded_roofing_reply(unit_price=100.01))
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    assert resp.json()["refusal_reason"] == "ungrounded"
    assert create.await_count == 2

    rows = await _line_item_rows(company_id, created["id"])
    assert rows == []


@pytest.mark.asyncio
async def test_ungrounded_basis_blocked(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """KEYSTONE 2b: valid structured fields, but a basis dollar figure absent
    from the payload's money set is blocked."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock(
            return_value=_grounded_roofing_reply(basis="priced well above the usual $999.99 job")
        )
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    assert resp.json()["refusal_reason"] == "ungrounded"
    assert create.await_count == 2

    rows = await _line_item_rows(company_id, created["id"])
    assert rows == []


@pytest.mark.asyncio
async def test_percent_cannot_borrow_a_money_value(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Trap 5's fix, proven at the integration level: a payload MONEY value
    (12.00, the actual-cost figure) is not a valid PERCENT citation even
    though it is a valid money one. With the shipped flat collector this
    citation would have passed."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_concrete_comparables(tenant_a_client, headers, company_id)

    job_id = await _create_job(tenant_a_client, trade_type=_CONCRETE_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    reply = _make_mock_anthropic_response(
        {
            "lines": [
                {
                    "item_type": "labor",
                    "description": "Concrete labor, priced from company history",
                    "quantity": 1,
                    "unit": "hr",
                    "unit_price": 100.00,
                    "basis": "past concrete jobs ran 12% under actual",
                }
            ]
        }
    )
    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock(return_value=reply)
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["refusal_reason"] == "ungrounded"
    assert body["suggested_line_count"] == 0
    assert create.await_count == 2

    rows = await _line_item_rows(company_id, created["id"])
    assert rows == []


@pytest.mark.asyncio
async def test_grounding_retry_used_exactly_once(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """The retry budget is exactly one: a persistently ungrounded reply is
    awaited twice, never more, before the whole set drops."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    bad_reply = _grounded_roofing_reply(unit_price=999.99)
    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        create = AsyncMock(side_effect=[bad_reply, bad_reply, bad_reply])
        mock_client.return_value.messages.create = create
        resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    assert resp.json()["refusal_reason"] == "ungrounded"
    assert create.await_count == 2


@pytest.mark.asyncio
async def test_ungrounded_drop_is_logged(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """A dropped suggestion set is logged through a call-site-rendered template
    naming the offending literal — structlog.testing.capture_logs, never the
    stdlib pytest logging fixture, which captures zero records from this app's
    structlog configuration."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        mock_client.return_value.messages.create = AsyncMock(
            return_value=_grounded_roofing_reply(unit_price=999.99)
        )
        with structlog.testing.capture_logs() as logs:
            resp = await tenant_a_client.post(_suggest_url(created["id"]), headers=headers)

    assert resp.status_code == 200, resp.text
    assert resp.json()["refusal_reason"] == "ungrounded"

    expected = DROPPED_SUGGESTION_LOG_TEMPLATE % (UUID(created["id"]), "unit_price")
    assert expected in _logged_events(logs)


# ---------------------------------------------------------------------------
# Plan 37-11 Task 2 — Keystone 4: regeneration preserves reviewed work, and
# the persisted confidence band always comes from code.
#
# A second suggestion run never goes through QuoteService.update_quote's
# id-keyed reconcile — it deletes only server-owned AI rows still unreviewed
# and inserts fresh ones (suggestion_service._persist). Every assertion below
# reads the row's `id` back, not just its content: a deleted-and-recreated
# look-alike is exactly Pitfall 2 / Trap 1's failure mode.
# ---------------------------------------------------------------------------

_FULL_LINE_ITEM_ROWS_SQL = (
    "SELECT id, item_type, description, quantity, unit, unit_price, field, "
    "ai_origin, review_state, confidence_band, basis, sort_order "
    "FROM quote_line_items WHERE quote_id = CAST(:quote_id AS uuid) ORDER BY sort_order"
)


async def _full_line_item_rows(company_id: str, quote_id: str) -> list[dict]:
    """Every column a regeneration test needs to prove byte-identity, id
    included — the only thing separating a preserved row from a deleted-and-
    recreated look-alike."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_FULL_LINE_ITEM_ROWS_SQL), {"quote_id": quote_id})
        return [dict(row._mapping) for row in result]


async def _quote_ai_suggestion_payload(company_id: str, quote_id: str) -> dict | None:
    """The audit-trail JSONB exactly as stored, read through the ORM (the
    shipped `_stored_payload` precedent, test_phase_36_e2e.py) so the JSONB
    column decodes to a plain dict rather than a raw text() query."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        quote = await session.get(Quote, UUID(quote_id))
        assert quote is not None
        return quote.ai_suggestion_payload


def _roofing_line(description: str, **extra: object) -> dict:
    """One grounded roofing line — unit_price/quantity copied verbatim from
    the single rate row `_seed_roofing_comparables(count=3)` produces (median
    unit_price 100.00, median quantity 2.000). Extra keys (e.g. a self-
    reported `confidence`) ride along unread — nothing in the service looks
    at them."""
    return {
        "item_type": "labor",
        "description": description,
        "quantity": 2,
        "unit": "hr",
        "unit_price": 100.00,
        "basis": "priced consistently with recent roofing jobs",
        **extra,
    }


def _patch_item_from(row: dict, *, review_state: str | None = None, **overrides: object) -> dict:
    """One quote_line_items DB row turned into a PATCH-body item, preserving
    every priced field unless overridden — the only way review_state_after
    can resolve to 'edited' or stay unreviewed on purpose, rather than by
    accident."""
    item: dict = {
        "id": str(row["id"]),
        "item_type": row["item_type"],
        "description": row["description"],
        "quantity": str(row["quantity"]),
        "unit": row["unit"],
        "unit_price": str(row["unit_price"]),
        "sort_order": row["sort_order"],
    }
    if row.get("field") is not None:
        item["field"] = row["field"]
    item.update(overrides)
    if review_state is not None:
        item["review_state"] = review_state
    return item


async def _run_suggest(
    client: AsyncClient, headers: dict, quote_id: str, lines: list[dict]
) -> dict:
    """One suggestion run against a mocked Claude reply, returning the response body."""
    reply = _make_mock_anthropic_response({"lines": lines})
    with patch("app.core.ai_utils.get_anthropic_client") as mock_client:
        mock_client.return_value.messages.create = AsyncMock(return_value=reply)
        resp = await client.post(_suggest_url(quote_id), headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_regenerate_preserves_reviewed_lines(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """KEYSTONE 4: a second suggestion run leaves an accepted line and an
    edited line byte-identical, id included, and replaces only the AI line
    that was left unreviewed. A hand-built line is untouched by either run."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    first = await _run_suggest(
        tenant_a_client,
        headers,
        created["id"],
        [
            _roofing_line("First AI line — keep as accepted"),
            _roofing_line("Second AI line — keep as edited"),
            _roofing_line("Third AI line — leave unreviewed"),
        ],
    )
    assert first["suggested_line_count"] == 3

    accept_row, edit_row, untouched_row = await _full_line_item_rows(company_id, created["id"])
    untouched_id = untouched_row["id"]

    hand_built = _line_item("Hand-built line", sort_order=3)
    await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            _patch_item_from(accept_row, review_state="accepted"),
            _patch_item_from(edit_row, unit_price="150.00"),
            _patch_item_from(untouched_row),
            hand_built,
        ],
    )

    before = await _full_line_item_rows(company_id, created["id"])
    accepted_before = next(row for row in before if row["id"] == accept_row["id"])
    edited_before = next(row for row in before if row["id"] == edit_row["id"])
    hand_built_before = next(row for row in before if row["description"] == "Hand-built line")
    assert accepted_before["review_state"] == "accepted"
    assert edited_before["review_state"] == "edited"

    second = await _run_suggest(
        tenant_a_client,
        headers,
        created["id"],
        [_roofing_line("Fresh line from the second run", confidence="high")],
    )
    assert second["suggested_line_count"] == 1

    after = await _full_line_item_rows(company_id, created["id"])
    after_by_id = {row["id"]: row for row in after}

    assert untouched_id not in after_by_id
    assert after_by_id[accept_row["id"]] == accepted_before
    assert after_by_id[edit_row["id"]] == edited_before
    assert after_by_id[hand_built_before["id"]] == hand_built_before

    kept_ids = {accept_row["id"], edit_row["id"], hand_built_before["id"]}
    new_rows = [row for row in after if row["id"] not in kept_ids]
    assert len(new_rows) == 1
    assert new_rows[0]["description"] == "Fresh line from the second run"
    assert new_rows[0]["ai_origin"] is True
    assert new_rows[0]["review_state"] == "unreviewed"


@pytest.mark.asyncio
async def test_regenerate_replaces_untouched_ai_lines(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Every remaining unreviewed AI line is replaced, not just the first —
    D-08's set-wide language, proven at more than one row."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    first = await _run_suggest(
        tenant_a_client,
        headers,
        created["id"],
        [_roofing_line("Untouched A"), _roofing_line("Untouched B")],
    )
    assert first["suggested_line_count"] == 2
    original_ids = {row["id"] for row in await _full_line_item_rows(company_id, created["id"])}

    second = await _run_suggest(
        tenant_a_client,
        headers,
        created["id"],
        [_roofing_line("Fresh A"), _roofing_line("Fresh B"), _roofing_line("Fresh C")],
    )
    assert second["suggested_line_count"] == 3

    after = await _full_line_item_rows(company_id, created["id"])
    assert original_ids.isdisjoint({row["id"] for row in after})
    assert len(after) == 3


@pytest.mark.asyncio
async def test_regenerate_leaves_hand_built_lines_alone(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """A hand-built line — never AI-originated — is untouched by a suggestion
    run: not deleted, not reviewed, not re-ordered away from its content."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(
        tenant_a_client, job_id, [_line_item("Hand-built line", unit_price="75.00")]
    )
    hand_built_before = (await _full_line_item_rows(company_id, created["id"]))[0]

    resp = await _run_suggest(tenant_a_client, headers, created["id"], [_roofing_line("AI line")])
    assert resp["suggested_line_count"] == 1

    after = await _full_line_item_rows(company_id, created["id"])
    hand_built_after = next(row for row in after if row["id"] == hand_built_before["id"])
    assert hand_built_after == hand_built_before
    assert len(after) == 2


@pytest.mark.asyncio
async def test_regenerate_preserves_kept_line_order(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """Kept lines (accepted/edited/hand-built) keep their relative order; a
    second run's fresh lines land after every kept one, never interleaved."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    await _run_suggest(
        tenant_a_client,
        headers,
        created["id"],
        [_roofing_line("Keep first"), _roofing_line("Keep second")],
    )
    keep_first, keep_second = await _full_line_item_rows(company_id, created["id"])

    await _patch_quote(
        tenant_a_client,
        created["id"],
        [
            _patch_item_from(keep_first, review_state="accepted"),
            _patch_item_from(keep_second, review_state="accepted"),
        ],
    )

    await _run_suggest(tenant_a_client, headers, created["id"], [_roofing_line("Fresh")])

    after = await _full_line_item_rows(company_id, created["id"])
    assert [row["id"] for row in after[:2]] == [keep_first["id"], keep_second["id"]]
    assert after[2]["description"] == "Fresh"


@pytest.mark.asyncio
async def test_band_is_code_computed(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """D-05: the persisted confidence_band is always the code-computed one — a
    self-reported band anywhere in the reply is never read back out. Exactly
    the D-09 comparable floor (3) computes LOW on the count axis no matter how
    tight the price agreement is on the spread axis (D-05's worse-of-two-axes
    rule), so this is a stable, deterministic pin regardless of the model's
    own claim."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    resp = await _run_suggest(
        tenant_a_client,
        headers,
        created["id"],
        [_roofing_line("Roofing labor", confidence="high")],
    )
    assert resp["suggested_line_count"] == 1

    rows = await _full_line_item_rows(company_id, created["id"])
    assert len(rows) == 1
    assert rows[0]["confidence_band"] == "low"


@pytest.mark.asyncio
async def test_suggestion_payload_is_stored_for_audit(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """The quote's ai_suggestion_payload holds exactly the payload the LATEST
    run validated its lines against, independently rebuilt from the same
    comparable read."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_roofing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_ROOFING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    resp = await _run_suggest(
        tenant_a_client, headers, created["id"], [_roofing_line("Roofing labor")]
    )
    assert resp["suggested_line_count"] == 1

    rows = await _comparables_for_trade(company_id, _ROOFING_TRADE)
    summary = summarize_comparables(_ROOFING_TRADE, rows.anchors, rows.lines)
    expected_payload = jsonb_payload(build_suggestion_payload(summary).payload)

    stored_payload = await _quote_ai_suggestion_payload(company_id, created["id"])
    assert stored_payload == expected_payload


# ---------------------------------------------------------------------------
# Plan 37-11 Task 3 — D-13 pricing basis and the payload variance leg (FINAI-05)
# ---------------------------------------------------------------------------

_FRAMING_TRADE = "Framing"


async def _seed_framing_comparables(
    client: AsyncClient,
    headers: dict,
    company_id: str,
    *,
    count: int = 3,
    materials_cost: str = "33.00",
) -> None:
    """Same-trade comparables quoted well above their actual cost (100.00
    quoted vs 33.00 actual per anchor) — D-13's 'profitable trade' precondition,
    fixed unit_price/quantity so the resulting payload carries exact figures."""
    await _seed_cost_categories(company_id)
    materials_id = await _category_id(company_id, "materials")
    for _ in range(count):
        job_id = await _create_job(client, trade_type=_FRAMING_TRADE)
        quote = await _create_quote(
            client, job_id, [_line_item(unit_price="100.00", quantity="1.000")]
        )
        await _approve_quote(company_id, quote["id"], approved_at=datetime.now(UTC))
        await _create_invoice(client, company_id, job_id=job_id, amount="10.00")
        await _add_cost_entry(
            client, headers, job_id=job_id, category_id=materials_id, amount=materials_cost
        )


@pytest.mark.asyncio
async def test_pricing_basis_comes_from_quoted_history(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """D-13 as a test: a suggestion prices from the QUOTED rate, not the
    unburdened actual-cost rate. Pricing from actual cost would make every
    suggestion at or below cost — PITFALLS #2 names this defect verbatim."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_framing_comparables(tenant_a_client, headers, company_id, count=3)

    job_id = await _create_job(tenant_a_client, trade_type=_FRAMING_TRADE)
    created = await _create_quote(tenant_a_client, job_id, [])

    rows = await _comparables_for_trade(company_id, _FRAMING_TRADE)
    summary = summarize_comparables(_FRAMING_TRADE, rows.anchors, rows.lines)
    payload = build_suggestion_payload(summary).payload
    quoted_rate = payload["rate_rows"][0]["median_quoted_unit_price"]
    actual_leg = payload["median_actual_total_per_comparable"]
    assert actual_leg < quoted_rate, "fixture must seed a profitable trade"

    resp = await _run_suggest(
        tenant_a_client,
        headers,
        created["id"],
        [
            {
                "item_type": "labor",
                "description": "Framing labor, priced from company history",
                "quantity": 1,
                "unit": "hr",
                "unit_price": float(quoted_rate),
                "basis": "priced consistently with recent framing jobs",
            }
        ],
    )
    assert resp["suggested_line_count"] == 1

    persisted = (await _full_line_item_rows(company_id, created["id"]))[0]
    assert persisted["unit_price"] == quoted_rate
    assert persisted["unit_price"] > actual_leg


@pytest.mark.asyncio
async def test_actual_cost_and_variance_are_separately_named_payload_fields(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
):
    """D-12: the quoted price, the actual cost and the variance percent are
    three distinct payload keys, and none is the arithmetic product of the
    other two — nothing here multiplies, adjusts or blends the two legs."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_framing_comparables(tenant_a_client, headers, company_id, count=3)

    rows = await _comparables_for_trade(company_id, _FRAMING_TRADE)
    summary = summarize_comparables(_FRAMING_TRADE, rows.anchors, rows.lines)
    payload = build_suggestion_payload(summary).payload

    quoted = payload["rate_rows"][0]["median_quoted_unit_price"]
    actual = payload["median_actual_total_per_comparable"]
    variance = payload["quoted_vs_actual_variance_percent"]

    # Pinned to the seeded fixture (100.00 quoted, 33.00 actual, 3 anchors) so
    # the "no field is a product of two others" claim is checked on real
    # values, not merely asserted in prose.
    assert quoted == Decimal("100.00")
    assert actual == Decimal("33.00")
    assert variance == Decimal("-67.0")
    assert quoted != actual
    assert quoted != variance
    assert actual != variance
    assert quoted != actual * variance
    assert actual != quoted * variance
    assert variance != quoted * actual


@pytest.mark.asyncio
async def test_variance_in_payload(tenant_a_client: AsyncClient, seed_two_tenants: dict):
    """FINAI-05: the trade's quoted-vs-actual variance percent rides into the
    payload as a named field, inside the AllowedFigures.percents set, so the
    AI may state it in the basis (D-12)."""
    company_id = seed_two_tenants["tenant_a_id"]
    headers = _pm_headers(company_id)
    await _seed_framing_comparables(tenant_a_client, headers, company_id, count=3)

    rows = await _comparables_for_trade(company_id, _FRAMING_TRADE)
    summary = summarize_comparables(_FRAMING_TRADE, rows.anchors, rows.lines)
    result = build_suggestion_payload(summary)

    variance = result.payload["quoted_vs_actual_variance_percent"]
    assert variance is not None
    assert variance in result.allowed_figures.percents
