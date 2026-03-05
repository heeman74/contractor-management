"""Test configuration and fixtures for ContractorHub backend tests.

Multi-tenant test setup:
- Runs Alembic migrations against a test database (preserving RLS policies).
- Each test gets fresh async clients that exercise the full ASGI stack.
- two tenant fixtures (tenant_a_client, tenant_b_client) pre-set X-Company-Id headers.
- seed_two_tenants creates two companies and returns their IDs for isolation tests.

Design:
  Uses the real app get_db dependency (no session injection overrides) so that
  TenantMiddleware -> ContextVar -> after_begin SET LOCAL RLS path is fully exercised.
  Companies are created via the API and committed — visible across independent sessions.
  Function-level isolation is achieved by truncating tables before each test.
"""

import os
import subprocess
import sys

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.main import app

# ---------------------------------------------------------------------------
# Database URL resolution
# ---------------------------------------------------------------------------

TEST_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub_test",
    ),
)

_BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_ALEMBIC_INI = os.path.join(_BACKEND_DIR, "alembic.ini")


# ---------------------------------------------------------------------------
# Session-scoped engine + migration setup
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture(scope="session")
async def test_engine():
    """Create test engine and apply Alembic migrations once for the test session.

    Alembic env.py uses async_engine_from_config (asyncpg), so no psycopg2 needed.
    The DATABASE_URL env var points to the test database for migration execution.
    """
    env = os.environ.copy()
    env["DATABASE_URL"] = TEST_DATABASE_URL

    # Apply all migrations — idempotent, handles version tracking
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "-c", _ALEMBIC_INI, "upgrade", "head"],
        cwd=_BACKEND_DIR,
        capture_output=True,
        text=True,
        env=env,
    )
    if result.returncode != 0:
        pytest.fail(
            f"Alembic upgrade failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

    engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    yield engine
    await engine.dispose()


# ---------------------------------------------------------------------------
# Per-test table truncation — prevents cross-test data pollution
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture(autouse=True)
async def clean_tables(test_engine):
    """Truncate tenant-scoped tables before each test to ensure isolation.

    RESTART IDENTITY resets sequences. CASCADE handles FK constraints.
    Uses SET session_replication_role = 'replica' to bypass FK checks during truncate.
    """
    session_factory = async_sessionmaker(
        test_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        await session.execute(
            text("TRUNCATE TABLE user_roles, users, companies RESTART IDENTITY CASCADE")
        )
        await session.commit()
    yield


# ---------------------------------------------------------------------------
# Async HTTP test client — uses real app, no dependency overrides
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def async_client():
    """Provide an async test client with NO X-Company-Id header.

    Uses in-process ASGI transport. No dependency overrides — the real get_db
    dependency is used so the full TenantMiddleware -> ContextVar -> RLS path runs.
    """
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        yield ac


# ---------------------------------------------------------------------------
# Seed two tenants — committed data visible across independent sessions
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def seed_two_tenants(async_client):
    """Create Tenant A and Tenant B companies via the API.

    Companies need no X-Company-Id header (they ARE the tenant root).
    Returns {'tenant_a_id': str, 'tenant_b_id': str}.
    """
    resp_a = await async_client.post(
        "/api/v1/companies/",
        json={"name": "Tenant A Corp"},
    )
    assert resp_a.status_code == 201, f"Failed to create Tenant A: {resp_a.text}"

    resp_b = await async_client.post(
        "/api/v1/companies/",
        json={"name": "Tenant B Corp"},
    )
    assert resp_b.status_code == 201, f"Failed to create Tenant B: {resp_b.text}"

    return {
        "tenant_a_id": resp_a.json()["id"],
        "tenant_b_id": resp_b.json()["id"],
    }


# ---------------------------------------------------------------------------
# Tenant-scoped clients — X-Company-Id header pre-set
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def tenant_a_client(seed_two_tenants):
    """Async client with Tenant A's X-Company-Id header set on every request.

    Each request flows: TenantMiddleware sets ContextVar(tenant_a_id)
    -> get_db opens session -> after_begin executes SET LOCAL RLS variable.
    """
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-Company-Id": seed_two_tenants["tenant_a_id"]},
    ) as ac:
        yield ac


@pytest_asyncio.fixture
async def tenant_b_client(seed_two_tenants):
    """Async client with Tenant B's X-Company-Id header set on every request.

    Each request flows: TenantMiddleware sets ContextVar(tenant_b_id)
    -> get_db opens session -> after_begin executes SET LOCAL RLS variable.
    """
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"X-Company-Id": seed_two_tenants["tenant_b_id"]},
    ) as ac:
        yield ac
