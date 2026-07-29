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
from collections.abc import AsyncIterator, Iterator, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from unittest.mock import MagicMock
from uuid import UUID, uuid4

import pytest
import structlog
from httpx import AsyncClient
from sqlalchemy import event, select, text
from sqlalchemy.exc import IntegrityError

from app.core.ai_grounding import collect_allowed_values
from app.core.database import async_session_factory, engine
from app.core.security import create_access_token
from app.features.dashboard.alert_types import AI_PROFITABILITY_ALERT_TYPE, FINANCIAL_ALERT_TYPES
from app.features.dashboard.models import DashboardAlert
from app.features.finance.models import CostCategory
from app.features.finance.profitability_math import SIGNAL_QUOTE_GAP, SkipReason
from app.features.finance.profitability_models import (
    MAX_ALERT_SUMMARY_LENGTH,
    MAX_NARRATIVE_LENGTH,
)
from app.features.finance.profitability_repository import FindingUpsert, ProfitabilityRepository
from app.features.finance.profitability_service import (
    LABOR_BASIS_UNBURDENED,
    SCAN_SUMMARY_LOG_TEMPLATE,
    SKIP_LOG_TEMPLATE,
    TREND_PAYLOAD_BUCKETS,
    ProfitabilityCandidate,
    ProfitabilityService,
)

_SECONDS_PER_HOUR = 3600
_ALERT_TYPE_CHECK_NAME = "dashboard_alerts_alert_type_check"

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
# Nightly-scan fixture amounts (FINAI-01)
#
# The analyzable project bills 6,000 against a 10,000 approved quote at the same
# job anchor with 5,000 of cost: billed margin 16.7% against a quote-implied
# 50.0% is a 33.3-point gap, comfortably over QUOTE_IMPLIED_GAP_POINTS, while the
# margin itself stays positive so the negative-margin signal cannot pre-empt it.
# ---------------------------------------------------------------------------

_ACTIVE_PROJECT_STATUS = "active"
_INVOICED_REVENUE_BASIS = "invoiced"
_MATERIALS_CATEGORY = "materials"
_ANALYZABLE_COST_AMOUNT = "5000.00"
_ANALYZABLE_INVOICE_AMOUNT = "6000.00"
_UNDER_BILLED_QUOTE_AMOUNT = "10000.00"
_ANALYZABLE_BUDGET_TOTAL = "8000.00"
_UNRATED_LABOR_HOURS = 8
_MONEY_SEED_DAYS_AGO = 20
_LABOR_SEED_DAYS_AGO = 10

# Both companies in the query-count test carry the SAME number of projects, so
# only how many of them are ELIGIBLE can move the statement count.
_FEW_ELIGIBLE_COUNT = 2
_INELIGIBLE_COUNT = 6
_MANY_ELIGIBLE_COUNT = _FEW_ELIGIBLE_COUNT + _INELIGIBLE_COUNT

_EXPECTED_PAYLOAD_FIELDS = frozenset(
    {
        "project_name",
        "project_status",
        "cost",
        "revenue",
        "revenue_basis",
        "quoted_revenue_share",
        "margin",
        "margin_percent",
        "labor_basis",
        "labor_cost",
        "categories",
        "budgets",
        "trend",
        "signal",
        "severity_band",
        "negative_margin_dollars",
        "margin_decline_points",
        "quote_gap_points",
        "billed_margin_percent",
        "quote_implied_margin_percent",
        "over_quote_dollars",
    }
)

_PAYLOAD_AGGREGATE_MONEY_FIELDS = (
    "cost",
    "revenue",
    "quoted_revenue_share",
    "margin",
    "margin_percent",
    "labor_cost",
)

_PAYLOAD_BUDGET_MONEY_FIELDS = ("spent", "total", "percent_used", "remaining")

_PAYLOAD_QUOTE_GAP_FIELDS = (
    "quote_gap_points",
    "billed_margin_percent",
    "quote_implied_margin_percent",
    "over_quote_dollars",
)

# Fields a raw-row payload would carry; their ABSENCE is the aggregates-only proof.
_FORBIDDEN_PAYLOAD_FIELDS = ("unrated_seconds", "incomplete_reasons", "entries", "cost_entries")


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
    """Create a project through the API and return its id.

    The project lands in 'draft': ProjectCreate declares no status field, so a
    status in the POST body is silently ignored. D-01 analyzes 'active' projects
    only, so every analysis fixture must patch the transition (_activate_project).
    """
    resp = await client.post(_PROJECTS_URL, json={"name": name})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _activate_project(client: AsyncClient, project_id: str) -> None:
    """Transition a project to 'active' — the only status D-01 admits for analysis."""
    resp = await client.patch(f"{_PROJECTS_URL}{project_id}", json={"status": "active"})
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == _ACTIVE_PROJECT_STATUS


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
# Nightly-scan helpers — seeding, driving, and observing scan_candidates
# ---------------------------------------------------------------------------


@contextlib.contextmanager
def _count_sql_statements() -> Iterator[list[str]]:
    """Record every SQL statement issued while the block runs.

    COPIED from test_phase_35_e2e.py per the self-contained-test-file convention.
    Listens on engine.sync_engine because SQLAlchemy's event API is synchronous by
    design (the same reason app/core/tenant.py's after_begin listener is sync).
    """
    statements: list[str] = []

    def _record(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement)

    event.listen(engine.sync_engine, "before_cursor_execute", _record)
    try:
        yield statements
    finally:
        event.remove(engine.sync_engine, "before_cursor_execute", _record)


def _days_ago(days: int) -> datetime:
    """A UTC timestamp `days` in the past.

    Money and labor fixtures are dated RELATIVE to now, never to a fixed calendar
    month: the margin trend's last bucket is always the current UTC month, so
    hard-coded dates quietly drift out of the buckets as time passes (35-07 lesson).
    """
    return datetime.now(UTC) - timedelta(days=days)


@dataclass(frozen=True)
class _AnalyzableProject:
    """One seeded project and the job anchor its cost and revenue both sit on."""

    project_id: str
    job_id: str


async def _seed_analyzable_project(
    client: AsyncClient,
    company_id: str,
    *,
    name: str,
    activate: bool = True,
    cost_amount: str | None = _ANALYZABLE_COST_AMOUNT,
    invoice_amount: str | None = _ANALYZABLE_INVOICE_AMOUNT,
    quote_amount: str | None = None,
    budget_total: str | None = None,
) -> _AnalyzableProject:
    """Seed one project whose cost and revenue share a single job anchor.

    Every D-01 skip fixture is this seeder with one leg withheld: `activate=False`
    is NOT_ACTIVE, `invoice_amount=None` is NO_REVENUE_SOURCE, and
    `cost_amount=None` is the revenue-bearing zero-cost project. The approved
    quote rides the SAME anchor as the invoice, which is the only shape the
    quote-implied gap can compare.
    """
    headers = _pm_headers(company_id)
    project_id = await _create_project(client, name)
    if activate:
        await _activate_project(client, project_id)
    job_id = await _create_job(client, project_id)
    if cost_amount is not None:
        await _add_cost_entry(
            client,
            headers,
            job_id=job_id,
            category_id=await _category_id(company_id, _MATERIALS_CATEGORY),
            amount=cost_amount,
            incurred_date=_days_ago(_MONEY_SEED_DAYS_AGO).date(),
        )
    if budget_total is not None:
        await _create_budget(client, headers, project_id=project_id, total=budget_total)
    if quote_amount is not None:
        await _create_approved_quote(
            client,
            company_id,
            job_id=job_id,
            amount=quote_amount,
            approved_at=_days_ago(_MONEY_SEED_DAYS_AGO),
        )
    if invoice_amount is not None:
        await _create_invoice(
            client,
            company_id,
            job_id=job_id,
            amount=invoice_amount,
            issued_at=_days_ago(_MONEY_SEED_DAYS_AGO),
        )
    return _AnalyzableProject(project_id=project_id, job_id=job_id)


async def _seed_unrated_labor(client: AsyncClient, company_id: str, job_id: str) -> None:
    """Add tracked time for a worker with no labor rate — the unrated-labor flag."""
    contractor_id = await _create_user(client, f"unrated-{uuid4().hex[:8]}@example.com")
    await _seed_time_entry(
        company_id,
        job_id,
        contractor_id,
        _UNRATED_LABOR_HOURS,
        clocked_in_at=_days_ago(_LABOR_SEED_DAYS_AGO),
    )


async def _scan_candidates(company_id: str) -> list[ProfitabilityCandidate]:
    """Drive the nightly scan for one company under its own RLS context.

    No Claude patching is needed: scan_candidates never calls the API. PostgreSQL
    rejects a parameterized SET LOCAL, hence the f-string.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        return await ProfitabilityService(session).scan_candidates(UUID(company_id))


def _logged_events(logs: Sequence[dict]) -> list[str]:
    """Every rendered log line the scan emitted, in order.

    structlog.testing.capture_logs, not pytest's caplog: this app configures
    structlog with the stdlib bridge and caplog captures NOTHING from it (verified
    empirically), so an assertion built on caplog would pass vacuously.
    """
    return [entry["event"] for entry in logs]


def _expected_skip_line(project_id: str, reason: SkipReason) -> str:
    """The exact line the scan must log for one skipped project."""
    return SKIP_LOG_TEMPLATE % (project_id, reason.value)


def _expected_summary_line(company_id: str, analyzed: int, candidates: int, skipped: int) -> str:
    """The exact per-company summary line that closes one scan."""
    return SCAN_SUMMARY_LOG_TEMPLATE % (company_id, analyzed, candidates, skipped)


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


# ---------------------------------------------------------------------------
# FINAI-02: schema contracts — alert type, tenant isolation, DB length CHECKs
# ---------------------------------------------------------------------------


def _orm_alert_type_check_sql() -> str:
    """The alert_type CHECK expression exactly as DashboardAlert declares it.

    Read from the ORM table metadata rather than the database: a SQLAlchemy
    CheckConstraint is DDL-only and is never evaluated on flush, so inserting a
    row proves the MIGRATION's value list and nothing about models.py. The two
    halves of this test together are the RESEARCH Pitfall 3 guard.
    """
    constraint = next(
        candidate
        for candidate in DashboardAlert.__table__.constraints
        if candidate.name == _ALERT_TYPE_CHECK_NAME
    )
    return str(constraint.sqltext)


async def test_ai_profitability_alert_type_accepted_by_orm(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """ai_profitability is spelled in all three literals that must agree on it."""
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        alert = DashboardAlert(
            company_id=UUID(company_id),
            project_id=UUID(project_id),
            severity="warning",
            alert_type=AI_PROFITABILITY_ALERT_TYPE,
            impact_text="Costs have overtaken revenue on this project.",
        )
        session.add(alert)
        await session.flush()
        alert_id = alert.id
        await session.commit()

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        stored = await session.get(DashboardAlert, alert_id)
        assert stored is not None
        assert stored.alert_type == AI_PROFITABILITY_ALERT_TYPE

    assert AI_PROFITABILITY_ALERT_TYPE in _orm_alert_type_check_sql()
    assert AI_PROFITABILITY_ALERT_TYPE in FINANCIAL_ALERT_TYPES


async def test_findings_rls_isolation(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Tenant B reads zero rows of tenant A's findings."""
    company_a_id = seed_two_tenants["tenant_a_id"]
    company_b_id = seed_two_tenants["tenant_b_id"]
    project_id = await _create_project(tenant_a_client)

    async with _tenant_repository(company_a_id) as repository:
        await repository.upsert_finding(_finding_upsert(company_a_id, project_id))

    assert len(await _open_findings(company_a_id)) == 1
    assert await _open_findings(company_b_id) == []

    async with _tenant_repository(company_b_id) as repository:
        assert await repository.latest_open_for_project(UUID(project_id)) is None


async def test_alert_summary_db_length_check(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Over-length text is REJECTED by the database, never silently truncated.

    The DATABASE half of the UI-SPEC length contract. Plan 36-08 owns the SERVICE
    half under the distinct name test_over_length_draft_is_rejected_not_truncated.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)

    with pytest.raises(IntegrityError) as over_length_summary:
        async with _tenant_repository(company_id) as repository:
            await repository.upsert_finding(
                _finding_upsert(
                    company_id,
                    project_id,
                    alert_summary="s" * (MAX_ALERT_SUMMARY_LENGTH + 1),
                )
            )
    assert "ai_profitability_findings_alert_summary_length_check" in str(over_length_summary.value)

    with pytest.raises(IntegrityError) as over_length_narrative:
        async with _tenant_repository(company_id) as repository:
            await repository.upsert_finding(
                _finding_upsert(
                    company_id,
                    project_id,
                    narrative="n" * (MAX_NARRATIVE_LENGTH + 1),
                )
            )
    assert "ai_profitability_findings_narrative_length_check" in str(over_length_narrative.value)

    assert await _finding_count(company_id) == 0

    async with _tenant_repository(company_id) as repository:
        accepted = await repository.upsert_finding(
            _finding_upsert(
                company_id,
                project_id,
                alert_summary="s" * MAX_ALERT_SUMMARY_LENGTH,
            )
        )
        assert len(accepted.alert_summary) == MAX_ALERT_SUMMARY_LENGTH


# ---------------------------------------------------------------------------
# FINAI-01: the nightly scan — D-01 eligibility, D-03 detection, payload closure
# ---------------------------------------------------------------------------


async def test_skips_non_active_project(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A draft project with full cost and revenue is never analyzed (D-01)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project = await _seed_analyzable_project(
        tenant_a_client, company_id, name="Draft Project 36", activate=False
    )

    with structlog.testing.capture_logs() as logs:
        candidates = await _scan_candidates(company_id)

    assert candidates == []
    events = _logged_events(logs)
    assert _expected_skip_line(project.project_id, SkipReason.NOT_ACTIVE) in events
    assert _expected_summary_line(company_id, analyzed=0, candidates=0, skipped=1) in events


async def test_skips_project_without_revenue_source(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Cost with no invoice and no approved quote has no margin to analyze (D-01)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project = await _seed_analyzable_project(
        tenant_a_client, company_id, name="Revenue-less Project 36", invoice_amount=None
    )

    with structlog.testing.capture_logs() as logs:
        candidates = await _scan_candidates(company_id)

    assert candidates == []
    assert _expected_skip_line(project.project_id, SkipReason.NO_REVENUE_SOURCE) in _logged_events(
        logs
    )


async def test_skips_incomplete_cost_data_project(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A revenue-bearing project with zero cost never reaches the AI (Pitfall 9).

    This is the fabricated-100%-margin case: revenue with no cost recorded yet.
    The D-01 ladder names it NO_COST_DATA — the zero-cost rung is checked before
    the margin's incomplete flag, so that reason (not INCOMPLETE_DATA) is the
    shipped verdict. What matters for Pitfall 9 is that it is skipped, with a name.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project = await _seed_analyzable_project(
        tenant_a_client, company_id, name="Zero-cost Project 36", cost_amount=None
    )

    with structlog.testing.capture_logs() as logs:
        candidates = await _scan_candidates(company_id)

    assert candidates == []
    assert _expected_skip_line(project.project_id, SkipReason.NO_COST_DATA) in _logged_events(logs)


async def test_skips_unrated_labor_project(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Tracked time with no effective rate makes the margin incomplete — no analysis."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project = await _seed_analyzable_project(
        tenant_a_client, company_id, name="Unrated Labor Project 36"
    )
    await _seed_unrated_labor(tenant_a_client, company_id, project.job_id)

    with structlog.testing.capture_logs() as logs:
        candidates = await _scan_candidates(company_id)

    assert candidates == []
    assert _expected_skip_line(project.project_id, SkipReason.INCOMPLETE_DATA) in _logged_events(
        logs
    )


async def test_quote_implied_gap_produces_candidate(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Invoicing below an approved quote at the same anchor surfaces one quote_gap candidate."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    project = await _seed_analyzable_project(
        tenant_a_client,
        company_id,
        name="Under-billed Project 36",
        quote_amount=_UNDER_BILLED_QUOTE_AMOUNT,
    )

    with structlog.testing.capture_logs() as logs:
        candidates = await _scan_candidates(company_id)

    assert len(candidates) == 1
    found = candidates[0]
    assert found.candidate.project_id == UUID(project.project_id)
    assert found.candidate.signal == SIGNAL_QUOTE_GAP
    assert found.project_name == "Under-billed Project 36"
    assert found.revenue_basis == _INVOICED_REVENUE_BASIS
    assert found.labor_included is False
    assert _expected_summary_line(
        company_id, analyzed=1, candidates=1, skipped=0
    ) in _logged_events(logs)


async def test_payload_carries_only_aggregates_and_named_deltas(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """The payload is aggregates plus one named field per citable delta — nothing else.

    Asserting the field set EXACTLY is the closed-set guard: an unnamed delta the
    prompt permits would let the model cite a figure the validator cannot match,
    and a stray raw-row field would ship cost entries to the API.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    await _seed_analyzable_project(
        tenant_a_client,
        company_id,
        name="Payload Project 36",
        quote_amount=_UNDER_BILLED_QUOTE_AMOUNT,
        budget_total=_ANALYZABLE_BUDGET_TOTAL,
    )

    candidates = await _scan_candidates(company_id)

    assert len(candidates) == 1
    payload = candidates[0].payload
    assert set(payload) == _EXPECTED_PAYLOAD_FIELDS
    for forbidden in _FORBIDDEN_PAYLOAD_FIELDS:
        assert forbidden not in payload

    assert payload["project_status"] == _ACTIVE_PROJECT_STATUS
    assert payload["revenue_basis"] == _INVOICED_REVENUE_BASIS
    assert payload["labor_basis"] == LABOR_BASIS_UNBURDENED
    assert payload["signal"] == SIGNAL_QUOTE_GAP

    for field in _PAYLOAD_AGGREGATE_MONEY_FIELDS:
        assert isinstance(payload[field], Decimal), field
    for field in _PAYLOAD_QUOTE_GAP_FIELDS:
        assert isinstance(payload[field], Decimal), field
    assert payload["negative_margin_dollars"] is None

    categories = payload["categories"]
    assert categories
    assert all(isinstance(row["cost"], Decimal) for row in categories)

    budgets = payload["budgets"]
    assert budgets
    assert all(
        isinstance(row[field], Decimal) for row in budgets for field in _PAYLOAD_BUDGET_MONEY_FIELDS
    )

    trend = payload["trend"]
    assert trend
    assert len(trend) <= TREND_PAYLOAD_BUCKETS
    assert all(isinstance(bucket["cost"], Decimal) for bucket in trend)

    allowed = collect_allowed_values(payload)
    assert payload["cost"] in allowed
    assert payload["quote_gap_points"] in allowed
    assert payload["over_quote_dollars"] in allowed


async def test_candidate_scan_query_count_is_bounded_by_eligible_projects(
    tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Ineligible projects cost no trend replay — the D-01 gate provably runs first.

    Both companies carry the same number of projects, so only how many are
    ELIGIBLE can move the statement count. This is the Open-Question-3 evidence:
    the scan is O(eligible), not O(all projects).
    """
    company_a_id = seed_two_tenants["tenant_a_id"]
    company_b_id = seed_two_tenants["tenant_b_id"]
    await _seed_cost_categories(company_a_id)
    await _seed_cost_categories(company_b_id)

    for index in range(_FEW_ELIGIBLE_COUNT):
        await _seed_analyzable_project(tenant_a_client, company_a_id, name=f"A eligible {index}")
    for index in range(_INELIGIBLE_COUNT):
        await _seed_analyzable_project(
            tenant_a_client,
            company_a_id,
            name=f"A draft {index}",
            activate=False,
            cost_amount=None,
            invoice_amount=None,
        )
    for index in range(_MANY_ELIGIBLE_COUNT):
        await _seed_analyzable_project(tenant_b_client, company_b_id, name=f"B eligible {index}")

    with _count_sql_statements() as few_eligible_statements:
        await _scan_candidates(company_a_id)
    with _count_sql_statements() as many_eligible_statements:
        await _scan_candidates(company_b_id)

    assert len(few_eligible_statements) < len(many_eligible_statements)
