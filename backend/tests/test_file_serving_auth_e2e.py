"""E2E tests for authenticated, tenant-scoped file serving (serve_router).

Regression guard for the StaticFiles auth fix: uploaded files must require a
valid token and must not cross tenant boundaries. Uploads a real image via the
API (writes to disk + returns a /files/images/... URL) and probes the serve
endpoint under different callers.
"""

from uuid import UUID, uuid4

from httpx import AsyncClient

from app.core.security import create_access_token

_PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


async def _upload_image(client: AsyncClient) -> str:
    resp = await client.post(
        "/api/v1/files/images",
        files={"file": ("site.png", _PNG_BYTES, "image/png")},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["remote_url"]


async def _upload_task_photo(client: AsyncClient) -> str:
    """Build a project -> trade_scope -> task and upload a photo, returning its
    /files/task-attachments/... remote_url."""
    project = await client.post("/api/v1/projects/", json={"name": "Media Test Project"})
    assert project.status_code == 201, project.text
    scope = await client.post(
        "/api/v1/trade-scopes/",
        json={
            "project_id": project.json()["id"],
            "trade_name": "Electrical",
            "trade_color": "#FF5733",
        },
    )
    assert scope.status_code == 201, scope.text
    task = await client.post(
        "/api/v1/tasks/",
        json={"trade_scope_id": scope.json()["id"], "title": "Install breaker panel"},
    )
    assert task.status_code == 201, task.text
    resp = await client.post(
        f"/api/v1/tasks/{task.json()['id']}/attachments",
        files={"file": ("progress.png", _PNG_BYTES, "image/png")},
        data={"attachment_type": "photo"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["remote_url"]


class TestFileServingAuth:
    async def test_owner_can_fetch_own_image(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        remote_url = await _upload_image(tenant_a_client)
        resp = await tenant_a_client.get(remote_url)
        assert resp.status_code == 200
        assert resp.content == _PNG_BYTES
        # Global SecurityHeadersMiddleware forces nosniff on every response.
        assert "nosniff" in resp.headers.get("x-content-type-options", "")

    async def test_unauthenticated_request_rejected(
        self, tenant_a_client: AsyncClient, async_client: AsyncClient, seed_two_tenants: dict
    ):
        remote_url = await _upload_image(tenant_a_client)
        # async_client carries no Authorization header / cookie
        resp = await async_client.get(remote_url)
        assert resp.status_code == 401

    async def test_other_tenant_cannot_fetch_image(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        # Tenant A's image URL embeds tenant A's company_id; tenant B must be denied.
        remote_url = await _upload_image(tenant_a_client)
        resp = await tenant_b_client.get(remote_url)
        assert resp.status_code == 404

    async def test_forged_company_segment_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        # A caller cannot read another company's images by swapping the path segment.
        resp = await tenant_a_client.get(f"/files/images/{uuid4()}/anything.png")
        assert resp.status_code == 404

    async def test_path_traversal_blocked(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        company_id = seed_two_tenants["tenant_a_id"]
        # Even with the caller's own company segment, traversal must not escape uploads/.
        resp = await tenant_a_client.get(
            f"/files/images/{company_id}/..%2f..%2f..%2fapp%2fcore%2fconfig.py"
        )
        assert resp.status_code == 404

    async def test_unknown_category_rejected(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        resp = await tenant_a_client.get("/files/secrets/x.txt")
        assert resp.status_code == 404

    async def test_nonexistent_attachment_is_404(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        # No Attachment row with this remote_url exists → 404 (never reaches disk).
        resp = await tenant_a_client.get(f"/files/attachments/{uuid4()}/ghost.png")
        assert resp.status_code == 404

    async def test_owner_can_fetch_own_task_photo(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        # Regression guard: task-attachment files (a distinct /files category) must
        # still be served to their owner after the StaticFiles auth fix.
        remote_url = await _upload_task_photo(tenant_a_client)
        assert remote_url.startswith("/files/task-attachments/")
        resp = await tenant_a_client.get(remote_url)
        assert resp.status_code == 200
        assert resp.content == _PNG_BYTES

    async def test_other_tenant_cannot_fetch_task_photo(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        remote_url = await _upload_task_photo(tenant_a_client)
        resp = await tenant_b_client.get(remote_url)
        assert resp.status_code == 404

    async def test_unauthenticated_task_photo_rejected(
        self, tenant_a_client: AsyncClient, async_client: AsyncClient, seed_two_tenants: dict
    ):
        remote_url = await _upload_task_photo(tenant_a_client)
        resp = await async_client.get(remote_url)
        assert resp.status_code == 401

    async def test_nonexistent_task_attachment_is_404(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        # No TaskAttachment row with this remote_url exists → 404 (never reaches disk).
        resp = await tenant_a_client.get(f"/files/task-attachments/{uuid4()}/ghost.png")
        assert resp.status_code == 404

    async def test_client_role_without_photos_still_authenticates_but_scoped(
        self, seed_two_tenants: dict
    ):
        # A client-role token is still a valid caller; scoping (not the upload
        # permission) governs read access. A random image path → 404, not 401.
        company_id = seed_two_tenants["tenant_a_id"]
        token = create_access_token(uuid4(), UUID(company_id), ["client"])
        from app.main import app

        async with AsyncClient(
            transport=__import__("httpx").ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": f"Bearer {token}"},
        ) as client:
            resp = await client.get(f"/files/images/{company_id}/nope.png")
            assert resp.status_code == 404
