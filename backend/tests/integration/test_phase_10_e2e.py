"""Phase 10 — UI Backend Wiring Gap Closure: Integration tests for SCHED-06.

Tests prove:
- SCHED-06: SchedulingService receives CachedTravelTimeProvider when ORS_API_KEY is set,
  and travel_provider=None when ORS_API_KEY is absent.
- Smoke test: scheduling endpoint works correctly with the new dependency injection.

Strategy:
- For travel provider injection tests: call get_scheduling_service() directly as
  a standalone async function (not via the ASGI transport) by constructing a fake
  AsyncSession and using monkeypatch on settings.ors_api_key.
- For smoke test: use ASGI transport with tenant_a_client fixture.
"""

from __future__ import annotations

import uuid
from unittest.mock import MagicMock

import pytest

from app.core.config import settings
from app.features.scheduling.router import get_scheduling_service
from app.features.scheduling.service import SchedulingService
from app.features.scheduling.travel.cache import CachedTravelTimeProvider

# isort: split
# Side-effect: register all scheduling mappers before tests run
import app.features.scheduling.models  # noqa: F401

# ---------------------------------------------------------------------------
# SCHED-06: Travel provider injection tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_travel_provider_absent_when_no_ors_key(monkeypatch: pytest.MonkeyPatch) -> None:
    """SCHED-06: travel_provider=None when ORS_API_KEY is not configured.

    Verifies the dependency returns SchedulingService with travel_provider=None
    when settings.ors_api_key is None (the default).
    """
    # Ensure ORS API key is absent
    monkeypatch.setattr(settings, "ors_api_key", None)

    # Create a minimal fake AsyncSession (no DB calls needed for this path)
    fake_db = MagicMock()

    # Fake current user (only needed to satisfy the dependency signature)
    fake_user = MagicMock()
    fake_user.user_id = str(uuid.uuid4())

    # Call the dependency function directly (not via FastAPI DI)
    svc = await get_scheduling_service(db=fake_db, current_user=fake_user)

    assert isinstance(svc, SchedulingService)
    assert svc.travel_provider is None, "Expected travel_provider=None when ORS_API_KEY is absent"


@pytest.mark.asyncio
async def test_travel_provider_injected_when_ors_key_set(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """SCHED-06: CachedTravelTimeProvider injected when ORS_API_KEY is configured.

    Verifies the dependency constructs and injects CachedTravelTimeProvider
    when settings.ors_api_key is non-None.
    """
    # Set ORS API key in settings
    monkeypatch.setattr(settings, "ors_api_key", "test-ors-api-key-12345")

    # Mock the tenant context — get_current_tenant_id() reads a ContextVar
    from app.core.tenant import set_current_tenant_id

    test_company_id = uuid.uuid4()
    set_current_tenant_id(test_company_id)

    fake_db = MagicMock()
    fake_user = MagicMock()
    fake_user.user_id = str(uuid.uuid4())

    svc = await get_scheduling_service(db=fake_db, current_user=fake_user)

    assert isinstance(svc, SchedulingService)
    assert svc.travel_provider is not None, (
        "Expected CachedTravelTimeProvider when ORS_API_KEY is set"
    )
    assert isinstance(svc.travel_provider, CachedTravelTimeProvider), (
        f"Expected CachedTravelTimeProvider, got {type(svc.travel_provider)}"
    )


# ---------------------------------------------------------------------------
# SCHED-06: Smoke test — scheduling endpoint works with new DI
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_scheduling_availability_endpoint_smoke(
    tenant_a_client,
    seed_two_tenants: dict,
) -> None:
    """Smoke test: POST /api/v1/scheduling/availability returns 200 with new DI.

    This test verifies that the get_scheduling_service dependency wiring does not
    break existing endpoint functionality. ORS_API_KEY is not set in test env
    so travel_provider=None path is exercised.

    A valid contractor UUID is required — we use the registered admin user's ID
    as the contractor_id. An empty availability list is acceptable (no schedule
    configured for test user) — a 200 response proves the endpoint wiring works.
    """
    contractor_id = seed_two_tenants["tenant_a_user_id"]

    resp = await tenant_a_client.post(
        "/api/v1/scheduling/availability",
        json={
            "contractor_ids": [contractor_id],
            "date": "2026-06-15",
        },
    )

    # 200 = endpoint wiring OK (empty list is acceptable — no schedule configured)
    assert resp.status_code == 200, (
        f"Expected 200 from scheduling/availability, got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    assert isinstance(data, list), f"Expected list response, got {type(data)}"


@pytest.mark.asyncio
async def test_scheduling_conflicts_endpoint_smoke(
    tenant_a_client,
    seed_two_tenants: dict,
) -> None:
    """Smoke test: POST /api/v1/scheduling/conflicts returns 200 with new DI.

    Verifies conflict-check endpoint works with get_scheduling_service dependency.
    """
    contractor_id = seed_two_tenants["tenant_a_user_id"]

    resp = await tenant_a_client.post(
        "/api/v1/scheduling/conflicts",
        json={
            "contractor_id": contractor_id,
            "start": "2026-06-15T09:00:00Z",
            "end": "2026-06-15T11:00:00Z",
        },
    )

    assert resp.status_code == 200, (
        f"Expected 200 from scheduling/conflicts, got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    assert isinstance(data, list), f"Expected list response, got {type(data)}"
    # No existing bookings → no conflicts
    assert data == [], f"Expected empty conflict list, got {data}"
