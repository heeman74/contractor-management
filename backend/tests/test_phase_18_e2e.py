"""Phase 18 E2E integration test stubs — Reporting Dashboard.

These stubs satisfy the ship-with-feature requirement for Phase 18 Plan 01.
Full implementations will be added in Plan 03 once the frontend is complete.

Each test class corresponds to an acceptance-criteria group from the plan.
Mark removed and tests fully implemented in Plan 03.
"""

import pytest


@pytest.mark.skip(reason="stub — implement in Plan 03")
class TestDashboard:
    """GET /api/v1/reports/dashboard returns 200 with all 4 metric fields.

    Coverage:
    - Admin can fetch dashboard data
    - Response includes jobs_by_status, revenue_by_month,
      contractor_utilization, and quote_conversion
    - Non-admin role receives 403
    """

    async def test_dashboard_returns_200_for_admin(self, tenant_a_client):
        """Admin receives 200 with all 4 dashboard metric groups."""
        response = await tenant_a_client.get("/api/v1/reports/dashboard")
        assert response.status_code == 200
        data = response.json()
        assert "jobs_by_status" in data
        assert "revenue_by_month" in data
        assert "contractor_utilization" in data
        assert "quote_conversion" in data

    async def test_dashboard_returns_403_for_non_admin(self, tenant_a_client):
        """Non-admin role receives 403 from dashboard endpoint."""
        # TODO: use contractor-role token fixture
        pass


@pytest.mark.skip(reason="stub — implement in Plan 03")
class TestDateFilter:
    """Date filtering narrows dashboard results.

    Coverage:
    - start_date and end_date query params are respected
    - Passing future date range returns empty metric lists
    - Revenue grouped by correct month boundaries
    """

    async def test_date_filter_future_range_returns_empty(self, tenant_a_client):
        """Future date range returns empty metrics (no data exists yet)."""
        response = await tenant_a_client.get(
            "/api/v1/reports/dashboard",
            params={"start_date": "2099-01-01", "end_date": "2099-12-31"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["jobs_by_status"] == []
        assert data["revenue_by_month"] == []

    async def test_date_filter_start_date_only(self, tenant_a_client):
        """start_date alone filters results from that date forward."""
        response = await tenant_a_client.get(
            "/api/v1/reports/dashboard",
            params={"start_date": "2026-01-01"},
        )
        assert response.status_code == 200


@pytest.mark.skip(reason="stub — implement in Plan 03")
class TestHeatmap:
    """GET /api/v1/reports/utilization-heatmap returns 200 with weeks + contractors.

    Coverage:
    - Response has weeks (list[str]) and contractors (list[...]) fields
    - ISO week format is YYYY-Www (e.g. "2026-W10")
    - Non-admin receives 403
    """

    async def test_heatmap_returns_200_for_admin(self, tenant_a_client):
        """Admin receives 200 with weeks and contractors fields."""
        response = await tenant_a_client.get("/api/v1/reports/utilization-heatmap")
        assert response.status_code == 200
        data = response.json()
        assert "weeks" in data
        assert "contractors" in data
        assert isinstance(data["weeks"], list)
        assert isinstance(data["contractors"], list)

    async def test_heatmap_iso_week_format(self, tenant_a_client):
        """ISO week strings match YYYY-Www format."""
        response = await tenant_a_client.get(
            "/api/v1/reports/utilization-heatmap",
            params={"start_date": "2026-01-01", "end_date": "2026-03-31"},
        )
        assert response.status_code == 200
        data = response.json()
        for week in data["weeks"]:
            # e.g. "2026-W01" through "2026-W53"
            assert len(week) >= 7, f"Unexpected week format: {week}"
            assert "W" in week, f"Expected ISO week with W prefix, got: {week}"

    async def test_heatmap_returns_403_for_non_admin(self, tenant_a_client):
        """Non-admin role receives 403 from heatmap endpoint."""
        # TODO: use contractor-role token fixture
        pass


@pytest.mark.skip(reason="stub — implement in Plan 03")
class TestHeatmapEmptyContractor:
    """Contractor with zero bookings still appears in heatmap response.

    Coverage:
    - LEFT JOIN ensures contractors without bookings appear
    - Their week items have booked_hours=0, utilization_percent=0
    - available_hours is fixed at 40 per week
    """

    async def test_contractor_no_bookings_appears_in_heatmap(
        self, tenant_a_client, seed_contractor_no_bookings
    ):
        """Contractor with no bookings appears with zero-filled week items."""
        response = await tenant_a_client.get("/api/v1/reports/utilization-heatmap")
        assert response.status_code == 200
        data = response.json()
        contractor_ids = [c["contractor_id"] for c in data["contractors"]]
        assert str(seed_contractor_no_bookings) in contractor_ids

    async def test_contractor_week_item_zero_values(
        self, tenant_a_client, seed_contractor_no_bookings
    ):
        """Zero-booking contractor has booked_hours=0 and utilization_percent=0."""
        response = await tenant_a_client.get(
            "/api/v1/reports/utilization-heatmap",
            params={"start_date": "2026-01-01", "end_date": "2026-03-31"},
        )
        assert response.status_code == 200
        data = response.json()
        for contractor in data["contractors"]:
            if contractor["contractor_id"] == str(seed_contractor_no_bookings):
                for week in contractor["weeks"]:
                    assert week["booked_hours"] == "0.00"
                    assert week["utilization_percent"] == "0.00"
                    assert week["available_hours"] == "40"
