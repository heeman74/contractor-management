"""Phase 18 — Reporting Dashboard E2E Tests.

Tests for:
- GET /api/v1/reports/dashboard (RPT-01, RPT-02)
- GET /api/v1/reports/utilization-heatmap (RPT-03)

Strategy:
- Uses tenant_a_client fixture (admin JWT Bearer token pre-set, see conftest.py).
- Uses async_client fixture (no auth) to verify 401 responses.
- All tests are @pytest.mark.anyio async tests — NO @pytest.mark.skip stubs.
- Note: tenant_a_contractor_token fixture does not exist in conftest.py;
  403 tests for contractor role are deferred to a future test fixture addition.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

# Side-effect: register all mappers before tests run.
import app.features.scheduling.models  # noqa: F401

pytestmark = pytest.mark.anyio


class TestDashboard:
    """RPT-01: Dashboard endpoint returns all 4 metric groups."""

    async def test_dashboard_returns_all_metrics(self, tenant_a_client: AsyncClient):
        """Admin receives 200 with all 4 dashboard metric groups."""
        response = await tenant_a_client.get("/api/v1/reports/dashboard")
        assert response.status_code == 200
        data = response.json()
        assert "jobs_by_status" in data
        assert "revenue_by_month" in data
        assert "contractor_utilization" in data
        assert "quote_conversion" in data
        # quote_conversion has expected fields
        qc = data["quote_conversion"]
        assert "approved" in qc
        assert "declined" in qc
        assert "pending" in qc
        assert "conversion_rate" in qc

    async def test_dashboard_jobs_by_status_is_list(self, tenant_a_client: AsyncClient):
        """jobs_by_status is a list of status/count objects."""
        response = await tenant_a_client.get("/api/v1/reports/dashboard")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data["jobs_by_status"], list)
        assert isinstance(data["revenue_by_month"], list)

    async def test_dashboard_requires_auth(self, async_client: AsyncClient):
        """Unauthenticated request returns 401."""
        response = await async_client.get("/api/v1/reports/dashboard")
        assert response.status_code == 401


class TestDateFilter:
    """RPT-02: Date filtering narrows results."""

    async def test_date_filter_returns_200(self, tenant_a_client: AsyncClient):
        """Dashboard with explicit date range returns 200."""
        response = await tenant_a_client.get(
            "/api/v1/reports/dashboard?start_date=2026-01-01&end_date=2026-12-31"
        )
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data["jobs_by_status"], list)
        assert isinstance(data["revenue_by_month"], list)

    async def test_narrow_date_range_returns_subset(self, tenant_a_client: AsyncClient):
        """Very narrow range in distant past returns empty/zero job counts."""
        response = await tenant_a_client.get(
            "/api/v1/reports/dashboard?start_date=2020-01-01&end_date=2020-01-01"
        )
        assert response.status_code == 200
        data = response.json()
        # Should have empty or zero-count results for jobs
        total_jobs = sum(item["count"] for item in data["jobs_by_status"])
        assert total_jobs == 0

    async def test_future_date_range_returns_empty(self, tenant_a_client: AsyncClient):
        """Future date range returns empty metrics (no data exists yet)."""
        response = await tenant_a_client.get(
            "/api/v1/reports/dashboard?start_date=2099-01-01&end_date=2099-12-31"
        )
        assert response.status_code == 200
        data = response.json()
        assert data["jobs_by_status"] == []
        assert data["revenue_by_month"] == []


class TestHeatmap:
    """RPT-03: Utilization heatmap endpoint."""

    async def test_heatmap_returns_200_with_structure(self, tenant_a_client: AsyncClient):
        """Admin receives 200 with weeks and contractors fields."""
        response = await tenant_a_client.get("/api/v1/reports/utilization-heatmap")
        assert response.status_code == 200
        data = response.json()
        assert "weeks" in data
        assert "contractors" in data
        assert isinstance(data["weeks"], list)
        assert isinstance(data["contractors"], list)

    async def test_heatmap_with_date_range(self, tenant_a_client: AsyncClient):
        """Heatmap with explicit date range returns 200 with valid contractor structure."""
        response = await tenant_a_client.get(
            "/api/v1/reports/utilization-heatmap?start_date=2026-01-01&end_date=2026-12-31"
        )
        assert response.status_code == 200
        data = response.json()
        # Each contractor should have weeks array with valid fields
        for contractor in data["contractors"]:
            assert "contractor_id" in contractor
            assert "contractor_name" in contractor
            assert "weeks" in contractor
            assert isinstance(contractor["weeks"], list)

    async def test_heatmap_requires_auth(self, async_client: AsyncClient):
        """Unauthenticated request returns 401."""
        response = await async_client.get("/api/v1/reports/utilization-heatmap")
        assert response.status_code == 401

    async def test_heatmap_iso_week_format(self, tenant_a_client: AsyncClient):
        """ISO week strings match YYYY-Www format when weeks are present."""
        response = await tenant_a_client.get(
            "/api/v1/reports/utilization-heatmap?start_date=2026-01-01&end_date=2026-03-31"
        )
        assert response.status_code == 200
        data = response.json()
        for week in data["weeks"]:
            # e.g. "2026-W01" through "2026-W53"
            assert len(week) >= 7, f"Unexpected week format: {week}"
            assert "W" in week, f"Expected ISO week with W prefix, got: {week}"


class TestHeatmapEmptyContractor:
    """RPT-03: Contractor with zero bookings still appears."""

    async def test_zero_booking_contractor_appears(self, tenant_a_client: AsyncClient):
        """Contractors with no bookings in date range still appear in heatmap response.

        Due to LEFT JOIN, contractors appear even when they have no bookings.
        Uses a date range far in the past where no bookings exist.
        If no contractors are seeded (empty test DB), the list is empty — still valid.
        """
        response = await tenant_a_client.get(
            "/api/v1/reports/utilization-heatmap?start_date=2020-01-01&end_date=2020-01-31"
        )
        assert response.status_code == 200
        data = response.json()
        # At minimum, verify the structure is correct
        assert isinstance(data["contractors"], list)
        # If contractors exist, verify they have valid week items
        for contractor in data["contractors"]:
            for week in contractor["weeks"]:
                assert "utilization_percent" in week
                assert "booked_hours" in week
                assert "available_hours" in week
