"""Phase 36 — AI Profitability Analysis.

Covers FINAI-01/FINAI-02: the findings persistence floor (idempotent nightly
upsert, claim-first alerting, resolve-then-recur lifecycle), the schema
contracts that guard it (the ai_profitability alert type, tenant isolation, and
the DB half of the UI-SPEC text-length contract), the nightly scan's D-01
eligibility gate, and the publish path's D-05 grounding contract.

Claude is never called for real: `app.core.ai_utils.get_anthropic_client` is
patched (the Phase 26 precedent) so the retry, dismissal, length and cap
behaviors are all offline and deterministic. No assertion here compares AI prose
byte-for-byte — bounds and grounding only, per the UI-SPEC.

Per the self-contained-test-file convention the helper set is COPIED from
test_phase_35_e2e.py (and _make_mock_anthropic_response from
test_phase_26_e2e.py) rather than imported across test modules, so a later
edit to a Phase 35 fixture can never silently change what Phase 36 asserts.

Repository-level tests drive ProfitabilityRepository inside
async_session_factory() with the SET LOCAL f-string pattern (PostgreSQL rejects
a parameterized SET LOCAL) and commit in the test — the scheduler-path
convention, where the repository never commits and its caller does.
"""

import asyncio
import contextlib
import json
from collections.abc import AsyncIterator, Iterator, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest
import structlog
from httpx import AsyncClient
from sqlalchemy import event, select, text
from sqlalchemy.exc import IntegrityError

from app.core.ai_grounding import collect_allowed_values
from app.core.ai_utils import gather_with_concurrency
from app.core.database import async_session_factory, engine
from app.core.security import create_access_token
from app.features.dashboard.alert_types import AI_PROFITABILITY_ALERT_TYPE, FINANCIAL_ALERT_TYPES
from app.features.dashboard.models import DashboardAlert
from app.features.finance.models import CostCategory
from app.features.finance.profitability_math import (
    SEVERITY_BAND_CRITICAL,
    SEVERITY_BAND_WARNING,
    SIGNAL_NEGATIVE_MARGIN,
    SIGNAL_QUOTE_GAP,
    CandidateSignal,
    SkipReason,
)
from app.features.finance.profitability_models import (
    MAX_ALERT_SUMMARY_LENGTH,
    MAX_CORRECTIVE_ACTION_LENGTH,
    MAX_NARRATIVE_LENGTH,
    AIProfitabilityFinding,
)
from app.features.finance.profitability_repository import FindingUpsert, ProfitabilityRepository
from app.features.finance.profitability_service import (
    _PROFITABILITY_PUSH_TYPE,
    AI_FINDING_PREFIX,
    CAP_DROP_LOG_TEMPLATE,
    DISMISSAL_LOG_TEMPLATE,
    EMPTY_DRAFT_LOG_TEMPLATE,
    GROUNDING_RETRY_LIMIT,
    LABOR_BASIS_UNBURDENED,
    MAX_FINDINGS_PER_COMPANY_PER_NIGHT,
    OVER_LENGTH_DROP_LOG_TEMPLATE,
    PROFITABILITY_MAX_OUTPUT_TOKENS,
    PUSH_TITLE_BY_BAND,
    SCAN_SUMMARY_LOG_TEMPLATE,
    SKIP_LOG_TEMPLATE,
    SUGGESTED_ACTION_PREFIX,
    TREND_PAYLOAD_BUCKETS,
    UNGROUNDED_DROP_LOG_TEMPLATE,
    FindingDraft,
    ProfitabilityCandidate,
    ProfitabilityService,
    PublishResult,
)
from app.features.finance.prompts.profitability_system import (
    ALERT_SUMMARY_MAX_CHARS,
    CORRECTIVE_ACTION_MAX_CHARS,
    NARRATIVE_MAX_CHARS,
)
from app.features.rbac.repository import RbacRepository

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

_AI_PROFITABILITY_ALERT_COUNT_SQL = (
    "SELECT count(*) FROM dashboard_alerts WHERE alert_type = :alert_type AND deleted_at IS NULL"
)

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


# ---------------------------------------------------------------------------
# FINAI-01: the publish path — D-05 grounding, dismissal, per-candidate isolation
#
# Patch target is app.core.ai_utils.get_anthropic_client (the Phase 26
# precedent), so the first call and its one D-05 retry both land on a single
# recorded mock.
# ---------------------------------------------------------------------------

_CLAUDE_CLIENT_PATH = "app.core.ai_utils.get_anthropic_client"

# _ANALYZABLE_COST_AMOUNT as format_alert_money would render it — present in
# every seeded payload, so citing it is grounded by construction.
_GROUNDED_LITERAL = "$5,000"
# Absent from every seeded payload, so citing it is fabrication by construction.
_FABRICATED_LITERAL = "$9,999"

_GROUNDED_NARRATIVE = (
    "Billed revenue trails the approved quote at this job anchor while recorded cost has "
    f"reached {_GROUNDED_LITERAL}."
)
_GROUNDED_CORRECTIVE_ACTION = (
    "Rebill the plumbing change order or renegotiate supplier pricing — recorded cost is "
    f"already {_GROUNDED_LITERAL}."
)
_GROUNDED_ALERT_SUMMARY = (
    f"Billed margin trails the approved quote on recorded cost of {_GROUNDED_LITERAL}."
)
_AI_STRING_FIELDS = ("narrative", "corrective_action", "alert_summary")
_DISMISSAL_REASON = "The gap is already explained by a pending change order."

_GROUNDED_DRAFT = FindingDraft(
    narrative=_GROUNDED_NARRATIVE,
    corrective_action=_GROUNDED_CORRECTIVE_ACTION,
    alert_summary=_GROUNDED_ALERT_SUMMARY,
)


def _finding_reply_data(**overrides: object) -> dict:
    """One Claude JSON turn — confirmed and fully grounded unless overridden."""
    return {
        "confirmed": True,
        "dismissal_reason": None,
        "narrative": _GROUNDED_NARRATIVE,
        "corrective_action": _GROUNDED_CORRECTIVE_ACTION,
        "alert_summary": _GROUNDED_ALERT_SUMMARY,
        **overrides,
    }


def _grounded_reply() -> MagicMock:
    """A reply whose three AI strings cite only payload figures."""
    return _make_mock_anthropic_response(_finding_reply_data())


def _fabricating_reply(field: str = "narrative") -> MagicMock:
    """A reply whose named AI string cites a figure no payload contains."""
    fabricated = _finding_reply_data()[field].replace(_GROUNDED_LITERAL, _FABRICATED_LITERAL)
    return _make_mock_anthropic_response(_finding_reply_data(**{field: fabricated}))


def _dismissal_reply() -> MagicMock:
    """The prompt's dismissal contract: confirmed false, a reason, empty text fields."""
    return _make_mock_anthropic_response(
        _finding_reply_data(
            confirmed=False,
            dismissal_reason=_DISMISSAL_REASON,
            narrative="",
            corrective_action="",
            alert_summary="",
        )
    )


def _textless_confirmation_reply() -> MagicMock:
    """Malformed: a confirmed finding with no text at all behind it."""
    return _make_mock_anthropic_response(
        _finding_reply_data(narrative="", corrective_action="", alert_summary="")
    )


@contextlib.contextmanager
def _patched_claude(*, side_effect: object) -> Iterator[AsyncMock]:
    """Patch the Anthropic client and hand back the recorded messages.create mock."""
    with patch(_CLAUDE_CLIENT_PATH) as mock_client:
        create = AsyncMock(side_effect=side_effect)
        mock_client.return_value.messages.create = create
        yield create


async def _draft_findings(company_id: str) -> list[FindingDraft | None]:
    """Scan, then draft every candidate — the publish path minus persistence.

    Drives the private _draft_for through the same gather_with_concurrency
    wrapper publish_findings uses, which is what makes a per-candidate Claude
    failure observable as one None rather than a raised run.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        service = ProfitabilityService(session)
        candidates = await service.scan_candidates(UUID(company_id))
        return await gather_with_concurrency(candidates, service._draft_for)


def _patched_scan(
    service: ProfitabilityService, candidates: Sequence[ProfitabilityCandidate] | None
) -> contextlib.AbstractContextManager:
    """Patch scan_candidates when a test supplies its own candidates, else do nothing."""
    if candidates is None:
        return contextlib.nullcontext()
    return patch.object(service, "scan_candidates", AsyncMock(return_value=list(candidates)))


async def _publish_findings(
    company_id: str, candidates: Sequence[ProfitabilityCandidate] | None = None
) -> PublishResult:
    """Drive publish_findings for one company under its own RLS context, committing on exit.

    The scheduler-path convention: the service never commits, its caller does.
    Supplying `candidates` patches the scan, which is how a cap or length behavior
    is proven against a dozen candidates without seeding a dozen projects.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        service = ProfitabilityService(session)
        with _patched_scan(service, candidates):
            result = await service.publish_findings(UUID(company_id), _FIRST_NIGHT)
        await session.commit()
        return result


async def _stored_payload(company_id: str, finding_id: UUID) -> dict:
    """The payload JSONB exactly as one persisted finding carries it."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        finding = await session.get(AIProfitabilityFinding, finding_id)
        assert finding is not None
        return finding.payload


async def _ai_profitability_alert_count(company_id: str) -> int:
    """Count this company's ai_profitability dashboard alerts."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(
            text(_AI_PROFITABILITY_ALERT_COUNT_SQL),
            {"alert_type": AI_PROFITABILITY_ALERT_TYPE},
        )
        return result.scalar_one()


async def _seed_one_candidate_project(
    client: AsyncClient, company_id: str, *, name: str
) -> _AnalyzableProject:
    """Seed exactly one quote-gap candidate: cost and revenue below an approved quote."""
    await _seed_cost_categories(company_id)
    return await _seed_analyzable_project(
        client, company_id, name=name, quote_amount=_UNDER_BILLED_QUOTE_AMOUNT
    )


def _retry_turn_roles(create: AsyncMock) -> list[str]:
    """The role sequence of the message list the retry call was made with."""
    return [turn["role"] for turn in create.call_args_list[1].kwargs["messages"]]


async def test_grounded_finding_publishes_without_retry(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A first reply citing only payload figures is accepted with no retry consumed."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_one_candidate_project(tenant_a_client, company_id, name="Grounded Project 36")

    with _patched_claude(side_effect=[_grounded_reply()]) as create:
        drafts = await _draft_findings(company_id)

    assert create.call_count == 1
    assert drafts == [_GROUNDED_DRAFT]
    assert create.call_args.kwargs["max_tokens"] == PROFITABILITY_MAX_OUTPUT_TOKENS


async def test_grounding_retry_succeeds_on_second_attempt(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """The retry turn names the fabricated literal back and the rewrite is accepted."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_one_candidate_project(tenant_a_client, company_id, name="Retried Project 36")

    with _patched_claude(side_effect=[_fabricating_reply(), _grounded_reply()]) as create:
        drafts = await _draft_findings(company_id)

    assert create.call_count == 2
    assert drafts == [_GROUNDED_DRAFT]

    retry_messages = create.call_args_list[1].kwargs["messages"]
    assert _retry_turn_roles(create) == ["user", "assistant", "user"]
    assert _FABRICATED_LITERAL in retry_messages[1]["content"]
    assert _FABRICATED_LITERAL in retry_messages[2]["content"]


async def test_unmatched_figure_blocked_after_one_retry(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """KEYSTONE: a still-fabricated rewrite is dropped — nothing persisted, nothing alerted.

    Driven through the whole publish path, not just the drafting half, so the
    zero-rows and zero-alerts assertions run against the code that could actually
    have written them. Exactly two calls: GROUNDING_RETRY_LIMIT is 1, so there is
    no third attempt and no clipped-but-published middle ground.

    The dropped candidate still qualifies tonight, so its fingerprint MUST stay in
    the D-06 keep-set — otherwise plan 36-09 would resolve a live finding and
    re-alert the same condition on the next successful night.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project = await _seed_one_candidate_project(
        tenant_a_client, company_id, name="Ungrounded Project 36"
    )

    with (
        structlog.testing.capture_logs() as logs,
        _patched_claude(side_effect=[_fabricating_reply(), _fabricating_reply()]) as create,
    ):
        result = await _publish_findings(company_id)

    assert create.call_count == 2
    assert result.published == []
    assert len(result.qualifying_fingerprints) == 1
    assert await _finding_count(company_id) == 0
    assert await _ai_profitability_alert_count(company_id) == 0
    assert UNGROUNDED_DROP_LOG_TEMPLATE % (
        project.project_id,
        _FABRICATED_LITERAL,
    ) in _logged_events(logs)


@pytest.mark.parametrize("fabricating_field", _AI_STRING_FIELDS)
async def test_every_ai_string_is_grounded_not_only_the_narrative(
    fabricating_field: str, tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A fabricated figure in ANY of the three AI strings blocks the finding."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_one_candidate_project(
        tenant_a_client, company_id, name=f"Fabricated {fabricating_field} 36"
    )

    replies = [_fabricating_reply(fabricating_field), _fabricating_reply(fabricating_field)]
    with _patched_claude(side_effect=replies) as create:
        drafts = await _draft_findings(company_id)

    assert create.call_count == 2
    assert drafts == [None]
    assert await _finding_count(company_id) == 0


async def test_ai_dismissal_publishes_nothing(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A dismissal ends the candidate on the first call: no validation, no retry, no row."""
    company_id = seed_two_tenants["tenant_a_id"]
    project = await _seed_one_candidate_project(
        tenant_a_client, company_id, name="Dismissed Project 36"
    )

    with (
        structlog.testing.capture_logs() as logs,
        _patched_claude(side_effect=[_dismissal_reply()]) as create,
    ):
        drafts = await _draft_findings(company_id)

    assert create.call_count == 1
    assert drafts == [None]
    assert await _finding_count(company_id) == 0
    assert DISMISSAL_LOG_TEMPLATE % (project.project_id, _DISMISSAL_REASON) in _logged_events(logs)


async def test_confirmed_finding_without_text_is_dropped(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A confirmed reply with empty strings is malformed, not a finding — the prompt
    reserves empty text for a dismissal, so publishing it would ship a blank card."""
    company_id = seed_two_tenants["tenant_a_id"]
    project = await _seed_one_candidate_project(
        tenant_a_client, company_id, name="Textless Project 36"
    )

    with (
        structlog.testing.capture_logs() as logs,
        _patched_claude(side_effect=[_textless_confirmation_reply()]) as create,
    ):
        drafts = await _draft_findings(company_id)

    assert create.call_count == 1
    assert drafts == [None]
    assert await _finding_count(company_id) == 0
    assert EMPTY_DRAFT_LOG_TEMPLATE % (project.project_id,) in _logged_events(logs)


async def test_only_candidates_reach_claude(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Eligible non-candidates never reach the API (D-02).

    Five eligible projects, two of them under-billed against an approved quote:
    only those two are candidates, so only two Claude calls may happen. Detection
    stays deterministic and the AI adds judgment and phrasing, not detection.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    for index in range(3):
        await _seed_analyzable_project(
            tenant_a_client, company_id, name=f"Eligible non-candidate {index}"
        )
    for index in range(2):
        await _seed_analyzable_project(
            tenant_a_client,
            company_id,
            name=f"Under-billed candidate {index}",
            quote_amount=_UNDER_BILLED_QUOTE_AMOUNT,
        )

    with _patched_claude(side_effect=[_grounded_reply(), _grounded_reply()]) as create:
        drafts = await _draft_findings(company_id)

    assert create.call_count == 2
    assert drafts == [_GROUNDED_DRAFT, _GROUNDED_DRAFT]


async def test_claude_failure_isolated_per_candidate(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """One candidate's Claude failure does not abort the rest of the company's run."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_cost_categories(company_id)
    for index in range(2):
        await _seed_analyzable_project(
            tenant_a_client,
            company_id,
            name=f"Isolation candidate {index}",
            quote_amount=_UNDER_BILLED_QUOTE_AMOUNT,
        )

    failure = ValueError("Empty response from Claude")
    with _patched_claude(side_effect=[failure, _grounded_reply()]) as create:
        drafts = await _draft_findings(company_id)

    assert create.call_count == 2
    assert len(drafts) == 2
    assert drafts.count(None) == 1
    assert _GROUNDED_DRAFT in drafts


# ---------------------------------------------------------------------------
# FINAI-01: the length contract, the D-10 nightly cap, and persistence
#
# The cap and the length rule are properties of the publish ORCHESTRATION, not of
# detection, so these fixtures hand publish_findings synthetic candidates against
# one seeded project instead of seeding a dozen slow ones. Each synthetic
# candidate carries a DISTINCT fingerprint: identical ones would upsert onto a
# single open row and make a cap assertion meaningless.
# ---------------------------------------------------------------------------

_SYNTHETIC_GROUNDED_PREFIX = "Synthetic candidate"
_SYNTHETIC_UNGROUNDED_PREFIX = "Ungrounded candidate"
_SYNTHETIC_COST = Decimal(_ANALYZABLE_COST_AMOUNT)
_SYNTHETIC_MARGIN = Decimal("-500.00")
_LENGTH_FILLER_CHARACTER = "x"

_CAPPED_CANDIDATE_COUNT = MAX_FINDINGS_PER_COMPANY_PER_NIGHT + 2
_UNGROUNDED_LEAD_COUNT = 3


def _synthetic_candidate(
    project_id: str, index: int, *, grounded: bool = True
) -> ProfitabilityCandidate:
    """One candidate the publish path can process without its own seeded project.

    The payload carries the same cost figure the grounded replies cite, and the
    project name tells the content-driven mock which reply this candidate earns.
    """
    prefix = _SYNTHETIC_GROUNDED_PREFIX if grounded else _SYNTHETIC_UNGROUNDED_PREFIX
    name = f"{prefix} {index}"
    signal = CandidateSignal(
        project_id=UUID(project_id),
        signal=SIGNAL_NEGATIVE_MARGIN,
        band=SEVERITY_BAND_CRITICAL,
        fingerprint=f"{project_id}:{SIGNAL_NEGATIVE_MARGIN}:{SEVERITY_BAND_CRITICAL}:{index}",
        negative_margin_dollars=_SYNTHETIC_MARGIN,
        margin_decline_points=None,
        quote_gap=None,
    )
    return ProfitabilityCandidate(
        candidate=signal,
        project_name=name,
        revenue_basis=_INVOICED_REVENUE_BASIS,
        labor_included=False,
        payload={"project_name": name, "cost": _SYNTHETIC_COST, "margin": _SYNTHETIC_MARGIN},
    )


def _reply_for_payload(*, messages: list[dict], **_kwargs: object) -> MagicMock:
    """Answer each candidate from its own payload rather than from call order.

    gather_with_concurrency interleaves calls under its semaphore, so a positional
    side_effect list could not say which candidate a reply belongs to.
    """
    if _SYNTHETIC_UNGROUNDED_PREFIX in messages[0]["content"]:
        return _fabricating_reply()
    return _grounded_reply()


def _sized_reply(field: str, length: int) -> MagicMock:
    """A grounded reply whose named AI string is exactly `length` characters.

    The filler carries no figures, so length is the only thing under test.
    """
    return _make_mock_anthropic_response(
        _finding_reply_data(**{field: _LENGTH_FILLER_CHARACTER * length})
    )


def test_prompt_and_database_state_the_same_length_bounds() -> None:
    """The bounds the model is told are the bounds the row is checked against.

    The service rejects against the DB constants, so a prompt that advertised a
    looser bound would turn every long finding into a silent drop.
    """
    assert NARRATIVE_MAX_CHARS == MAX_NARRATIVE_LENGTH
    assert CORRECTIVE_ACTION_MAX_CHARS == MAX_CORRECTIVE_ACTION_LENGTH
    assert ALERT_SUMMARY_MAX_CHARS == MAX_ALERT_SUMMARY_LENGTH


async def test_over_length_draft_is_rejected_not_truncated(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """The SERVICE half of the length contract: over-length text is dropped whole.

    Plan 36-01 owns the DATABASE half under test_alert_summary_db_length_check —
    two functions of one name in one module would trip ruff F811 and shadow one.
    A clipped grounded sentence can lose the very figure that justifies it, so
    there is no shortening anywhere on this path.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    candidates = [_synthetic_candidate(project_id, 0)]

    over_length_replies = (
        _sized_reply("alert_summary", MAX_ALERT_SUMMARY_LENGTH + 1),
        _sized_reply("corrective_action", MAX_CORRECTIVE_ACTION_LENGTH + 1),
        _sized_reply("narrative", MAX_NARRATIVE_LENGTH + 1),
    )
    for reply in over_length_replies:
        with structlog.testing.capture_logs() as logs, _patched_claude(side_effect=[reply]):
            result = await _publish_findings(company_id, candidates)

        assert result.published == []
        assert await _finding_count(company_id) == 0
        assert OVER_LENGTH_DROP_LOG_TEMPLATE % (project_id,) in _logged_events(logs)

    with _patched_claude(side_effect=[_sized_reply("alert_summary", MAX_ALERT_SUMMARY_LENGTH)]):
        at_the_bound = await _publish_findings(company_id, candidates)

    assert len(at_the_bound.published) == 1
    rows = await _open_findings(company_id)
    assert len(rows) == 1
    assert len(rows[0]["alert_summary"]) == MAX_ALERT_SUMMARY_LENGTH


async def test_per_company_findings_cap(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Twelve grounded candidates publish exactly ten findings, and both drops are logged.

    The two capped candidates still qualify tonight, so all twelve fingerprints
    stay in the D-06 keep-set.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    candidates = [
        _synthetic_candidate(project_id, index) for index in range(_CAPPED_CANDIDATE_COUNT)
    ]

    with (
        structlog.testing.capture_logs() as logs,
        _patched_claude(side_effect=_reply_for_payload) as create,
    ):
        result = await _publish_findings(company_id, candidates)

    assert create.call_count == _CAPPED_CANDIDATE_COUNT
    assert len(result.published) == MAX_FINDINGS_PER_COMPANY_PER_NIGHT
    assert await _finding_count(company_id) == MAX_FINDINGS_PER_COMPANY_PER_NIGHT
    assert len(result.qualifying_fingerprints) == _CAPPED_CANDIDATE_COUNT

    cap_line = CAP_DROP_LOG_TEMPLATE % (project_id, MAX_FINDINGS_PER_COMPANY_PER_NIGHT)
    expected_drops = _CAPPED_CANDIDATE_COUNT - MAX_FINDINGS_PER_COMPANY_PER_NIGHT
    assert _logged_events(logs).count(cap_line) == expected_drops


async def test_findings_cap_counted_after_validation(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Three ungrounded candidates ahead of ten grounded ones still publish ten findings.

    Counting the cap before validation would spend three of its ten slots on
    findings that were never published, leaving seven.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client)
    ungrounded = [
        _synthetic_candidate(project_id, index, grounded=False)
        for index in range(_UNGROUNDED_LEAD_COUNT)
    ]
    grounded = [
        _synthetic_candidate(project_id, _UNGROUNDED_LEAD_COUNT + index)
        for index in range(MAX_FINDINGS_PER_COMPANY_PER_NIGHT)
    ]

    with (
        structlog.testing.capture_logs() as logs,
        _patched_claude(side_effect=_reply_for_payload) as create,
    ):
        result = await _publish_findings(company_id, [*ungrounded, *grounded])

    assert len(result.published) == MAX_FINDINGS_PER_COMPANY_PER_NIGHT
    assert await _finding_count(company_id) == MAX_FINDINGS_PER_COMPANY_PER_NIGHT
    assert len(result.qualifying_fingerprints) == len(ungrounded) + len(grounded)

    ungrounded_calls = _UNGROUNDED_LEAD_COUNT * (GROUNDING_RETRY_LIMIT + 1)
    assert create.call_count == MAX_FINDINGS_PER_COMPANY_PER_NIGHT + ungrounded_calls

    drop_line = UNGROUNDED_DROP_LOG_TEMPLATE % (project_id, _FABRICATED_LITERAL)
    assert _logged_events(logs).count(drop_line) == _UNGROUNDED_LEAD_COUNT


async def test_persisted_payload_matches_the_grounded_payload(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """The row stores the exact payload the finding was validated against.

    Also pins the six PublishedFinding fields plan 36-09 reads, resolved here in
    the request session so the alerting step never re-reads the ORM.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project = await _seed_one_candidate_project(
        tenant_a_client, company_id, name="Published Project 36"
    )

    with _patched_claude(side_effect=[_grounded_reply()]):
        result = await _publish_findings(company_id)

    assert len(result.published) == 1
    published = result.published[0]
    assert published.project_id == UUID(project.project_id)
    assert published.alert_summary == _GROUNDED_ALERT_SUMMARY
    assert published.corrective_action == _GROUNDED_CORRECTIVE_ACTION
    assert result.qualifying_fingerprints == [published.fingerprint]

    rows = await _open_findings(company_id)
    assert len(rows) == 1
    assert rows[0]["id"] == published.finding_id
    assert rows[0]["fingerprint"] == published.fingerprint
    assert rows[0]["severity_band"] == published.severity_band
    assert rows[0]["signal"] == SIGNAL_QUOTE_GAP
    assert rows[0]["narrative"] == _GROUNDED_NARRATIVE
    assert rows[0]["revenue_basis"] == _INVOICED_REVENUE_BASIS
    assert rows[0]["alerted_at"] is None

    stored_payload = await _stored_payload(company_id, published.finding_id)
    assert set(stored_payload) == _EXPECTED_PAYLOAD_FIELDS
    assert Decimal(stored_payload["cost"]) == Decimal(_ANALYZABLE_COST_AMOUNT)
    assert Decimal(stored_payload["quote_gap_points"]) > 0
    assert stored_payload["labor_basis"] == LABOR_BASIS_UNBURDENED


# ---------------------------------------------------------------------------
# FINAI-02: the alert lifecycle — resolve stale fingerprints, claim once, alert
#
# One condition alerts ONCE for as long as it stays true. A second alert is only
# allowed when it worsens into a different band (the band is inside the
# fingerprint, so that is a different fingerprint) or when it clears and later
# recurs (D-06).
#
# These fixtures start in the WARNING band with room to worsen: the default
# analyzable project is already critical on its first night, which leaves nowhere
# to escalate to.
# ---------------------------------------------------------------------------

_FOURTH_NIGHT = date(2026, 7, 4)
_IDENTICAL_NIGHTS = (_FIRST_NIGHT, _SECOND_NIGHT, _THIRD_NIGHT)

_PAUSED_PROJECT_STATUS = "on_hold"

# 1,200 of cost against 10,000 invoiced under a 20,000 approved quote at the same
# job anchor: billed margin 88.0% against a quote-implied 94.0% is a 6.0-point
# gap — over QUOTE_IMPLIED_GAP_POINTS, under CRITICAL_QUOTE_GAP_POINTS. Adding
# 1,800 more cost takes the gap to 15.0 points (70.0% against 85.0%): the
# critical band, the SAME signal, and a margin still comfortably positive so the
# negative-margin signal cannot pre-empt the comparison.
_LIFECYCLE_INVOICE_AMOUNT = "10000.00"
_LIFECYCLE_QUOTE_AMOUNT = "20000.00"
_LIFECYCLE_WARNING_COST = "1200.00"
_LIFECYCLE_WORSENING_COST = "1800.00"

# The invoiced revenue — present in every lifecycle payload at BOTH cost levels,
# so one reply stays grounded across a worsening band.
_LIFECYCLE_LITERAL = "$10,000"
_LIFECYCLE_NARRATIVE = (
    f"Billed revenue of {_LIFECYCLE_LITERAL} at this job anchor sits below what the approved "
    "quote implies for the same work."
)
_LIFECYCLE_CORRECTIVE_ACTION = (
    f"Rebill the approved scope still outstanding — only {_LIFECYCLE_LITERAL} is invoiced."
)
_LIFECYCLE_ALERT_SUMMARY = (
    f"Billed margin trails the approved quote on {_LIFECYCLE_LITERAL} billed."
)

_ALL_FINDINGS_SQL = (
    "SELECT id, project_id, severity_band, fingerprint, alert_summary, corrective_action, "
    "dashboard_alert_id, alerted_at, resolved_at, found_on, last_confirmed_on "
    "FROM ai_profitability_findings WHERE deleted_at IS NULL ORDER BY created_at"
)

_AI_PROFITABILITY_ALERTS_SQL = (
    "SELECT id, project_id, severity, alert_type, days_behind, impact_text, remediation_text, "
    "affected_scope_ids, rescheduling_payload, rescheduling_accepted "
    "FROM dashboard_alerts WHERE alert_type = :alert_type AND deleted_at IS NULL "
    "ORDER BY created_at"
)


async def _all_findings(company_id: str) -> list[dict]:
    """Every live finding row for a company, resolved ones included, oldest first."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(text(_ALL_FINDINGS_SQL))
        return [dict(row) for row in result.mappings()]


async def _ai_profitability_alerts(company_id: str) -> list[dict]:
    """Every ai_profitability dashboard alert for a company, oldest first."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        result = await session.execute(
            text(_AI_PROFITABILITY_ALERTS_SQL), {"alert_type": AI_PROFITABILITY_ALERT_TYPE}
        )
        return [dict(row) for row in result.mappings()]


async def _analyze_company(company_id: str, target_date: date) -> None:
    """Drive one whole nightly run for one company under its own RLS context.

    The scheduler-path convention: the service never commits, its caller does.
    PostgreSQL rejects a parameterized SET LOCAL, hence the f-string.
    """
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await ProfitabilityService(session).analyze_company(
            company_id=UUID(company_id), target_date=target_date
        )
        await session.commit()


def _lifecycle_reply() -> MagicMock:
    """A grounded reply citing only the invoiced revenue, which survives a cost change."""
    return _make_mock_anthropic_response(
        _finding_reply_data(
            narrative=_LIFECYCLE_NARRATIVE,
            corrective_action=_LIFECYCLE_CORRECTIVE_ACTION,
            alert_summary=_LIFECYCLE_ALERT_SUMMARY,
        )
    )


async def _seed_lifecycle_project(
    client: AsyncClient, company_id: str, *, name: str
) -> _AnalyzableProject:
    """Seed one quote-gap candidate sitting in the WARNING band with room to worsen."""
    await _seed_cost_categories(company_id)
    return await _seed_analyzable_project(
        client,
        company_id,
        name=name,
        cost_amount=_LIFECYCLE_WARNING_COST,
        invoice_amount=_LIFECYCLE_INVOICE_AMOUNT,
        quote_amount=_LIFECYCLE_QUOTE_AMOUNT,
    )


async def _worsen_into_critical_band(client: AsyncClient, company_id: str, job_id: str) -> None:
    """Add cost at the same anchor until the quote-implied gap reaches the critical band.

    Cost, never a second quote: the invoice moved this job out of 'quote' status,
    so the quote endpoint would reject one with a 409.
    """
    await _add_cost_entry(
        client,
        _pm_headers(company_id),
        job_id=job_id,
        category_id=await _category_id(company_id, _MATERIALS_CATEGORY),
        amount=_LIFECYCLE_WORSENING_COST,
        incurred_date=_days_ago(_MONEY_SEED_DAYS_AGO).date(),
    )


async def _pause_project(client: AsyncClient, project_id: str) -> None:
    """Move a project out of 'active' so D-01 stops analyzing it — the condition clears."""
    resp = await client.patch(
        f"{_PROJECTS_URL}{project_id}", json={"status": _PAUSED_PROJECT_STATUS}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == _PAUSED_PROJECT_STATUS


async def test_fingerprint_alerts_exactly_once_across_three_runs(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """KEYSTONE 2: one alert across three identical nights; a worsened band re-fires.

    Nights 1-3 restate the same fingerprint, so the row's text and
    last_confirmed_on move while alerted_at and found_on do not, and exactly one
    DashboardAlert exists. Night 4 worsens the gap into the critical band — a
    different fingerprint — so the warning row resolves in the SAME run and the
    critical row inserts fresh, claims its own alert and fires.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project = await _seed_lifecycle_project(tenant_a_client, company_id, name="Eroding Project 36")

    for night in _IDENTICAL_NIGHTS:
        with _patched_claude(side_effect=[_lifecycle_reply()]):
            await _analyze_company(company_id, night)

    findings = await _all_findings(company_id)
    assert len(findings) == 1
    warning = findings[0]
    assert warning["severity_band"] == SEVERITY_BAND_WARNING
    assert warning["found_on"] == _FIRST_NIGHT
    assert warning["last_confirmed_on"] == _THIRD_NIGHT
    assert warning["resolved_at"] is None
    assert warning["alerted_at"] is not None

    alerts = await _ai_profitability_alerts(company_id)
    assert len(alerts) == 1
    assert warning["dashboard_alert_id"] == alerts[0]["id"]
    assert alerts[0]["severity"] == SEVERITY_BAND_WARNING

    await _worsen_into_critical_band(tenant_a_client, company_id, project.job_id)
    with _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _FOURTH_NIGHT)

    findings = await _all_findings(company_id)
    assert len(findings) == 2
    resolved, escalated = findings
    assert resolved["id"] == warning["id"]
    assert resolved["resolved_at"] is not None
    assert escalated["severity_band"] == SEVERITY_BAND_CRITICAL
    assert escalated["fingerprint"] != resolved["fingerprint"]
    assert escalated["resolved_at"] is None
    assert escalated["alerted_at"] is not None
    assert escalated["found_on"] == _FOURTH_NIGHT

    alerts = await _ai_profitability_alerts(company_id)
    assert len(alerts) == 2
    assert alerts[1]["severity"] == SEVERITY_BAND_CRITICAL
    assert escalated["dashboard_alert_id"] == alerts[1]["id"]


async def test_cleared_then_recurring_condition_realerts(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A condition that clears and later recurs fires a SECOND alert (D-06).

    The recurrence carries the SAME fingerprint as the original, which is exactly
    why it needs the resolve-then-reinsert lifecycle rather than the upsert: the
    resolved row is invisible to the open-row unique index, so a fresh row lands
    with alerted_at NULL and earns its own claim.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project = await _seed_lifecycle_project(
        tenant_a_client, company_id, name="Recurring Project 36"
    )

    with _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _FIRST_NIGHT)
    original = (await _all_findings(company_id))[0]
    assert await _ai_profitability_alert_count(company_id) == 1

    await _pause_project(tenant_a_client, project.project_id)
    with _patched_claude(side_effect=[]) as create:
        await _analyze_company(company_id, _SECOND_NIGHT)

    assert create.call_count == 0
    cleared = await _all_findings(company_id)
    assert len(cleared) == 1
    assert cleared[0]["resolved_at"] is not None
    assert await _ai_profitability_alert_count(company_id) == 1

    await _activate_project(tenant_a_client, project.project_id)
    with _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _THIRD_NIGHT)

    recurred = await _all_findings(company_id)
    assert len(recurred) == 2
    assert recurred[1]["fingerprint"] == original["fingerprint"]
    assert recurred[1]["id"] != original["id"]
    assert recurred[1]["found_on"] == _THIRD_NIGHT
    assert recurred[1]["alerted_at"] is not None
    assert await _ai_profitability_alert_count(company_id) == 2


async def test_same_day_rerun_is_idempotent(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Two runs on the same target_date leave one finding and one alert."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_lifecycle_project(tenant_a_client, company_id, name="Re-run Project 36")

    for _ in range(2):
        with _patched_claude(side_effect=[_lifecycle_reply()]):
            await _analyze_company(company_id, _FIRST_NIGHT)

    findings = await _all_findings(company_id)
    assert len(findings) == 1
    assert findings[0]["resolved_at"] is None
    assert findings[0]["found_on"] == _FIRST_NIGHT
    assert findings[0]["last_confirmed_on"] == _FIRST_NIGHT
    assert await _ai_profitability_alert_count(company_id) == 1


async def test_transient_claude_failure_does_not_resolve_or_realert(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """The D-06 keep-set guard: a failed API call must never resolve a live finding.

    Night 2's Claude call raises against unchanged data, so the candidate still
    QUALIFIES but publishes nothing. Built from `published` instead of
    `qualifying_fingerprints`, the keep-set would be empty, the still-true finding
    would resolve, and night 3 would insert a fresh unalerted row and fire a
    SECOND alert for a condition that never cleared.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_lifecycle_project(tenant_a_client, company_id, name="Transient Project 36")

    with _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _FIRST_NIGHT)
    original = (await _all_findings(company_id))[0]

    with _patched_claude(side_effect=RuntimeError("Anthropic API unavailable")) as create:
        await _analyze_company(company_id, _SECOND_NIGHT)

    # A raised transport error is not a grounding failure, so it consumes no D-05
    # retry: the candidate is abandoned on its first and only call.
    assert create.call_count == 1
    after_failure = await _all_findings(company_id)
    assert len(after_failure) == 1
    assert after_failure[0]["id"] == original["id"]
    assert after_failure[0]["resolved_at"] is None
    assert after_failure[0]["last_confirmed_on"] == _FIRST_NIGHT
    assert await _ai_profitability_alert_count(company_id) == 1

    with _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _THIRD_NIGHT)

    recovered = await _all_findings(company_id)
    assert len(recovered) == 1
    assert recovered[0]["id"] == original["id"]
    assert recovered[0]["resolved_at"] is None
    assert recovered[0]["last_confirmed_on"] == _THIRD_NIGHT
    assert await _ai_profitability_alert_count(company_id) == 1


async def test_alert_frame_strings_are_exact(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """The two locked frame prefixes are byte-exact and the AI prose is asserted by
    reference, never retyped — the UI-SPEC's one testable half of an AI string.

    The suppression fields are asserted too: with days_behind, affected_scope_ids
    and both rescheduling columns empty, AlertPanel renders the finding without a
    schedule line and without the Accept/Dismiss controls, which is why it needs
    no code change for this alert type.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project = await _seed_lifecycle_project(tenant_a_client, company_id, name="Framed Project 36")

    with _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _FIRST_NIGHT)

    alerts = await _ai_profitability_alerts(company_id)
    assert len(alerts) == 1
    alert = alerts[0]
    assert alert["impact_text"].startswith(AI_FINDING_PREFIX)
    assert alert["impact_text"].removeprefix(AI_FINDING_PREFIX) == _LIFECYCLE_ALERT_SUMMARY
    assert alert["remediation_text"].startswith(SUGGESTED_ACTION_PREFIX)
    assert (
        alert["remediation_text"].removeprefix(SUGGESTED_ACTION_PREFIX)
        == _LIFECYCLE_CORRECTIVE_ACTION
    )
    assert alert["alert_type"] == AI_PROFITABILITY_ALERT_TYPE
    assert alert["severity"] == SEVERITY_BAND_WARNING
    assert alert["project_id"] == UUID(project.project_id)
    assert alert["days_behind"] is None
    assert alert["affected_scope_ids"] == []
    assert alert["rescheduling_payload"] is None
    assert alert["rescheduling_accepted"] is None


def test_push_title_map_covers_both_bands() -> None:
    """One map per concept: the band's push title is not spelled a second time.

    The UI-SPEC rule is that a condition never carries two names, so the chip
    label, the push title and the DashboardAlert severity all read from here.
    """
    assert PUSH_TITLE_BY_BAND == {
        SEVERITY_BAND_WARNING: "Margin warning",
        SEVERITY_BAND_CRITICAL: "Margin critical",
    }


# ---------------------------------------------------------------------------
# FINAI-02: FCM dispatch to the LIVE finance.view holder set (D-07)
#
# Recipients are never a role-name list: a company can move finance.view onto any
# role through the shipped permission editor, and the push has to follow that
# without a code change. Patch target is the NotificationService method (the
# Phase 34 precedent), so the whole scheduling path runs for real.
# ---------------------------------------------------------------------------

_SEND_PROFITABILITY_PUSH_TARGET = (
    "app.features.notifications.service.NotificationService.send_profitability_finding_notification"
)

_FINANCE_VIEW_PERMISSION_KEY = "finance.view"
_CONTRACTOR_ROLE = "contractor"

_ASSIGN_ROLE_SQL = (
    "INSERT INTO user_roles (company_id, user_id, role) "
    "VALUES (CAST(:company_id AS uuid), CAST(:user_id AS uuid), :role)"
)

_EXPECTED_PUSH_DATA_KEYS = frozenset(
    {"type", "alert_type", "alert_id", "finding_id", "project_id", "severity"}
)

_PUSH_FLUSH_ATTEMPTS = 40
_PUSH_FLUSH_INTERVAL_SECONDS = 0.05


@dataclass(frozen=True)
class _RoleHolders:
    """One user per role, so a recipient set can be asserted by identity."""

    owner_id: str
    project_manager_id: str
    contractor_id: str


async def _assign_role(company_id: str, user_id: str, role: str) -> None:
    """Insert a user_roles row directly — no role-assignment endpoint exists."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await session.execute(
            text(_ASSIGN_ROLE_SQL),
            {"company_id": company_id, "user_id": user_id, "role": role},
        )
        await session.commit()


async def _seed_role_holders(client: AsyncClient, company_id: str) -> _RoleHolders:
    """Create one owner, one project manager and one contractor for this company."""
    holders = _RoleHolders(
        owner_id=await _create_user(client, f"owner-{uuid4().hex[:8]}@tenant-a.com"),
        project_manager_id=await _create_user(client, f"pm-{uuid4().hex[:8]}@tenant-a.com"),
        contractor_id=await _create_user(client, f"crew-{uuid4().hex[:8]}@tenant-a.com"),
    )
    await _assign_role(company_id, holders.owner_id, "owner")
    await _assign_role(company_id, holders.project_manager_id, "project_manager")
    await _assign_role(company_id, holders.contractor_id, _CONTRACTOR_ROLE)
    return holders


async def _finance_view_holders(company_id: str) -> set[str]:
    """The live finance.view holder set, read through the shipped RBAC repository."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        holders = await RbacRepository(session).user_ids_with_permission(
            UUID(company_id), _FINANCE_VIEW_PERMISSION_KEY
        )
        return {str(user_id) for user_id in holders}


async def _grant_finance_view(company_id: str, role: str) -> None:
    """Add finance.view to one role the way the shipped permission editor does."""
    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        repository = RbacRepository(session)
        granted = [*(await repository.get_map()).get(role, []), _FINANCE_VIEW_PERMISSION_KEY]
        await repository.set_role(UUID(company_id), role, granted)
        await session.commit()


@contextlib.contextmanager
def _patched_profitability_push() -> Iterator[list[dict]]:
    """Capture every profitability push instead of dispatching one."""
    calls: list[dict] = []

    async def _capture(**kwargs: object) -> None:
        calls.append(kwargs)

    with patch(_SEND_PROFITABILITY_PUSH_TARGET, side_effect=_capture):
        yield calls


async def _flush_background_pushes(calls: list, expected: int = 1) -> None:
    """Yield to the event loop until the fire-and-forget push tasks have run.

    COPIED from test_phase_34_e2e.py per the self-contained-test-file convention.
    """
    for _ in range(_PUSH_FLUSH_ATTEMPTS):
        if len(calls) >= expected:
            return
        await asyncio.sleep(_PUSH_FLUSH_INTERVAL_SECONDS)


async def test_push_recipients_follow_live_permission_matrix(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """Recipients equal the live finance.view holder set, and follow a new grant.

    The second run also pins the critical band's push title, which is why it
    worsens the condition instead of re-running the same one: a restated
    fingerprint never re-alerts, so it would never push either.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    holders = await _seed_role_holders(tenant_a_client, company_id)
    project = await _seed_lifecycle_project(
        tenant_a_client, company_id, name="Recipients Project 36"
    )

    with _patched_profitability_push() as calls, _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _FIRST_NIGHT)
        await _flush_background_pushes(calls)

    assert len(calls) == 1
    recipients = {str(user_id) for user_id in calls[0]["recipient_ids"]}
    assert recipients == await _finance_view_holders(company_id)
    assert holders.owner_id in recipients
    assert holders.project_manager_id in recipients
    assert holders.contractor_id not in recipients
    assert seed_two_tenants["tenant_a_user_id"] not in recipients  # admin: no finance.view

    alerts = await _ai_profitability_alerts(company_id)
    assert calls[0]["title"] == PUSH_TITLE_BY_BAND[SEVERITY_BAND_WARNING]
    assert calls[0]["body"] == alerts[0]["impact_text"]

    await _grant_finance_view(company_id, _CONTRACTOR_ROLE)
    await _worsen_into_critical_band(tenant_a_client, company_id, project.job_id)

    with _patched_profitability_push() as calls, _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _SECOND_NIGHT)
        await _flush_background_pushes(calls)

    assert len(calls) == 1
    widened = {str(user_id) for user_id in calls[0]["recipient_ids"]}
    assert widened == await _finance_view_holders(company_id)
    assert holders.contractor_id in widened
    assert calls[0]["title"] == PUSH_TITLE_BY_BAND[SEVERITY_BAND_CRITICAL]
    assert calls[0]["body"] == (await _ai_profitability_alerts(company_id))[1]["impact_text"]


async def test_push_data_values_are_all_strings(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """The data payload carries the six documented keys, every value a str (FCM)."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_role_holders(tenant_a_client, company_id)
    project = await _seed_lifecycle_project(
        tenant_a_client, company_id, name="Push Data Project 36"
    )

    with _patched_profitability_push() as calls, _patched_claude(side_effect=[_lifecycle_reply()]):
        await _analyze_company(company_id, _FIRST_NIGHT)
        await _flush_background_pushes(calls)

    assert len(calls) == 1
    data = calls[0]["data"]
    assert all(isinstance(value, str) for value in data.values())
    assert set(data) == _EXPECTED_PUSH_DATA_KEYS
    assert data["type"] == _PROFITABILITY_PUSH_TYPE
    assert data["alert_type"] == AI_PROFITABILITY_ALERT_TYPE
    assert data["severity"] == SEVERITY_BAND_WARNING
    assert data["project_id"] == project.project_id

    finding = (await _all_findings(company_id))[0]
    assert data["finding_id"] == str(finding["id"])
    assert data["alert_id"] == str(finding["dashboard_alert_id"])


async def test_push_failure_does_not_break_analysis(
    tenant_a_client: AsyncClient, seed_two_tenants: dict
) -> None:
    """A raising push is swallowed inside its own task — the finding and alert persist."""
    company_id = seed_two_tenants["tenant_a_id"]
    await _seed_role_holders(tenant_a_client, company_id)
    await _seed_lifecycle_project(tenant_a_client, company_id, name="Push Failure Project 36")
    attempts: list[dict] = []

    async def _explode(**kwargs: object) -> None:
        attempts.append(kwargs)
        raise RuntimeError("FCM unavailable")

    with (
        patch(_SEND_PROFITABILITY_PUSH_TARGET, side_effect=_explode),
        _patched_claude(side_effect=[_lifecycle_reply()]),
    ):
        await _analyze_company(company_id, _FIRST_NIGHT)
        await _flush_background_pushes(attempts)

    assert len(attempts) == 1
    findings = await _all_findings(company_id)
    assert len(findings) == 1
    assert findings[0]["dashboard_alert_id"] is not None
    assert await _ai_profitability_alert_count(company_id) == 1
