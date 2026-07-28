"""Phase 30 E2E anchor — financial schema foundation and RBAC audit.

This file is the shared phase E2E scaffold: a reusable JWT-minting token
helper plus the RBAC integration tests that pass with only the
permissions.py catalog/derivation change (no migration, no new endpoints
needed for this plan). Later plans (02/03/04) add their own test functions
to this same file as the cost/budget schema and endpoints land.
"""

import json
from datetime import date
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from sqlalchemy import select, text

from app.core.database import async_session_factory
from app.core.finance_scrub import FINANCE_FIELD_NAMES
from app.core.security import create_access_token
from app.features.checklists.service import ChecklistService
from app.features.dashboard.models import DashboardAlert
from app.features.dashboard.service import DashboardService
from app.features.finance.models import Budget, CostCategory, CostEntry

FINANCE_KEYS = {"finance.view", "finance.manage", "finance.rates.manage"}


def _token(company_id: str, roles: list[str]) -> str:
    """Mint an access token for a synthetic user with the given roles."""
    return create_access_token(uuid4(), UUID(company_id), roles)


@pytest.mark.asyncio
async def test_new_company_seeded_with_finance_defaults(async_client, seed_two_tenants):
    """A freshly seeded company grants finance.* to project_manager and owner, never admin."""
    company_id = seed_two_tenants["tenant_a_id"]

    pm_headers = {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}
    pm_resp = await async_client.get("/api/v1/me/permissions", headers=pm_headers)
    assert pm_resp.status_code == 200, pm_resp.text
    assert set(pm_resp.json()["permissions"]) >= FINANCE_KEYS

    owner_headers = {"Authorization": f"Bearer {_token(company_id, ['owner'])}"}
    owner_resp = await async_client.get("/api/v1/me/permissions", headers=owner_headers)
    assert owner_resp.status_code == 200, owner_resp.text
    assert set(owner_resp.json()["permissions"]) >= FINANCE_KEYS

    admin_headers = {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}
    admin_resp = await async_client.get("/api/v1/me/permissions", headers=admin_headers)
    assert admin_resp.status_code == 200, admin_resp.text
    assert FINANCE_KEYS.isdisjoint(set(admin_resp.json()["permissions"]))


@pytest.mark.asyncio
async def test_admin_never_gets_finance_via_defaults(async_client, seed_two_tenants):
    """FINSEC-03 integration counterpart to the unit test: admin's live effective
    permissions (via the API, reading the seeded per-company matrix) never contain
    a finance.* key.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    admin_headers = {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}

    resp = await async_client.get("/api/v1/me/permissions", headers=admin_headers)
    assert resp.status_code == 200, resp.text
    assert FINANCE_KEYS.isdisjoint(set(resp.json()["permissions"]))


@pytest.mark.asyncio
async def test_owner_can_grant_finance_to_custom_role(
    async_client, tenant_a_client, seed_two_tenants
):
    """FINSEC-02: an owner can grant finance.view to a non-default role (gc) via
    the existing matrix endpoint, and it takes effect immediately for a gc user —
    without also granting finance.manage.
    """
    company_id = seed_two_tenants["tenant_a_id"]

    current = await tenant_a_client.get("/api/v1/roles/permissions")
    assert current.status_code == 200, current.text
    gc_permissions = list(current.json()["roles"]["gc"])
    assert "finance.view" not in gc_permissions

    updated = [*gc_permissions, "finance.view"]
    put_resp = await tenant_a_client.put(
        "/api/v1/roles/gc/permissions",
        json={"permissions": updated},
    )
    assert put_resp.status_code == 200, put_resp.text

    gc_headers = {"Authorization": f"Bearer {_token(company_id, ['gc'])}"}
    gc_resp = await async_client.get("/api/v1/me/permissions", headers=gc_headers)
    assert gc_resp.status_code == 200, gc_resp.text
    gc_effective = set(gc_resp.json()["permissions"])

    assert "finance.view" in gc_effective
    assert "finance.manage" not in gc_effective


# ---------------------------------------------------------------------------
# Task 1: migration-effect tests — PM backfill, category seed, RLS isolation.
# These exercise the exact SQL migration 0032 runs (raw text(), not the ORM
# layer) against tenant context set via SET LOCAL, mirroring scripts/seed_data.py.
# ---------------------------------------------------------------------------

_FINANCE_BACKFILL_SQL = (
    "UPDATE company_role_permissions "
    'SET permissions = permissions || \'["finance.view","finance.manage",'
    '"finance.rates.manage"]\'::jsonb, '
    "updated_at = now() "
    "WHERE role = 'project_manager' "
    "AND NOT (permissions @> '[\"finance.view\"]'::jsonb)"
)

_COST_CATEGORY_SEED_SQL = (
    "INSERT INTO cost_categories (company_id, name, is_system) "
    "SELECT CAST(:company_id AS uuid), v.name, true "
    "FROM (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name) "
    "ON CONFLICT (company_id, name) DO NOTHING"
)


async def _create_company(session, name: str) -> str:
    """Insert a bare company row (companies carries no RLS) — simulates a
    company that already existed before migration 0032 ran.
    """
    result = await session.execute(
        text("INSERT INTO companies (id, name) VALUES (gen_random_uuid(), :name) RETURNING id"),
        {"name": name},
    )
    return str(result.scalar_one())


async def _seed_role_permissions(
    session, company_id: str, role: str, permissions: list[str]
) -> None:
    """Insert a company_role_permissions row directly, bypassing RbacRepository,
    to simulate a pre-migration company's stored permission list.
    """
    await session.execute(
        text(
            "INSERT INTO company_role_permissions (company_id, role, permissions) "
            "VALUES (CAST(:company_id AS uuid), :role, CAST(:permissions AS jsonb))"
        ),
        {"company_id": company_id, "role": role, "permissions": json.dumps(permissions)},
    )


async def _get_role_permissions(session, company_id: str, role: str) -> list[str]:
    result = await session.execute(
        text(
            "SELECT permissions FROM company_role_permissions "
            "WHERE company_id = CAST(:company_id AS uuid) AND role = :role"
        ),
        {"company_id": company_id, "role": role},
    )
    row = result.first()
    assert row is not None, f"no company_role_permissions row for role={role}"
    return list(row[0])


async def _run_pm_finance_backfill(session, company_id: str) -> None:
    """Execute the exact guarded UPDATE migration 0032 uses to backfill PM rows."""
    await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
    await session.execute(text(_FINANCE_BACKFILL_SQL))


async def _seed_cost_categories(session, company_id: str) -> None:
    """Execute the same per-company seed INSERT migration 0032 uses for
    cost_categories, scoped to one company via SET LOCAL + bind param (RLS is
    already enabled on this table post-migration, unlike the pre-RLS migration run).
    """
    await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
    await session.execute(text(_COST_CATEGORY_SEED_SQL), {"company_id": company_id})


@pytest.mark.asyncio
async def test_existing_company_backfilled_with_finance_defaults():
    """FINSEC-01: migration 0032's guarded PM backfill UPDATE reaches an
    existing (pre-migration) company's project_manager row and leaves admin
    untouched; re-running the same guarded UPDATE a second time is a no-op.
    """
    pre_finance_pm = ["projects.view", "projects.create", "jobs.view", "tasks.view"]
    admin_permissions = ["users.view", "users.create", "jobs.view"]

    async with async_session_factory() as session:
        company_id = await _create_company(session, "Pre-Migration Co")
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        await _seed_role_permissions(session, company_id, "project_manager", pre_finance_pm)
        await _seed_role_permissions(session, company_id, "admin", admin_permissions)
        await session.commit()

    async with async_session_factory() as session:
        await _run_pm_finance_backfill(session, company_id)
        await session.commit()

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        pm_after_first = await _get_role_permissions(session, company_id, "project_manager")
        admin_after_first = await _get_role_permissions(session, company_id, "admin")

    assert set(pm_after_first) == set(pre_finance_pm) | FINANCE_KEYS
    assert admin_after_first == admin_permissions, "backfill must not touch admin rows"

    # Idempotency: re-running the same guarded UPDATE changes nothing further.
    async with async_session_factory() as session:
        await _run_pm_finance_backfill(session, company_id)
        await session.commit()

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        pm_after_second = await _get_role_permissions(session, company_id, "project_manager")
        admin_after_second = await _get_role_permissions(session, company_id, "admin")

    assert set(pm_after_second) == set(pm_after_first)
    assert admin_after_second == admin_permissions


@pytest.mark.asyncio
async def test_cost_categories_seeded_per_company(seed_two_tenants):
    """FINSEC-01: every company ends up with exactly 4 protected system cost
    categories, and re-running the seed INSERT is idempotent.
    """
    company_id = seed_two_tenants["tenant_a_id"]

    async with async_session_factory() as session:
        await _seed_cost_categories(session, company_id)
        await session.commit()

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        rows = (
            (
                await session.execute(
                    select(CostCategory).where(CostCategory.company_id == company_id)
                )
            )
            .scalars()
            .all()
        )

    assert len(rows) == 4
    assert all(row.is_system for row in rows)
    assert {row.name for row in rows} == {"labor", "materials", "subcontractor", "other"}

    async with async_session_factory() as session:
        await _seed_cost_categories(session, company_id)
        await session.commit()

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        rows_again = (
            (
                await session.execute(
                    select(CostCategory).where(CostCategory.company_id == company_id)
                )
            )
            .scalars()
            .all()
        )

    assert len(rows_again) == 4, "re-seeding must be idempotent (ON CONFLICT DO NOTHING)"


@pytest.mark.asyncio
async def test_cost_entry_rls_isolation(seed_two_tenants):
    """FINSEC-01: tenant B cannot read tenant A's cost_entries or budgets rows —
    RLS isolation on the new financial tables, mirroring SKILL.md's convention.
    """
    tenant_a_id = seed_two_tenants["tenant_a_id"]
    tenant_b_id = seed_two_tenants["tenant_b_id"]

    async with async_session_factory() as session:
        await _seed_cost_categories(session, tenant_a_id)
        await session.commit()

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{tenant_a_id}'"))
        materials_category = (
            await session.execute(
                select(CostCategory).where(
                    CostCategory.company_id == tenant_a_id,
                    CostCategory.name == "materials",
                )
            )
        ).scalar_one()

        cost_entry = CostEntry(
            company_id=tenant_a_id,
            category_id=materials_category.id,
            amount=Decimal("125.50"),
            incurred_date=date.today(),
        )
        budget = Budget(company_id=tenant_a_id, total=Decimal("5000.00"))
        session.add_all([cost_entry, budget])
        await session.flush()
        cost_entry_id = cost_entry.id
        budget_id = budget.id
        await session.commit()

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{tenant_b_id}'"))
        visible_cost_entries = (
            (await session.execute(select(CostEntry).where(CostEntry.id == cost_entry_id)))
            .scalars()
            .all()
        )
        visible_budgets = (
            (await session.execute(select(Budget).where(Budget.id == budget_id))).scalars().all()
        )

    assert visible_cost_entries == [], (
        "ISOLATION FAILURE: tenant B can read tenant A's cost_entries row"
    )
    assert visible_budgets == [], "ISOLATION FAILURE: tenant B can read tenant A's budgets row"

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{tenant_a_id}'"))
        own_cost_entries = (
            (await session.execute(select(CostEntry).where(CostEntry.id == cost_entry_id)))
            .scalars()
            .all()
        )

    assert len(own_cost_entries) == 1


# ---------------------------------------------------------------------------
# Task 2: legacy-surface leak tripwires — reports, dashboard-alert filter, AI
# context builders. Each proves FINSEC-04 with an enforced assertion rather
# than manual inspection.
# ---------------------------------------------------------------------------


def _collect_dict_keys(value: object) -> set[str]:
    """Recursively collect every dict key in a JSON-decoded response body."""
    keys: set[str] = set()
    if isinstance(value, dict):
        keys.update(value.keys())
        for nested in value.values():
            keys.update(_collect_dict_keys(nested))
    elif isinstance(value, list):
        for item in value:
            keys.update(_collect_dict_keys(item))
    return keys


@pytest.mark.asyncio
async def test_reports_dashboard_leaks_no_finance_fields(async_client, seed_two_tenants):
    """D-06 tripwire: GET /reports/dashboard (admin-gated, revenue-only) never
    grows a finance field — fails loudly if a future phase adds cost/margin data
    to the wrong (non-finance-gated) endpoint.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    admin_headers = {"Authorization": f"Bearer {_token(company_id, ['admin'])}"}

    resp = await async_client.get("/api/v1/reports/dashboard", headers=admin_headers)
    assert resp.status_code == 200, resp.text

    response_keys = _collect_dict_keys(resp.json())
    assert response_keys.isdisjoint(FINANCE_FIELD_NAMES)


@pytest.mark.asyncio
async def test_dashboard_alerts_filtered_by_finance_permission(
    async_client, tenant_a_client, seed_two_tenants
):
    """FINSEC-04: users without finance.view never see financial alerts;
    users with finance.view see both. budget_warning is a real financial
    alert type as of Phase 34 (registered in FINANCIAL_ALERT_TYPES and
    permitted by the migration 0035 CHECK constraint).
    """
    company_id = seed_two_tenants["tenant_a_id"]

    project_resp = await tenant_a_client.post(
        "/api/v1/projects/", json={"name": "Finance Alerts Test"}
    )
    assert project_resp.status_code == 201, project_resp.text
    project_id = project_resp.json()["id"]

    async with async_session_factory() as session:
        await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))
        session.add_all(
            [
                DashboardAlert(
                    company_id=company_id,
                    project_id=project_id,
                    severity="warning",
                    alert_type="budget_warning",
                    impact_text="Plumbing scope has spent $8,200 of its $10,000 budget (82%).",
                ),
                DashboardAlert(
                    company_id=company_id,
                    project_id=project_id,
                    severity="warning",
                    alert_type="schedule_slip",
                    impact_text="Plumbing is 3 days behind schedule",
                ),
            ]
        )
        await session.commit()

    gc_headers = {"Authorization": f"Bearer {_token(company_id, ['gc'])}"}
    gc_resp = await async_client.get(
        f"/api/v1/dashboard/alerts?project_id={project_id}", headers=gc_headers
    )
    assert gc_resp.status_code == 200, gc_resp.text
    gc_types = {a["alert_type"] for a in gc_resp.json()}
    assert "budget_warning" not in gc_types
    assert "schedule_slip" in gc_types

    pm_headers = {"Authorization": f"Bearer {_token(company_id, ['project_manager'])}"}
    pm_resp = await async_client.get(
        f"/api/v1/dashboard/alerts?project_id={project_id}", headers=pm_headers
    )
    assert pm_resp.status_code == 200, pm_resp.text
    pm_types = {a["alert_type"] for a in pm_resp.json()}
    assert "budget_warning" in pm_types
    assert "schedule_slip" in pm_types


@pytest.mark.asyncio
async def test_ai_context_builders_leak_no_finance_fields():
    """FINSEC-04 tripwire: today's AI context builders carry no finance fields —
    proven both on the input item dict (no finance keys) and the rendered string
    output (no finance field name appears as a substring). This will fail
    loudly if a later phase adds finance data to these builders without
    routing it through app.core.finance_scrub.scrub_finance_fields first.
    """
    checklist_item = {
        "project_name": "Riverside Remodel",
        "trade_name": "Plumbing",
        "target_date": date(2026, 7, 24),
        "tasks": [
            {
                "id": str(uuid4()),
                "title": "Rough-in supply lines",
                "status": "not_started",
                "priority": "high",
                "due_date": "2026-07-25",
                "materials_needed": [{"name": "PEX tubing"}],
            }
        ],
        "project_description": "Full bathroom remodel, single trade scope.",
    }
    assert set(checklist_item.keys()).isdisjoint(FINANCE_FIELD_NAMES)

    checklist_service = ChecklistService.__new__(ChecklistService)
    checklist_content = checklist_service._build_user_content_from_dict(checklist_item)
    assert all(name not in checklist_content for name in FINANCE_FIELD_NAMES)

    slip_item = {
        "project_name": "Riverside Remodel",
        "trade_name": "Plumbing",
        "days_behind": 3,
        "overdue_tasks": [
            {
                "id": str(uuid4()),
                "title": "Rough-in supply lines",
                "due_date": "2026-07-20",
                "status": "in_progress",
            }
        ],
        "affected_scope_ids": [],
        "project_description": "Full bathroom remodel, single trade scope.",
    }
    assert set(slip_item.keys()).isdisjoint(FINANCE_FIELD_NAMES)

    dashboard_service = DashboardService.__new__(DashboardService)
    slip_content = dashboard_service._build_slip_content_from_dict(slip_item)
    assert all(name not in slip_content for name in FINANCE_FIELD_NAMES)
