"""Phase 20 — Dependency Engine E2E Tests.

Integration tests covering:
- PROJ-04: Task dependency creation, cycle detection, blocked status
- AI-06: Zone-based conflict detection

Strategy:
- Uses tenant_a_client / seed_two_tenants fixtures from conftest.py.
- All tests are @pytest.mark.anyio async tests.
- Each test class creates its own project/scopes/tasks as needed.
- seed_two_tenants registers two companies; each client has an admin user.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient

# Ensure all SQLAlchemy mappers are configured before tests run.
import app.features.projects.models  # noqa: F401

pytestmark = pytest.mark.anyio


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def create_project(client: AsyncClient, name: str = "Test Project") -> str:
    """Create a project and return its ID."""
    resp = await client.post("/api/v1/projects/", json={"name": name})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def create_scope(client: AsyncClient, project_id: str, trade_name: str) -> str:
    """Create a trade scope and return its ID."""
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def create_task(
    client: AsyncClient,
    scope_id: str,
    title: str,
    due_date: str | None = None,
    zone_id: str | None = None,
) -> str:
    """Create a task and return its ID."""
    payload: dict = {"trade_scope_id": scope_id, "title": title}
    if due_date:
        payload["due_date"] = due_date
    if zone_id:
        payload["zone_id"] = zone_id
    resp = await client.post("/api/v1/tasks/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def create_zone(client: AsyncClient, project_id: str, name: str) -> str:
    """Create a project zone and return its ID."""
    resp = await client.post(
        f"/api/v1/projects/{project_id}/zones",
        json={"name": name},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def create_dependency(
    client: AsyncClient,
    successor_id: str,
    predecessor_id: str,
    dep_type: str = "FS",
) -> dict:
    """Create a dependency edge and return the response JSON."""
    resp = await client.post(
        f"/api/v1/tasks/{successor_id}/dependencies",
        json={"predecessor_task_id": predecessor_id, "dependency_type": dep_type},
    )
    return resp


# ---------------------------------------------------------------------------
# PROJ-04: Task dependencies — creation, cycles, blocked status
# ---------------------------------------------------------------------------


class TestDependencyCreation:
    """Basic dependency CRUD."""

    async def test_create_fs_dependency(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """POST creates an FS dependency edge, returns 201 with edge record."""
        project_id = await create_project(tenant_a_client, "Dep Test Project")
        scope_id = await create_scope(tenant_a_client, project_id, "Electrical")
        task_a = await create_task(tenant_a_client, scope_id, "Run conduit")
        task_b = await create_task(tenant_a_client, scope_id, "Pull wire")

        resp = await create_dependency(tenant_a_client, task_b, task_a)
        assert resp.status_code == 201, resp.text
        data = resp.json()
        assert data["predecessor_task_id"] == task_a
        assert data["successor_task_id"] == task_b
        assert data["dependency_type"] == "FS"
        assert data["lag_days"] == 0
        assert "id" in data

    async def test_create_dependency_with_lag(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """POST with lag_days stores the lag value correctly."""
        project_id = await create_project(tenant_a_client)
        scope_id = await create_scope(tenant_a_client, project_id, "Plumbing")
        task_a = await create_task(tenant_a_client, scope_id, "Rough-in")
        task_b = await create_task(tenant_a_client, scope_id, "Inspect")

        resp = await client_post_dep(
            tenant_a_client, task_b, task_a, dep_type="SS", lag_days=2
        )
        assert resp.status_code == 201
        assert resp.json()["lag_days"] == 2
        assert resp.json()["dependency_type"] == "SS"

    async def test_list_dependencies(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """GET /tasks/{id}/dependencies returns all edges for the task."""
        project_id = await create_project(tenant_a_client)
        scope_id = await create_scope(tenant_a_client, project_id, "Framing")
        task_a = await create_task(tenant_a_client, scope_id, "Frame walls")
        task_b = await create_task(tenant_a_client, scope_id, "Install doors")
        task_c = await create_task(tenant_a_client, scope_id, "Drywall")

        # B depends on A; C depends on B
        await create_dependency(tenant_a_client, task_b, task_a)
        await create_dependency(tenant_a_client, task_c, task_b)

        # task_b appears as both successor (A->B) and predecessor (B->C)
        resp = await tenant_a_client.get(f"/api/v1/tasks/{task_b}/dependencies")
        assert resp.status_code == 200
        edges = resp.json()
        assert len(edges) == 2

    async def test_delete_dependency(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """DELETE /dependencies/{id} returns 204 and removes the edge."""
        project_id = await create_project(tenant_a_client)
        scope_id = await create_scope(tenant_a_client, project_id, "HVAC")
        task_a = await create_task(tenant_a_client, scope_id, "Ductwork")
        task_b = await create_task(tenant_a_client, scope_id, "Insulate ducts")

        # Create edge
        create_resp = await create_dependency(tenant_a_client, task_b, task_a)
        assert create_resp.status_code == 201
        dep_id = create_resp.json()["id"]

        # Delete edge
        del_resp = await tenant_a_client.delete(f"/api/v1/dependencies/{dep_id}")
        assert del_resp.status_code == 204

        # Verify it's gone
        list_resp = await tenant_a_client.get(f"/api/v1/tasks/{task_b}/dependencies")
        assert list_resp.status_code == 200
        assert list_resp.json() == []

    async def test_delete_nonexistent_dependency_returns_404(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """DELETE on nonexistent dependency ID returns 404."""
        import uuid

        fake_id = str(uuid.uuid4())
        resp = await tenant_a_client.delete(f"/api/v1/dependencies/{fake_id}")
        assert resp.status_code == 404


# ---------------------------------------------------------------------------
# PROJ-04: Cycle detection
# ---------------------------------------------------------------------------


class TestCycleDetection:
    """DFS cycle detection rejects circular dependency graphs."""

    async def test_cycle_rejected_422(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """A->B->C->A cycle returns 422 with cycle path in detail."""
        project_id = await create_project(tenant_a_client, "Cycle Test")
        scope_id = await create_scope(tenant_a_client, project_id, "General")
        task_a = await create_task(tenant_a_client, scope_id, "Task A")
        task_b = await create_task(tenant_a_client, scope_id, "Task B")
        task_c = await create_task(tenant_a_client, scope_id, "Task C")

        # A->B, B->C (these are valid)
        r1 = await create_dependency(tenant_a_client, task_b, task_a)
        assert r1.status_code == 201
        r2 = await create_dependency(tenant_a_client, task_c, task_b)
        assert r2.status_code == 201

        # C->A would close the cycle — must be rejected
        r3 = await create_dependency(tenant_a_client, task_a, task_c)
        assert r3.status_code == 422
        detail = r3.json()["detail"]
        assert "cycle" in detail or "Cycle" in str(detail)

    async def test_self_loop_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """A task depending on itself is rejected (DB CHECK constraint or service layer)."""
        project_id = await create_project(tenant_a_client)
        scope_id = await create_scope(tenant_a_client, project_id, "Self Loop")
        task_a = await create_task(tenant_a_client, scope_id, "Self loop task")

        # Self-loop: A->A
        resp = await tenant_a_client.post(
            f"/api/v1/tasks/{task_a}/dependencies",
            json={"predecessor_task_id": task_a, "dependency_type": "FS"},
        )
        # Should be rejected — either by service (422) or DB constraint (422/500)
        assert resp.status_code in (400, 422, 500)

    async def test_direct_cycle_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """A->B and then B->A (direct cycle) is rejected."""
        project_id = await create_project(tenant_a_client)
        scope_id = await create_scope(tenant_a_client, project_id, "Direct Cycle")
        task_a = await create_task(tenant_a_client, scope_id, "Task A")
        task_b = await create_task(tenant_a_client, scope_id, "Task B")

        r1 = await create_dependency(tenant_a_client, task_b, task_a)
        assert r1.status_code == 201

        r2 = await create_dependency(tenant_a_client, task_a, task_b)
        assert r2.status_code == 422


# ---------------------------------------------------------------------------
# PROJ-04: Blocked status auto-computation
# ---------------------------------------------------------------------------


class TestBlockedStatus:
    """Blocked status is auto-computed from dependency state."""

    async def test_task_blocked_by_dependency(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Creating a FS dependency with an incomplete predecessor blocks the successor."""
        project_id = await create_project(tenant_a_client, "Blocked Status Test")
        scope_id = await create_scope(tenant_a_client, project_id, "Painting")
        task_a = await create_task(tenant_a_client, scope_id, "Prime walls")
        task_b = await create_task(tenant_a_client, scope_id, "Paint walls")

        # B depends on A (A is not_started, so B should become blocked)
        dep_resp = await create_dependency(tenant_a_client, task_b, task_a)
        assert dep_resp.status_code == 201

        # Check task B is now blocked
        tasks_resp = await tenant_a_client.get(
            f"/api/v1/tasks/?trade_scope_id={scope_id}"
        )
        assert tasks_resp.status_code == 200
        tasks = {t["id"]: t for t in tasks_resp.json()}
        assert tasks[task_b]["status"] == "blocked"
        # Task A should remain not_started
        assert tasks[task_a]["status"] == "not_started"

    async def test_task_unblocked_on_completion(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Completing a predecessor unblocks the successor task."""
        project_id = await create_project(tenant_a_client, "Unblock Test")
        scope_id = await create_scope(tenant_a_client, project_id, "Tiling")
        task_a = await create_task(tenant_a_client, scope_id, "Prep subfloor")
        task_b = await create_task(tenant_a_client, scope_id, "Lay tile")

        # Set up dependency: B depends on A
        dep_resp = await create_dependency(tenant_a_client, task_b, task_a)
        assert dep_resp.status_code == 201

        # Verify B is blocked
        tasks_resp = await tenant_a_client.get(
            f"/api/v1/tasks/?trade_scope_id={scope_id}"
        )
        tasks = {t["id"]: t for t in tasks_resp.json()}
        assert tasks[task_b]["status"] == "blocked"

        # Complete task A
        update_resp = await tenant_a_client.patch(
            f"/api/v1/tasks/{task_a}", json={"status": "complete"}
        )
        assert update_resp.status_code == 200

        # Task B should now be unblocked (not_started)
        tasks_resp2 = await tenant_a_client.get(
            f"/api/v1/tasks/?trade_scope_id={scope_id}"
        )
        tasks2 = {t["id"]: t for t in tasks_resp2.json()}
        assert tasks2[task_b]["status"] == "not_started"

    async def test_delete_dependency_unblocks_successor(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Deleting the only blocking dependency unblocks the successor."""
        project_id = await create_project(tenant_a_client)
        scope_id = await create_scope(tenant_a_client, project_id, "Masonry")
        task_a = await create_task(tenant_a_client, scope_id, "Pour foundation")
        task_b = await create_task(tenant_a_client, scope_id, "Build walls")

        # Create dependency and verify B is blocked
        dep_resp = await create_dependency(tenant_a_client, task_b, task_a)
        assert dep_resp.status_code == 201
        dep_id = dep_resp.json()["id"]

        tasks_resp = await tenant_a_client.get(
            f"/api/v1/tasks/?trade_scope_id={scope_id}"
        )
        tasks = {t["id"]: t for t in tasks_resp.json()}
        assert tasks[task_b]["status"] == "blocked"

        # Delete the dependency
        del_resp = await tenant_a_client.delete(f"/api/v1/dependencies/{dep_id}")
        assert del_resp.status_code == 204

        # Task B should now be not_started
        tasks_resp2 = await tenant_a_client.get(
            f"/api/v1/tasks/?trade_scope_id={scope_id}"
        )
        tasks2 = {t["id"]: t for t in tasks_resp2.json()}
        assert tasks2[task_b]["status"] == "not_started"

    async def test_ff_dependency_does_not_block(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """FF dependency type does not set successor to blocked (only FS/SS/SE do)."""
        project_id = await create_project(tenant_a_client)
        scope_id = await create_scope(tenant_a_client, project_id, "Carpentry")
        task_a = await create_task(tenant_a_client, scope_id, "Cut lumber")
        task_b = await create_task(tenant_a_client, scope_id, "Sand lumber")

        resp = await client_post_dep(tenant_a_client, task_b, task_a, dep_type="FF")
        assert resp.status_code == 201

        # FF does not block — task_b should remain not_started
        tasks_resp = await tenant_a_client.get(
            f"/api/v1/tasks/?trade_scope_id={scope_id}"
        )
        tasks = {t["id"]: t for t in tasks_resp.json()}
        assert tasks[task_b]["status"] == "not_started"


# ---------------------------------------------------------------------------
# AI-06: Project zones
# ---------------------------------------------------------------------------


class TestProjectZones:
    """Zone CRUD for conflict detection."""

    async def test_create_zone(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """POST creates zone, returns 201 with id and project_id."""
        project_id = await create_project(tenant_a_client, "Zone Test Project")
        resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/zones",
            json={"name": "Kitchen"},
        )
        assert resp.status_code == 201, resp.text
        data = resp.json()
        assert data["name"] == "Kitchen"
        assert data["project_id"] == project_id
        assert "id" in data

    async def test_list_zones(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """GET /projects/{id}/zones returns all zones for the project."""
        project_id = await create_project(tenant_a_client)
        await create_zone(tenant_a_client, project_id, "Bathroom")
        await create_zone(tenant_a_client, project_id, "Kitchen")

        resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/zones")
        assert resp.status_code == 200
        zones = resp.json()
        names = [z["name"] for z in zones]
        assert "Bathroom" in names
        assert "Kitchen" in names
        assert len(zones) == 2

    async def test_duplicate_zone_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Two zones with the same name in the same project are rejected."""
        project_id = await create_project(tenant_a_client)
        await create_zone(tenant_a_client, project_id, "Master Bath")

        # Duplicate name
        resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/zones",
            json={"name": "Master Bath"},
        )
        # DB UNIQUE constraint violation → 422 or 500
        assert resp.status_code in (409, 422, 500)

    async def test_delete_zone(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """DELETE /zones/{id} returns 204."""
        project_id = await create_project(tenant_a_client)
        zone_id = await create_zone(tenant_a_client, project_id, "Garage")

        del_resp = await tenant_a_client.delete(f"/api/v1/zones/{zone_id}")
        assert del_resp.status_code == 204

        # Zone should no longer appear in list
        list_resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/zones")
        zones = list_resp.json()
        zone_ids = [z["id"] for z in zones]
        assert zone_id not in zone_ids

    async def test_zones_isolated_between_tenants(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        """Tenant A's zones are not visible to Tenant B."""
        project_a = await create_project(tenant_a_client, "Tenant A Project")
        zone_a = await create_zone(tenant_a_client, project_a, "Living Room")

        # Tenant B tries to list Tenant A's zones — RLS returns empty
        resp = await tenant_b_client.get(f"/api/v1/projects/{project_a}/zones")
        assert resp.status_code == 200
        assert resp.json() == []


# ---------------------------------------------------------------------------
# AI-06: Conflict detection
# ---------------------------------------------------------------------------


class TestConflictDetection:
    """Zone-based scheduling conflict detection."""

    async def test_conflict_detected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Two tasks from different trade scopes in the same zone on the same day → conflict."""
        project_id = await create_project(tenant_a_client, "Conflict Test Project")
        scope_elec = await create_scope(tenant_a_client, project_id, "Electrical")
        scope_plumb = await create_scope(tenant_a_client, project_id, "Plumbing")
        zone_id = await create_zone(tenant_a_client, project_id, "Kitchen")

        # Both tasks in the same zone on the same day
        await create_task(
            tenant_a_client, scope_elec, "Install outlets", "2026-05-01", zone_id
        )
        await create_task(
            tenant_a_client, scope_plumb, "Install sink", "2026-05-01", zone_id
        )

        resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/conflicts")
        assert resp.status_code == 200
        conflicts = resp.json()
        assert len(conflicts) == 1
        c = conflicts[0]
        assert c["zone_name"] == "Kitchen"
        assert c["conflict_date"] == "2026-05-01"
        # Both task IDs appear in the conflict record
        task_ids = {c["task1_id"], c["task2_id"]}
        assert len(task_ids) == 2

    async def test_no_conflict_different_zones(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Tasks from different trade scopes in different zones on the same day → no conflict."""
        project_id = await create_project(tenant_a_client, "Different Zones")
        scope_elec = await create_scope(tenant_a_client, project_id, "Electrical")
        scope_plumb = await create_scope(tenant_a_client, project_id, "Plumbing")
        zone_kitchen = await create_zone(tenant_a_client, project_id, "Kitchen")
        zone_bath = await create_zone(tenant_a_client, project_id, "Bathroom")

        await create_task(
            tenant_a_client, scope_elec, "Kitchen outlets", "2026-05-01", zone_kitchen
        )
        await create_task(
            tenant_a_client, scope_plumb, "Bath plumbing", "2026-05-01", zone_bath
        )

        resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/conflicts")
        assert resp.status_code == 200
        assert resp.json() == []

    async def test_no_conflict_different_dates(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Tasks in the same zone but on different dates → no conflict."""
        project_id = await create_project(tenant_a_client, "Different Dates")
        scope_elec = await create_scope(tenant_a_client, project_id, "Electrical")
        scope_plumb = await create_scope(tenant_a_client, project_id, "Plumbing")
        zone_id = await create_zone(tenant_a_client, project_id, "Master Bath")

        await create_task(
            tenant_a_client, scope_elec, "Wiring", "2026-05-01", zone_id
        )
        await create_task(
            tenant_a_client, scope_plumb, "Pipes", "2026-05-02", zone_id
        )

        resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/conflicts")
        assert resp.status_code == 200
        assert resp.json() == []

    async def test_no_conflict_same_trade_scope(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Two tasks from the SAME trade scope in the same zone on the same day → no conflict."""
        project_id = await create_project(tenant_a_client, "Same Scope")
        scope_id = await create_scope(tenant_a_client, project_id, "Electrical")
        zone_id = await create_zone(tenant_a_client, project_id, "Basement")

        await create_task(
            tenant_a_client, scope_id, "Outlets", "2026-05-01", zone_id
        )
        await create_task(
            tenant_a_client, scope_id, "Switches", "2026-05-01", zone_id
        )

        resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/conflicts")
        assert resp.status_code == 200
        assert resp.json() == []

    async def test_no_conflict_no_zone(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Tasks without zone_id set don't trigger conflicts."""
        project_id = await create_project(tenant_a_client, "No Zone")
        scope_elec = await create_scope(tenant_a_client, project_id, "Electrical")
        scope_plumb = await create_scope(tenant_a_client, project_id, "Plumbing")

        # Tasks without zone_id
        await create_task(tenant_a_client, scope_elec, "Wiring", "2026-05-01")
        await create_task(tenant_a_client, scope_plumb, "Pipes", "2026-05-01")

        resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/conflicts")
        assert resp.status_code == 200
        assert resp.json() == []

    async def test_multiple_conflicts_detected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Multiple conflicts in different zones on different days are all returned."""
        project_id = await create_project(tenant_a_client, "Multi Conflict")
        scope_elec = await create_scope(tenant_a_client, project_id, "Electrical")
        scope_plumb = await create_scope(tenant_a_client, project_id, "Plumbing")
        zone_kitchen = await create_zone(tenant_a_client, project_id, "Kitchen")
        zone_bath = await create_zone(tenant_a_client, project_id, "Bathroom")

        # Two separate conflicts: Kitchen on May 1, Bathroom on May 2
        await create_task(
            tenant_a_client, scope_elec, "Kitchen E", "2026-05-01", zone_kitchen
        )
        await create_task(
            tenant_a_client, scope_plumb, "Kitchen P", "2026-05-01", zone_kitchen
        )
        await create_task(
            tenant_a_client, scope_elec, "Bath E", "2026-05-02", zone_bath
        )
        await create_task(
            tenant_a_client, scope_plumb, "Bath P", "2026-05-02", zone_bath
        )

        resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/conflicts")
        assert resp.status_code == 200
        conflicts = resp.json()
        assert len(conflicts) == 2


# ---------------------------------------------------------------------------
# Cross-project dependency isolation
# ---------------------------------------------------------------------------


class TestCrossProjectIsolation:
    """Dependencies cannot span across projects."""

    async def test_dependency_cross_project_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Creating a dependency between tasks in different projects returns 400."""
        project_1 = await create_project(tenant_a_client, "Project 1")
        project_2 = await create_project(tenant_a_client, "Project 2")
        scope_1 = await create_scope(tenant_a_client, project_1, "Electrical")
        scope_2 = await create_scope(tenant_a_client, project_2, "Plumbing")
        task_1 = await create_task(tenant_a_client, scope_1, "Task in Project 1")
        task_2 = await create_task(tenant_a_client, scope_2, "Task in Project 2")

        resp = await tenant_a_client.post(
            f"/api/v1/tasks/{task_2}/dependencies",
            json={"predecessor_task_id": task_1, "dependency_type": "FS"},
        )
        assert resp.status_code == 400


# ---------------------------------------------------------------------------
# Helper: post with explicit lag_days parameter
# ---------------------------------------------------------------------------


async def client_post_dep(
    client: AsyncClient,
    successor_id: str,
    predecessor_id: str,
    dep_type: str = "FS",
    lag_days: int = 0,
):
    """Create a dependency with explicit lag_days."""
    return await client.post(
        f"/api/v1/tasks/{successor_id}/dependencies",
        json={
            "predecessor_task_id": predecessor_id,
            "dependency_type": dep_type,
            "lag_days": lag_days,
        },
    )
