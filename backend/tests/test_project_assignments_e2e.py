"""E2E tests for project assignments (sub-feature A).

Covers assigning people to a project with project-level roles (project_manager,
contractor, foreman, …), listing, unassigning, validation, and RLS isolation.

Uses the shared conftest fixtures: seed_two_tenants registers two companies each
with an admin user; tenant_a_client / tenant_b_client have Bearer tokens pre-set.
"""

import uuid

from httpx import AsyncClient


async def _create_project(client: AsyncClient, name: str = "Assignment Project") -> str:
    resp = await client.post("/api/v1/projects/", json={"name": name})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


class TestProjectAssignments:
    async def test_assign_project_manager(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)
        user_id = seed_two_tenants["tenant_a_user_id"]

        resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/assignments",
            json={"user_id": user_id, "role": "project_manager"},
        )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        assert body["role"] == "project_manager"
        assert body["user_id"] == user_id
        assert body["user_name"]  # denormalized name populated

    async def test_assign_pm_and_contractor_both_listed(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)
        user_id = seed_two_tenants["tenant_a_user_id"]

        for role in ("project_manager", "contractor"):
            resp = await tenant_a_client.post(
                f"/api/v1/projects/{project_id}/assignments",
                json={"user_id": user_id, "role": role},
            )
            assert resp.status_code == 201, resp.text

        list_resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/assignments")
        assert list_resp.status_code == 200
        roles = {a["role"] for a in list_resp.json()}
        assert roles == {"project_manager", "contractor"}

    async def test_invalid_role_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)
        user_id = seed_two_tenants["tenant_a_user_id"]

        resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/assignments",
            json={"user_id": user_id, "role": "wizard"},
        )
        assert resp.status_code == 422

    async def test_assign_unknown_user_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)

        resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/assignments",
            json={"user_id": str(uuid.uuid4()), "role": "project_manager"},
        )
        assert resp.status_code == 400

    async def test_unassign_removes_from_list(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)
        user_id = seed_two_tenants["tenant_a_user_id"]

        assign_resp = await tenant_a_client.post(
            f"/api/v1/projects/{project_id}/assignments",
            json={"user_id": user_id, "role": "project_manager"},
        )
        assignment_id = assign_resp.json()["id"]

        del_resp = await tenant_a_client.delete(
            f"/api/v1/projects/{project_id}/assignments/{assignment_id}"
        )
        assert del_resp.status_code == 204

        list_resp = await tenant_a_client.get(f"/api/v1/projects/{project_id}/assignments")
        assert list_resp.json() == []

    async def test_rls_isolation_cannot_assign_to_other_tenant_project(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        # Tenant A owns the project; tenant B must not be able to assign to it.
        project_id = await _create_project(tenant_a_client)
        tenant_b_user_id = seed_two_tenants["tenant_b_user_id"]

        resp = await tenant_b_client.post(
            f"/api/v1/projects/{project_id}/assignments",
            json={"user_id": tenant_b_user_id, "role": "project_manager"},
        )
        # RLS hides tenant A's project from tenant B → project not found.
        assert resp.status_code == 404
