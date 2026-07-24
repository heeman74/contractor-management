"""E2E tests for job ↔ project linkage and job manager assignment.

Sub-feature B (migration 0030): jobs.project_id — create/update with a project,
project_name denormalization, list filtering, validation, RLS isolation.
Sub-feature C (migration 0031): jobs.manager_id — assign a project manager to a
job, manager_name denormalization, validation, RLS isolation.

Uses the shared conftest fixtures (seed_two_tenants / tenant_a_client / tenant_b_client).
"""

import uuid

from httpx import AsyncClient


async def _create_project(client: AsyncClient, name: str = "Linked Project") -> str:
    resp = await client.post("/api/v1/projects/", json={"name": name})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_job(client: AsyncClient, **overrides) -> dict:
    payload = {"description": "Job for project link", "trade_type": "plumber", **overrides}
    resp = await client.post("/api/v1/jobs/", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


class TestJobProjectLink:
    async def test_create_job_with_project(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)
        job = await _create_job(tenant_a_client, project_id=project_id)
        assert job["project_id"] == project_id

        # Detail resolves the denormalized project_name from the eager-loaded link
        detail = await tenant_a_client.get(f"/api/v1/jobs/{job['id']}")
        assert detail.status_code == 200
        assert detail.json()["project_name"] == "Linked Project"

    async def test_create_job_without_project_still_works(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        job = await _create_job(tenant_a_client)
        assert job["project_id"] is None
        assert job["project_name"] is None

    async def test_link_existing_job_via_patch(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)
        job = await _create_job(tenant_a_client)

        patch = await tenant_a_client.patch(
            f"/api/v1/jobs/{job['id']}", json={"project_id": project_id}
        )
        assert patch.status_code == 200, patch.text
        assert patch.json()["project_id"] == project_id

    async def test_list_jobs_filtered_by_project(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        project_id = await _create_project(tenant_a_client)
        linked = await _create_job(tenant_a_client, project_id=project_id)
        await _create_job(tenant_a_client)  # unlinked job

        resp = await tenant_a_client.get(f"/api/v1/jobs/?project_id={project_id}")
        assert resp.status_code == 200
        jobs = resp.json()
        assert [j["id"] for j in jobs] == [linked["id"]]
        assert jobs[0]["project_name"] == "Linked Project"

    async def test_unknown_project_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        resp = await tenant_a_client.post(
            "/api/v1/jobs/",
            json={
                "description": "Bad link",
                "trade_type": "plumber",
                "project_id": str(uuid.uuid4()),
            },
        )
        assert resp.status_code == 400

    async def test_rls_isolation_cannot_link_other_tenant_project(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        # Tenant A owns the project; tenant B must not be able to link a job to it.
        project_id = await _create_project(tenant_a_client)

        resp = await tenant_b_client.post(
            "/api/v1/jobs/",
            json={
                "description": "Cross-tenant link attempt",
                "trade_type": "plumber",
                "project_id": project_id,
            },
        )
        # RLS hides tenant A's project from tenant B → validation fails with 400.
        assert resp.status_code == 400


class TestJobManager:
    async def test_create_job_with_manager(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        # Create a named team member to act as the job's project manager
        user_resp = await tenant_a_client.post(
            "/api/v1/users/",
            json={"email": "pm@tenant-a.com", "first_name": "Paula", "last_name": "Manager"},
        )
        assert user_resp.status_code == 201, user_resp.text
        manager_id = user_resp.json()["id"]

        job = await _create_job(tenant_a_client, manager_id=manager_id)
        assert job["manager_id"] == manager_id

        # Detail resolves the denormalized manager_name from the eager-loaded link
        detail = await tenant_a_client.get(f"/api/v1/jobs/{job['id']}")
        assert detail.status_code == 200
        body = detail.json()
        assert body["manager_id"] == manager_id
        assert body["manager_name"] == "Paula Manager"

    async def test_assign_manager_via_patch(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        manager_id = seed_two_tenants["tenant_a_user_id"]
        job = await _create_job(tenant_a_client)
        assert job["manager_id"] is None

        patch = await tenant_a_client.patch(
            f"/api/v1/jobs/{job['id']}", json={"manager_id": manager_id}
        )
        assert patch.status_code == 200, patch.text
        assert patch.json()["manager_id"] == manager_id

    async def test_unknown_manager_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        resp = await tenant_a_client.post(
            "/api/v1/jobs/",
            json={
                "description": "Bad manager",
                "trade_type": "plumber",
                "manager_id": str(uuid.uuid4()),
            },
        )
        assert resp.status_code == 400

    async def test_rls_isolation_cannot_assign_other_tenant_manager(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        # Tenant B's user must not be assignable as manager on a tenant A job.
        tenant_b_user_id = seed_two_tenants["tenant_b_user_id"]

        resp = await tenant_a_client.post(
            "/api/v1/jobs/",
            json={
                "description": "Cross-tenant manager attempt",
                "trade_type": "plumber",
                "manager_id": tenant_b_user_id,
            },
        )
        # RLS hides tenant B's user from tenant A → validation fails with 400.
        assert resp.status_code == 400
