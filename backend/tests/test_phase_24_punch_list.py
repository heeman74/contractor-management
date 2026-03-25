"""Phase 24 backend integration tests — INSP-03: Punch list items.

Tests cover:
1. Create punch list item directly (without flag) — 201
2. List punch items for scope — scoped correctly
3. Update punch item status — status changes
4. Full status lifecycle: open -> in_progress -> resolved -> verified
5. Punch item created via flag conversion has source_flag_id populated

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


async def _create_project(client: AsyncClient, name: str = "Punch List Project") -> str:
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


async def _create_punch_item(
    client: AsyncClient,
    project_id: str,
    trade_scope_id: str,
    description: str = "Fix outlet",
    priority: str = "medium",
):  # type: ignore[return]
    """Create a punch list item and return the response object."""
    return await client.post(
        f"/api/v1/projects/{project_id}/punch-items",
        json={
            "trade_scope_id": trade_scope_id,
            "description": description,
            "priority": priority,
        },
    )


# ---------------------------------------------------------------------------
# INSP-03: Punch list item tests
# ---------------------------------------------------------------------------


class TestPunchListItems:
    async def test_create_punch_item(self, tenant_a_client: AsyncClient) -> None:
        """Create a punch list item directly — 201, all fields present."""
        project_id = await _create_project(tenant_a_client, "Create Punch Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)

        resp = await _create_punch_item(
            tenant_a_client,
            project_id,
            scope_id,
            description="Fix outlet",
            priority="urgent",
        )
        assert resp.status_code == 201, f"Punch item creation failed: {resp.text}"
        data = resp.json()
        assert data["description"] == "Fix outlet"
        assert data["priority"] == "urgent"
        assert data["status"] == "open"
        assert data["project_id"] == project_id
        assert data["trade_scope_id"] == scope_id
        assert data["source_flag_id"] is None

    async def test_list_punch_items_for_scope(self, tenant_a_client: AsyncClient) -> None:
        """Create items for two scopes — list by scope returns only scope A items."""
        project_id = await _create_project(tenant_a_client, "List Scope Punch Project")
        scope_a = await _create_trade_scope(tenant_a_client, project_id, "Electrical")
        scope_b = await _create_trade_scope(tenant_a_client, project_id, "Plumbing")

        # 2 items for scope A, 1 for scope B
        for i in range(2):
            r = await _create_punch_item(
                tenant_a_client, project_id, scope_a, description=f"Scope A Item {i + 1}"
            )
            assert r.status_code == 201

        r_b = await _create_punch_item(
            tenant_a_client, project_id, scope_b, description="Scope B Item"
        )
        assert r_b.status_code == 201

        list_resp = await tenant_a_client.get(f"/api/v1/trade-scopes/{scope_a}/punch-items")
        assert list_resp.status_code == 200
        items = list_resp.json()
        assert len(items) == 2
        for item in items:
            assert item["trade_scope_id"] == scope_a

    async def test_update_punch_item_status(self, tenant_a_client: AsyncClient) -> None:
        """Update a punch item's status — status changes correctly."""
        project_id = await _create_project(tenant_a_client, "Update Status Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)

        create_resp = await _create_punch_item(
            tenant_a_client, project_id, scope_id, description="Repair drywall"
        )
        assert create_resp.status_code == 201
        item_id = create_resp.json()["id"]

        # Update status to in_progress
        update_resp = await tenant_a_client.patch(
            f"/api/v1/punch-items/{item_id}",
            json={"status": "in_progress"},
        )
        assert update_resp.status_code == 200, f"Update failed: {update_resp.text}"
        assert update_resp.json()["status"] == "in_progress"

    async def test_punch_item_status_lifecycle(self, tenant_a_client: AsyncClient) -> None:
        """Walk through full punch item lifecycle: open -> in_progress -> resolved -> verified."""
        project_id = await _create_project(tenant_a_client, "Lifecycle Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)

        create_resp = await _create_punch_item(
            tenant_a_client, project_id, scope_id, description="Full lifecycle item"
        )
        assert create_resp.status_code == 201
        item_id = create_resp.json()["id"]
        assert create_resp.json()["status"] == "open"

        for expected_status in ("in_progress", "resolved", "verified"):
            resp = await tenant_a_client.patch(
                f"/api/v1/punch-items/{item_id}",
                json={"status": expected_status},
            )
            assert resp.status_code == 200, (
                f"Status transition to '{expected_status}' failed: {resp.text}"
            )
            assert resp.json()["status"] == expected_status, (
                f"Expected status='{expected_status}', got '{resp.json()['status']}'"
            )

    async def test_punch_item_has_source_flag_when_converted(
        self, tenant_a_client: AsyncClient
    ) -> None:
        """Punch item created via flag conversion has source_flag_id populated."""
        project_id = await _create_project(tenant_a_client, "Source Flag Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)

        # Create a flag
        flag_resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/flags",
            json={"description": "Pipe leak near east wall", "severity": "high"},
        )
        assert flag_resp.status_code == 201
        flag_id = flag_resp.json()["id"]

        # Convert flag to punch item
        convert_resp = await tenant_a_client.patch(
            f"/api/v1/flags/{flag_id}/convert",
            json={"trade_scope_id": scope_id, "priority": "high"},
        )
        assert convert_resp.status_code == 200
        punch_data = convert_resp.json()
        assert punch_data["source_flag_id"] == flag_id
        assert punch_data["description"] == "Pipe leak near east wall"

        # List punch items for scope — verify source_flag_id is set
        list_resp = await tenant_a_client.get(f"/api/v1/trade-scopes/{scope_id}/punch-items")
        assert list_resp.status_code == 200
        items = list_resp.json()
        assert len(items) == 1
        assert items[0]["source_flag_id"] == flag_id

    async def test_update_punch_item_priority(self, tenant_a_client: AsyncClient) -> None:
        """Update punch item priority in addition to status."""
        project_id = await _create_project(tenant_a_client, "Priority Update Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)

        create_resp = await _create_punch_item(
            tenant_a_client, project_id, scope_id, priority="low"
        )
        assert create_resp.status_code == 201
        item_id = create_resp.json()["id"]

        # Escalate priority
        update_resp = await tenant_a_client.patch(
            f"/api/v1/punch-items/{item_id}",
            json={"priority": "urgent"},
        )
        assert update_resp.status_code == 200
        assert update_resp.json()["priority"] == "urgent"
