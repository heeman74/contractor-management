"""Phase 36 — AI Profitability Analysis.

Covers FINAI-01/FINAI-02: the findings persistence floor (idempotent nightly
upsert, claim-first alerting, resolve-then-recur lifecycle) and the schema
contracts that guard it (the ai_profitability alert type, tenant isolation, and
the DB half of the UI-SPEC text-length contract).

Per the self-contained-test-file convention the helper set is COPIED from
test_phase_35_e2e.py (and _make_mock_anthropic_response from
test_phase_26_e2e.py) rather than imported across test modules, so a later
edit to a Phase 35 fixture can never silently change what Phase 36 asserts.

Repository-level tests drive ProfitabilityRepository inside
async_session_factory() with the SET LOCAL f-string pattern (PostgreSQL rejects
a parameterized SET LOCAL) and commit in the test — the scheduler-path
convention, where the repository never commits and its caller does.
"""

import contextlib
import json
from collections.abc import AsyncIterator
from datetime import date, datetime
from unittest.mock import MagicMock
from uuid import UUID, uuid4

from app.features.finance.profitability_repository import FindingUpsert, ProfitabilityRepository
from httpx import AsyncClient
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.security import create_access_token
from app.features.finance.models import CostCategory

_SECONDS_PER_HOUR = 3600

# Phase 36 endpoint URLs. The finding endpoint lands in a later Phase 36 plan;
# the constant is declared here so no call site carries a bare path literal.
_PROJECTS_URL = "/api/v1/projects/"
_BUDGETS_URL = "/api/v1/budgets/"
_COST_ENTRIES_URL = "/api/v1/cost-entries/"
_TRADE_SCOPES_URL = "/api/v1/trade-scopes/"
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

_QUOTE_BACKDATE_SQL = (
    "UPDATE quotes SET created_at = :created_at WHERE id = CAST(:quote_id AS uuid)"
)

_OPEN_FINDINGS_SQL = (
    "SELECT id, project_id, signal, severity_band, fingerprint, narrative, "
    "corrective_action, alert_summary, revenue_basis, labor_included, "
    "alerted_at, resolved_at, found_on, last_confirmed_on "
    "FROM ai_profitability_findings "
    "WHERE deleted_at IS NULL AND resolved_at IS NULL "
    "ORDER BY created_at"
)

_ALL_FINDINGS_COUNT_SQL = "SELECT count(*) FROM ai_profitability_findings WHERE deleted_at IS NULL"


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------


def _token(company_id: str, roles: list[str]) -> str:
    """Mint an access token for a synthetic user with the given roles."""
    return create_access_token(uuid4(), UUID(company_id), roles)


def _pm_headers(company_id: str) -> dict:
    """Authorization header for a project_manager token (finance.view + finance.manage)."""
    return {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}


def _admin_headers(company_id: str) -> dict:
    """Authorization header for an admin token (excluded from finance.* by default)."""
    return {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}


def _finding_url(project_id: str) -> str:
    """URL of one project's latest AI finding (endpoint lands in a later Phase 36 plan)."""
    return f"/api/v1/projects/{project_id}/financials/finding"


def _make_mock_anthropic_response(content: dict | str) -> MagicMock:
    """Build a mock Anthropic message response with content[0].text."""
    body = json.dumps(content) if isinstance(content, dict) else content

    mock_content = MagicMock()
    mock_content.text = body

    mock_response = MagicMock()
    mock_response.content = [mock_content]
    return mock_response


# ---------------------------------------------------------------------------
# Structure and money seeders — driven through the shipped endpoints
# ---------------------------------------------------------------------------


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


async def _create_project(client: AsyncClient, name: str = "Profitability Project 36") -> str:
    """Create a project through the API and return its id."""
    resp = await client.post(_PROJECTS_URL, json={"name": name, "status": "active"})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient, project_id: str, trade_name: str = "Plumbing"
) -> str:
    """Create a trade scope on a project through the API and return its id."""
    resp = await client.post(
        _TRADE_SCOPES_URL,
        json={"project_id": project_id, "trade_name": trade_name, "trade_color": "#2196F3"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_job(client: AsyncClient, project_id: str | None = None) -> str:
    """Create a job through the API, optionally linked to a project, and return its id."""
    payload: dict = {"description": "Profitability test job", "trade_type": "general"}
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


_DEFAULT_INCURRED_DATE = date(2026, 6, 1)


async def _add_cost_entry(
    client: AsyncClient,
    headers: dict,
    *,
    job_id: str | None = None,
    trade_scope_id: str | None = None,
    category_id: str,
    amount: str,
    incurred_date: date = _DEFAULT_INCURRED_DATE,
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


# ---------------------------------------------------------------------------
# Revenue seeders — the anchors every profitability assertion needs
# ---------------------------------------------------------------------------


def _material_line_item(amount: str) -> dict:
    """One material line item — the only revenue shape these fixtures need."""
    return {
        "item_type": "material",
        "description": "Phase 36 revenue item",
        "quantity": "1.000",
        "unit": "each",
        "unit_price": amount,
    }


async def _mark_job_complete(company_id: str, job_id: str) -> None:
    """Force a job to 'complete' via SQL so a manual invoice can be posted on it."""
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

    SQL, never POST /quotes/{id}/approve — the endpoint demands a sent/viewed
    transition and creates jobs for project-level quotes (33-02 lesson).
    """
    statement = _QUOTE_APPROVE_SQL if project_id is None else _QUOTE_APPROVE_WITH_PROJECT_SQL
    params: dict = {"quote_id": quote_id, "approved_at": approved_at}
    if project_id is not None:
        params["project_id"] = project_id
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(text(statement), params)
        await session.commit()


async def _backdate_quote(company_id: str, quote_id: str, created_at: datetime) -> None:
    """Move a quote's created_at into the past."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_QUOTE_BACKDATE_SQL), {"quote_id": quote_id, "created_at": created_at}
        )
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
    """Create a quote at one anchor and force it to approved, returning its id."""
    payload: dict = {"line_items": [_material_line_item(amount)]}
    if job_id is not None:
        payload["job_id"] = job_id
    if trade_scope_id is not None:
        payload["trade_scope_id"] = trade_scope_id
    if job_id is None and trade_scope_id is None:
        payload["title"] = "Phase 36 project quote"
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
    """Create an invoice at one anchor on a caller-chosen issue date and return its id."""
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
# Findings helpers — the Phase 36 persistence floor
# ---------------------------------------------------------------------------

_FIRST_NIGHT = date(2026, 7, 1)
_SECOND_NIGHT = date(2026, 7, 2)
_THIRD_NIGHT = date(2026, 7, 3)

_DEFAULT_FINGERPRINT = "negative_margin:critical"
_ORIGINAL_NARRATIVE = "Costs on this project have overtaken invoiced revenue."
_RESTATED_NARRATIVE = "Costs on this project now exceed invoiced revenue by a wider gap."


@contextlib.asynccontextmanager
async def _tenant_repository(company_id: str) -> AsyncIterator[ProfitabilityRepository]:
    """A ProfitabilityRepository in a tenant-scoped session, committed on exit.

    The scheduler-path convention: the repository never commits, its caller does.
    PostgreSQL rejects a parameterized SET LOCAL, hence the f-string.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        yield ProfitabilityRepository(session)
        await session.commit()


def _finding_upsert(
    company_id: str,
    project_id: str,
    *,
    fingerprint: str = _DEFAULT_FINGERPRINT,
    narrative: str = _ORIGINAL_NARRATIVE,
    corrective_action: str = "Re-price the remaining scope before the next draw.",
    alert_summary: str = "Negative margin on this project.",
    severity_band: str = "critical",
    analyzed_on: date = _FIRST_NIGHT,
    payload: dict | None = None,
) -> FindingUpsert:
    """One night's finding for a project, with every field defaulted to a valid value."""
    return FindingUpsert(
        company_id=UUID(company_id),
        project_id=UUID(project_id),
        signal="negative_margin",
        severity_band=severity_band,
        fingerprint=fingerprint,
        narrative=narrative,
        corrective_action=corrective_action,
        alert_summary=alert_summary,
        revenue_basis="invoiced",
        labor_included=True,
        payload=payload if payload is not None else {"margin": "-500.00"},
        analyzed_on=analyzed_on,
    )


async def _open_findings(company_id: str) -> list[dict]:
    """Every open finding row for a company, read with RLS context set."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_OPEN_FINDINGS_SQL))
        return [dict(row) for row in result.mappings()]


async def _finding_count(company_id: str) -> int:
    """Count every live finding row for a company, resolved ones included."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_ALL_FINDINGS_COUNT_SQL))
        return result.scalar_one()


# ---------------------------------------------------------------------------
# FINAI-01: findings persistence — upsert, claim, resolve, latest-open
# ---------------------------------------------------------------------------


async def test_finding_upsert_is_idempotent_and_preserves_alert_state(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A second night on the same fingerprint restates the text without re-arming the alert."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    async with _tenant_repository(company_id) as repository:
        first = await repository.upsert_finding(_finding_upsert(company_id, project_id))
        finding_id = first.id
        assert first.alerted_at is None
        assert first.found_on == _FIRST_NIGHT
        assert first.last_confirmed_on == _FIRST_NIGHT

    async with _tenant_repository(company_id) as repository:
        assert await repository.claim_alert(finding_id) == finding_id

    async with _tenant_repository(company_id) as repository:
        restated = await repository.upsert_finding(
            _finding_upsert(
                company_id,
                project_id,
                narrative=_RESTATED_NARRATIVE,
                analyzed_on=_SECOND_NIGHT,
                payload={"margin": "-900.00"},
            )
        )
        assert restated.id == finding_id
        assert restated.payload == {"margin": "-900.00"}

    rows = await _open_findings(company_id)
    assert len(rows) == 1
    assert rows[0]["narrative"] == _RESTATED_NARRATIVE
    assert rows[0]["last_confirmed_on"] == _SECOND_NIGHT
    assert rows[0]["found_on"] == _FIRST_NIGHT
    assert rows[0]["alerted_at"] is not None


async def test_claim_alert_succeeds_exactly_once(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Two claims on one finding return its id, then None — no second alert is possible."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    async with _tenant_repository(company_id) as repository:
        finding_id = (await repository.upsert_finding(_finding_upsert(company_id, project_id))).id

    async with _tenant_repository(company_id) as repository:
        first_claim = await repository.claim_alert(finding_id)

    async with _tenant_repository(company_id) as repository:
        second_claim = await repository.claim_alert(finding_id)

    assert first_claim == finding_id
    assert second_claim is None


async def test_resolve_then_recur_inserts_a_fresh_unalerted_row(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A resolved fingerprint that recurs inserts a NEW row that can alert again (D-06)."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    async with _tenant_repository(company_id) as repository:
        original_id = (await repository.upsert_finding(_finding_upsert(company_id, project_id))).id

    async with _tenant_repository(company_id) as repository:
        assert await repository.claim_alert(original_id) == original_id

    async with _tenant_repository(company_id) as repository:
        assert await repository.resolve_absent_fingerprints(keep=[]) == 1

    assert await _open_findings(company_id) == []

    async with _tenant_repository(company_id) as repository:
        recurrence = await repository.upsert_finding(
            _finding_upsert(company_id, project_id, analyzed_on=_THIRD_NIGHT)
        )
        recurrence_id = recurrence.id
        assert recurrence_id != original_id
        assert recurrence.alerted_at is None
        assert recurrence.found_on == _THIRD_NIGHT

    assert await _finding_count(company_id) == 2

    async with _tenant_repository(company_id) as repository:
        latest = await repository.latest_open_for_project(UUID(project_id))
        assert latest is not None
        assert latest.id == recurrence_id
        assert await repository.latest_open_for_project(uuid4()) is None
