"""Phase 24 backend integration tests — INSP-02: Site walk flags.

Tests cover:
1. Create site walk flag — 201, all fields returned
2. List flags for project — returns correct count
3. Flag defaults to medium severity when not specified
4. Convert flag to punch list item — PunchListItem created with source_flag_id
5. Converting an already-converted flag returns 422

All tests use ASGI client hitting real HTTP endpoints via tenant_a_client.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

import app.features.inspection.models  # noqa: F401 — ensure mappers configured

pytestmark = pytest.mark.anyio


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


async def _create_project(client: AsyncClient, name: str = "Site Walk Project") -> str:
    resp = await client.post("/api/v1/projects/", json={"name": name})
    assert resp.status_code == 201, f"Project creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient,
    project_id: str,
    trade_name: str = "Plumbing",
) -> str:
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name},
    )
    assert resp.status_code == 201, f"Trade scope creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_flag(
    client: AsyncClient,
    project_id: str,
    description: str = "Crack in foundation",
    severity: str | None = None,
    location_label: str | None = None,
) -> dict:
    body: dict = {"description": description}
    if severity is not None:
        body["severity"] = severity
    if location_label is not None:
        body["location_label"] = location_label
    return await client.post(f"/api/v1/projects/{project_id}/flags", json=body)


# ---------------------------------------------------------------------------
# INSP-02: Site walk flag tests
# ---------------------------------------------------------------------------


class TestSiteWalkFlags:
    async def test_create_site_walk_flag(self, tenant_a_client: AsyncClient) -> None:
        """Create a site walk flag — 201, all fields present."""
        project_id = await _create_project(tenant_a_client, "Flag Create Project")

        resp = await _create_flag(
            tenant_a_client,
            project_id,
            description="Crack in foundation",
            severity="high",
            location_label="North wall",
        )
        assert resp.status_code == 201, f"Flag creation failed: {resp.text}"
        data = resp.json()
        assert data["description"] == "Crack in foundation"
        assert data["severity"] == "high"
        assert data["location_label"] == "North wall"
        assert data["status"] == "open"
        assert data["project_id"] == project_id
        assert "id" in data

    async def test_list_flags_for_project(self, tenant_a_client: AsyncClient) -> None:
        """Create 3 flags, list them — returns all 3."""
        project_id = await _create_project(tenant_a_client, "Flag List Project")

        for i in range(3):
            r = await _create_flag(
                tenant_a_client,
                project_id,
                description=f"Issue {i + 1}",
            )
            assert r.status_code == 201

        list_resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/flags")
        assert list_resp.status_code == 200
        flags = list_resp.json()
        assert len(flags) == 3

    async def test_flag_defaults_to_medium_severity(self, tenant_a_client: AsyncClient) -> None:
        """Creating a flag without severity defaults to 'medium'."""
        project_id = await _create_project(tenant_a_client, "Default Severity Project")

        resp = await _create_flag(
            tenant_a_client,
            project_id,
            description="Issue without explicit severity",
        )
        assert resp.status_code == 201
        assert resp.json()["severity"] == "medium"

    async def test_create_flag_missing_description_returns_422(
        self, tenant_a_client: AsyncClient
    ) -> None:
        """Creating a flag with empty description returns 422."""
        project_id = await _create_project(tenant_a_client, "Empty Desc Project")

        resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/flags",
            json={"description": ""},
        )
        assert resp.status_code == 422

    async def test_convert_flag_to_punch_item(self, tenant_a_client: AsyncClient) -> None:
        """Convert a site walk flag to a punch list item.

        - PunchListItem created with source_flag_id set
        - Flag status becomes 'converted'
        - PunchListItem inherits flag description
        """
        project_id = await _create_project(tenant_a_client, "Flag Convert Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id, "Electrical")

        flag_resp = await _create_flag(
            tenant_a_client,
            project_id,
            description="Exposed wiring near panel",
            severity="high",
        )
        assert flag_resp.status_code == 201
        flag_id = flag_resp.json()["id"]

        # Convert flag to punch item
        convert_resp = await tenant_a_client.patch(
            f"/api/v1/flags/{flag_id}/convert",
            json={
                "trade_scope_id": scope_id,
                "priority": "high",
            },
        )
        assert convert_resp.status_code == 200, f"Convert failed: {convert_resp.text}"
        punch_data = convert_resp.json()
        assert punch_data["description"] == "Exposed wiring near panel"
        assert punch_data["source_flag_id"] == flag_id
        assert punch_data["priority"] == "high"
        assert punch_data["status"] == "open"
        assert punch_data["trade_scope_id"] == scope_id

        # Verify flag status is now 'converted'
        list_resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/flags")
        assert list_resp.status_code == 200
        flags = list_resp.json()
        converted_flags = [f for f in flags if f["id"] == flag_id]
        assert len(converted_flags) == 1
        assert converted_flags[0]["status"] == "converted"

    async def test_convert_already_converted_flag_returns_422(
        self, tenant_a_client: AsyncClient
    ) -> None:
        """Converting an already-converted flag returns 422."""
        project_id = await _create_project(tenant_a_client, "Double Convert Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)

        flag_resp = await _create_flag(
            tenant_a_client,
            project_id,
            description="Issue for double convert test",
        )
        assert flag_resp.status_code == 201
        flag_id = flag_resp.json()["id"]

        # First conversion — should succeed
        r1 = await tenant_a_client.patch(
            f"/api/v1/flags/{flag_id}/convert",
            json={"trade_scope_id": scope_id, "priority": "medium"},
        )
        assert r1.status_code == 200

        # Second conversion — should fail with 422
        r2 = await tenant_a_client.patch(
            f"/api/v1/flags/{flag_id}/convert",
            json={"trade_scope_id": scope_id, "priority": "low"},
        )
        assert r2.status_code == 422, f"Expected 422, got {r2.status_code}: {r2.text}"

    async def test_flags_isolated_by_project(self, tenant_a_client: AsyncClient) -> None:
        """Flags for project A do not appear in project B's list."""
        proj_a = await _create_project(tenant_a_client, "Flag Isolation A")
        proj_b = await _create_project(tenant_a_client, "Flag Isolation B")

        # Create 2 flags for project A, 1 flag for project B
        for i in range(2):
            await _create_flag(tenant_a_client, proj_a, description=f"A Flag {i}")
        await _create_flag(tenant_a_client, proj_b, description="B Flag")

        a_flags = (await tenant_a_client.get(f"/api/v1/projects/{proj_a}/flags")).json()
        b_flags = (await tenant_a_client.get(f"/api/v1/projects/{proj_b}/flags")).json()

        assert len(a_flags) == 2
        assert len(b_flags) == 1
