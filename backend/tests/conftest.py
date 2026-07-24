"""Test configuration and fixtures for ContractorHub backend tests.

Multi-tenant test setup with JWT authentication:
- Runs Alembic migrations against a test database (preserving RLS policies).
- Each test gets fresh async clients that exercise the full ASGI stack.
- seed_two_tenants creates two companies via /auth/register and returns JWT tokens.
- tenant_a_client and tenant_b_client have Bearer tokens pre-set.

Design:
  Uses the real app get_db dependency (no session injection overrides) so that
  the full JWT -> get_current_user -> set_current_tenant_id -> after_begin
  SET LOCAL RLS path is fully exercised.

  The app engine uses NullPool in tests to avoid stale connection pool issues
  across async test boundaries.
"""

import os
import subprocess
import sys

# Set required env vars BEFORE importing app (Settings crashes without these).
# Force the app-under-test onto the dedicated TEST database, ignoring any dev
# DATABASE_URL — so running the suite can never truncate development data. CI sets
# TEST_DATABASE_URL; locally it defaults to contractorhub_test.
os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub_test",
)
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-for-integration-tests-min-32")

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

import app.core.database as db_module
from app.core.rate_limit import limiter
from app.main import app

# ---------------------------------------------------------------------------
# Replace app engine with NullPool version to avoid event loop issues in tests.
# NullPool creates fresh connections per use — no stale pool connections.
# ---------------------------------------------------------------------------
_test_app_engine = create_async_engine(
    os.environ["DATABASE_URL"],
    echo=False,
    poolclass=NullPool,
)
_test_session_factory = async_sessionmaker(
    _test_app_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)
# Monkey-patch the app's database module so all app code uses NullPool engine
db_module.engine = _test_app_engine
db_module.async_session_factory = _test_session_factory


# ---------------------------------------------------------------------------
# Database URL resolution
# ---------------------------------------------------------------------------

TEST_DATABASE_URL = os.environ["DATABASE_URL"]

_BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_ALEMBIC_INI = os.path.join(_BACKEND_DIR, "alembic.ini")


# ---------------------------------------------------------------------------
# Session-scoped engine + migration setup
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture(scope="session")
async def test_engine():
    """Create test engine and apply Alembic migrations once for the test session."""
    env = os.environ.copy()
    env["DATABASE_URL"] = TEST_DATABASE_URL

    result = subprocess.run(
        [sys.executable, "-m", "alembic", "-c", _ALEMBIC_INI, "upgrade", "head"],
        cwd=_BACKEND_DIR,
        capture_output=True,
        text=True,
        env=env,
    )
    if result.returncode != 0:
        pytest.fail(f"Alembic upgrade failed:\nstdout: {result.stdout}\nstderr: {result.stderr}")

    engine = create_async_engine(TEST_DATABASE_URL, echo=False, poolclass=NullPool)
    yield engine
    await engine.dispose()


# ---------------------------------------------------------------------------
# Per-test table truncation — prevents cross-test data pollution
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture(autouse=True)
async def clean_tables(test_engine):
    """Truncate all tables and reset rate limiter before each test.

    All tables are listed explicitly in a single TRUNCATE statement (no CASCADE).
    PostgreSQL acquires all table locks atomically in a single TRUNCATE, preventing
    deadlocks. TRUNCATE bypasses FORCE ROW LEVEL SECURITY so no RLS policy issues
    occur even after RESET app.current_company_id.

    Order: bookings first (self-referential FK via parent_booking_id), then other
    scheduling tables, then auth tables, then companies (parent of all).
    """
    async with test_engine.connect() as conn:
        await conn.execute(text("RESET app.current_company_id"))
        await conn.execute(
            text(
                "TRUNCATE TABLE "
                # Phase 6 field workflow tables (reference job_notes/jobs): children first.
                "attachments, "
                "time_entries, "
                "job_notes, "
                # Phase 4 job lifecycle tables (reference jobs/users): children before parents.
                # ratings and job_requests reference jobs; client_properties references job_sites.
                "ratings, "
                "job_requests, "
                "client_properties, "
                "client_profiles, "
                # Scheduling tables (reference users/companies): children before parents.
                # bookings listed before job_sites (bookings references job_sites).
                # bookings now also references jobs (via bookings_job_id_fkey from migration 0008).
                "bookings, "
                "travel_time_cache, "
                "job_sites, "
                "jobs, "
                "contractor_date_overrides, "
                "contractor_weekly_schedule, "
                "contractor_schedule_locks, "
                # Phase 8 business operations tables (reference jobs/users): children first.
                "invoice_line_items, "
                "invoices, "
                "quote_line_items, "
                "quote_templates, "
                "quotes, "
                # Phase 7 notification tables
                "device_tokens, "
                # Phase 20 dependency engine tables (reference tasks)
                # task_dependencies FKs to tasks — must come before tasks
                # project_zones is referenced by tasks.zone_id — must come after task_dependencies but before tasks
                "task_dependencies, "
                # Phase 21 AI conversation tables (reference projects/trade_scopes/users)
                # ai_token_usage, ai_messages -> ai_conversations -> projects/trade_scopes
                "ai_token_usage, "
                "ai_image_uploads, "
                "ai_messages, "
                "ai_conversations, "
                # Phase 19/22 project data model tables (reference users/companies/trade_catalog)
                # task_notes -> tasks; task_attachments -> tasks -> trade_scopes -> projects
                # user_trade_specialties -> users, trade_catalog
                "task_notes, "
                "task_attachments, "
                "tasks, "
                "project_zones, "
                "trade_scopes, "
                "projects, "
                "user_trade_specialties, "
                "trade_catalog, "
                # Phase 23 chat tables (reference chat_threads, users, projects)
                # chat_read_receipts -> chat_threads; chat_messages -> chat_threads
                # chat_memberships -> chat_threads; chat_threads -> projects
                "chat_read_receipts, "
                "chat_messages, "
                "chat_memberships, "
                "chat_threads, "
                # Phase 24 inspection workflow tables (reference tasks/projects/trade_scopes)
                # task_inspections -> tasks; punch_list_items -> projects, trade_scopes
                # site_walk_flags -> projects
                "task_inspections, "
                "punch_list_items, "
                "site_walk_flags, "
                # Phase 25 billing tables (reference trade_scopes)
                "billing_milestones, "
                # Phase 26 AI checklists and dashboard alert tables
                # daily_checklists references projects; dashboard_alerts references projects
                "daily_checklists, "
                "dashboard_alerts, "
                # Foreman tables (reference projects/users)
                "project_status_updates, "
                "project_assignments, "
                # Auth + core tables
                "refresh_tokens, "
                "user_roles, "
                # Phase 27 RBAC (references companies)
                "company_role_permissions, "
                "users, "
                "companies"
            )
        )
        await conn.commit()
    limiter.reset()
    yield


# ---------------------------------------------------------------------------
# Async HTTP test client — uses real app, no dependency overrides
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def async_client():
    """Provide an async test client with no auth headers.

    Uses in-process ASGI transport. No dependency overrides — the real get_db
    dependency is used so the full JWT -> RLS path runs.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------


async def register_user(client: AsyncClient, email: str, company_name: str) -> dict:
    """Register a new user and return the full response data including tokens."""
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "TestPass123!",
            "company_name": company_name,
        },
    )
    assert resp.status_code == 201, f"Registration failed: {resp.text}"
    return resp.json()


# ---------------------------------------------------------------------------
# Seed two tenants — via /auth/register (creates company + user + admin role)
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def seed_two_tenants(async_client):
    """Create Tenant A and Tenant B via /auth/register.

    Returns dict with tenant IDs, user IDs, and access tokens.
    """
    data_a = await register_user(async_client, "admin@tenant-a.com", "Tenant A Corp")
    data_b = await register_user(async_client, "admin@tenant-b.com", "Tenant B Corp")

    return {
        "tenant_a_id": data_a["company_id"],
        "tenant_a_token": data_a["access_token"],
        "tenant_a_user_id": data_a["user_id"],
        "tenant_b_id": data_b["company_id"],
        "tenant_b_token": data_b["access_token"],
        "tenant_b_user_id": data_b["user_id"],
    }


# ---------------------------------------------------------------------------
# Tenant-scoped clients — Bearer token pre-set
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def tenant_a_client(seed_two_tenants):
    """Async client with Tenant A's JWT Bearer token set on every request.

    Each request flows: get_current_user extracts company_id from JWT
    -> set_current_tenant_id -> after_begin executes SET LOCAL RLS variable.
    """
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {seed_two_tenants['tenant_a_token']}"},
    ) as ac:
        yield ac


@pytest_asyncio.fixture
async def tenant_b_client(seed_two_tenants):
    """Async client with Tenant B's JWT Bearer token set on every request."""
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"Authorization": f"Bearer {seed_two_tenants['tenant_b_token']}"},
    ) as ac:
        yield ac
