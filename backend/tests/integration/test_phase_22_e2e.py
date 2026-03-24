"""Phase 22 E2E integration tests — task notes, attachment upload, annotation, digest notification.

Tests cover:
1. POST /tasks/{id}/notes — create task note
2. GET /tasks/{id}/notes — list notes newest first
3. POST /tasks/{id}/attachments — upload photo (multipart)
4. POST /tasks/{id}/attachments — upload PDF document
5. PATCH /tasks/{id}/attachments/{id} — update annotation_data
6. Photo count limit (max 10) — 11th upload returns 400
7. Document count limit (max 5) — 6th upload returns 400
8. DELETE /tasks/{id}/attachments/{id} — soft delete, excluded from GET
9. PATCH /tasks/{id} status=complete triggers queue_task_completion_digest (mocked)

Follow existing conftest.py patterns:
- Use tenant_a_client fixture for authenticated requests
- seed_two_tenants provides company + user IDs and JWT tokens
- All test state is isolated via clean_tables (autouse)
"""

from __future__ import annotations

import io
import uuid
from unittest.mock import patch

import pytest
import pytest_asyncio
from httpx import AsyncClient

# ---------------------------------------------------------------------------
# Shared helper: build a minimal project -> trade_scope -> task hierarchy
# ---------------------------------------------------------------------------


async def _create_project(client: AsyncClient) -> dict:
    resp = await client.post(
        "/api/v1/projects/",
        json={"name": "Phase 22 Test Project"},
    )
    assert resp.status_code == 201, f"create project failed: {resp.text}"
    return resp.json()


async def _create_trade_scope(client: AsyncClient, project_id: str) -> dict:
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={
            "project_id": project_id,
            "trade_name": "Electrical",
            "trade_color": "#FF5733",
        },
    )
    assert resp.status_code == 201, f"create trade scope failed: {resp.text}"
    return resp.json()


async def _create_task(client: AsyncClient, trade_scope_id: str) -> dict:
    resp = await client.post(
        "/api/v1/tasks/",
        json={
            "trade_scope_id": trade_scope_id,
            "title": "Install breaker panel",
            "description": "Main 200A breaker panel installation",
        },
    )
    assert resp.status_code == 201, f"create task failed: {resp.text}"
    return resp.json()


@pytest_asyncio.fixture
async def setup_task(tenant_a_client):
    """Create project -> trade_scope -> task. Return task dict and client."""
    project = await _create_project(tenant_a_client)
    scope = await _create_trade_scope(tenant_a_client, project["id"])
    task = await _create_task(tenant_a_client, scope["id"])
    return {"task": task, "scope": scope, "project": project}


# ---------------------------------------------------------------------------
# Task 1: test_create_task_note
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_task_note(tenant_a_client, setup_task, seed_two_tenants):
    """POST /tasks/{id}/notes creates a note and returns 201 with correct fields."""
    task_id = setup_task["task"]["id"]

    resp = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/notes",
        json={"body": "Confirmed breaker panel location marked on floor plan."},
    )
    assert resp.status_code == 201, f"create note failed: {resp.text}"

    data = resp.json()
    assert data["task_id"] == task_id
    assert data["body"] == "Confirmed breaker panel location marked on floor plan."
    assert data["author_id"] == seed_two_tenants["tenant_a_user_id"]
    assert "id" in data
    assert "created_at" in data


# ---------------------------------------------------------------------------
# Task 2: test_list_task_notes_newest_first
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_task_notes_newest_first(tenant_a_client, setup_task):
    """GET /tasks/{id}/notes returns notes ordered newest first."""
    task_id = setup_task["task"]["id"]

    resp1 = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/notes",
        json={"body": "First note — arrived on site."},
    )
    assert resp1.status_code == 201

    resp2 = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/notes",
        json={"body": "Second note — materials confirmed."},
    )
    assert resp2.status_code == 201

    list_resp = await tenant_a_client.get(f"/api/v1/tasks/{task_id}/notes")
    assert list_resp.status_code == 200

    notes = list_resp.json()
    assert len(notes) == 2
    # Newest first: second note should appear before first
    assert notes[0]["body"] == "Second note — materials confirmed."
    assert notes[1]["body"] == "First note — arrived on site."


# ---------------------------------------------------------------------------
# Task 3: test_task_attachment_upload_photo
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_task_attachment_upload_photo(tenant_a_client, setup_task):
    """POST /tasks/{id}/attachments with a JPEG file returns 201 with remote_url."""
    task_id = setup_task["task"]["id"]

    # Minimal valid JPEG header bytes (enough to pass file write, not full image)
    jpeg_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"

    resp = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        data={"attachment_type": "photo", "caption": "Site overview photo", "sort_order": "1"},
        files={"file": ("site_overview.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
    )
    assert resp.status_code == 201, f"upload photo failed: {resp.text}"

    data = resp.json()
    assert data["task_id"] == task_id
    assert data["attachment_type"] == "photo"
    assert data["remote_url"] is not None
    assert f"task-attachments/{task_id}" in data["remote_url"]
    assert data["caption"] == "Site overview photo"
    assert data["sort_order"] == 1


# ---------------------------------------------------------------------------
# Task 4: test_task_attachment_upload_pdf
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_task_attachment_upload_pdf(tenant_a_client, setup_task):
    """POST /tasks/{id}/attachments with PDF bytes returns 201 with attachment_type=document."""
    task_id = setup_task["task"]["id"]

    # Minimal PDF header bytes
    pdf_bytes = b"%PDF-1.4\n%EOF"

    resp = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        data={"attachment_type": "document", "caption": "Electrical spec sheet"},
        files={"file": ("spec.pdf", io.BytesIO(pdf_bytes), "application/pdf")},
    )
    assert resp.status_code == 201, f"upload pdf failed: {resp.text}"

    data = resp.json()
    assert data["task_id"] == task_id
    assert data["attachment_type"] == "document"
    assert data["remote_url"] is not None
    assert data["annotation_data"] is None


# ---------------------------------------------------------------------------
# Task 5: test_task_attachment_annotation_update
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_task_attachment_annotation_update(tenant_a_client, setup_task):
    """Upload photo then PATCH annotation_data. Verify annotation_data round-trips."""
    task_id = setup_task["task"]["id"]

    jpeg_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x00\x00\xff\xd9"

    upload_resp = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        data={"attachment_type": "photo"},
        files={"file": ("panel.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
    )
    assert upload_resp.status_code == 201
    attachment_id = upload_resp.json()["id"]

    annotation_payload = {
        "version": "1.0",
        "objects": [
            {"type": "arrow", "x1": 100, "y1": 200, "x2": 300, "y2": 400, "color": "#FF0000"},
            {"type": "text", "x": 150, "y": 250, "content": "Check here", "fontSize": 14},
        ],
    }

    patch_resp = await tenant_a_client.patch(
        f"/api/v1/tasks/{task_id}/attachments/{attachment_id}",
        json={"annotation_data": annotation_payload},
    )
    assert patch_resp.status_code == 200, f"patch annotation failed: {patch_resp.text}"
    assert patch_resp.json()["annotation_data"] == annotation_payload

    # Verify via GET list
    list_resp = await tenant_a_client.get(f"/api/v1/tasks/{task_id}/attachments")
    assert list_resp.status_code == 200
    attachments = list_resp.json()
    target = next((a for a in attachments if a["id"] == attachment_id), None)
    assert target is not None
    assert target["annotation_data"] == annotation_payload


# ---------------------------------------------------------------------------
# Task 6: test_photo_limit_enforcement
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_photo_limit_enforcement(tenant_a_client, setup_task):
    """Upload 10 photos (at limit), then attempt 11th — should return 400."""
    task_id = setup_task["task"]["id"]
    jpeg_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x00\x00\xff\xd9"

    # Upload 10 photos (max allowed)
    for i in range(10):
        resp = await tenant_a_client.post(
            f"/api/v1/tasks/{task_id}/attachments",
            data={"attachment_type": "photo"},
            files={"file": (f"photo_{i}.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
        )
        assert resp.status_code == 201, f"Upload {i} failed: {resp.text}"

    # 11th photo should be rejected
    resp_11 = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        data={"attachment_type": "photo"},
        files={"file": ("photo_11.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
    )
    assert resp_11.status_code == 400
    assert "limit exceeded" in resp_11.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Task 7: test_pdf_limit_enforcement
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_pdf_limit_enforcement(tenant_a_client, setup_task):
    """Upload 5 documents (at limit), then attempt 6th — should return 400."""
    task_id = setup_task["task"]["id"]
    pdf_bytes = b"%PDF-1.4\n%EOF"

    # Upload 5 documents (max allowed)
    for i in range(5):
        resp = await tenant_a_client.post(
            f"/api/v1/tasks/{task_id}/attachments",
            data={"attachment_type": "document"},
            files={"file": (f"doc_{i}.pdf", io.BytesIO(pdf_bytes), "application/pdf")},
        )
        assert resp.status_code == 201, f"Upload doc {i} failed: {resp.text}"

    # 6th document should be rejected
    resp_6 = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        data={"attachment_type": "document"},
        files={"file": ("doc_6.pdf", io.BytesIO(pdf_bytes), "application/pdf")},
    )
    assert resp_6.status_code == 400
    assert "limit exceeded" in resp_6.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Task 8: test_task_attachment_soft_delete
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_task_attachment_soft_delete(tenant_a_client, setup_task):
    """DELETE /tasks/{id}/attachments/{id} returns 204. GET no longer returns it."""
    task_id = setup_task["task"]["id"]
    jpeg_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x00\x00\xff\xd9"

    upload_resp = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        data={"attachment_type": "photo"},
        files={"file": ("to_delete.jpg", io.BytesIO(jpeg_bytes), "image/jpeg")},
    )
    assert upload_resp.status_code == 201
    attachment_id = upload_resp.json()["id"]

    # Soft delete
    del_resp = await tenant_a_client.delete(f"/api/v1/tasks/{task_id}/attachments/{attachment_id}")
    assert del_resp.status_code == 204

    # Verify deleted attachment does not appear in GET
    list_resp = await tenant_a_client.get(f"/api/v1/tasks/{task_id}/attachments")
    assert list_resp.status_code == 200
    attachment_ids = [a["id"] for a in list_resp.json()]
    assert attachment_id not in attachment_ids


# ---------------------------------------------------------------------------
# Task 9: test_task_completion_triggers_digest_notification
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_task_completion_triggers_digest_notification(tenant_a_client, setup_task):
    """PATCH task status to 'complete' triggers queue_task_completion_digest.

    Verifies:
    1. PATCH returns 200 even if notification internals raise (fire-and-forget).
    2. queue_task_completion_digest is called with correct task_id and trade_scope_name.
    3. Called only on first transition to 'complete' (not on idempotent re-patch).
    """
    task_id = setup_task["task"]["id"]
    trade_scope_name = setup_task["scope"]["trade_name"]

    call_log: list[dict] = []

    async def mock_digest(
        self_,
        task_id: uuid.UUID,
        task_title: str,
        trade_scope_name: str,
        company_id: uuid.UUID,
        completed_by_name: str,
    ) -> None:
        call_log.append(
            {
                "task_id": str(task_id),
                "task_title": task_title,
                "trade_scope_name": trade_scope_name,
            }
        )

    with patch(
        "app.features.notifications.service.NotificationService.queue_task_completion_digest",
        new=mock_digest,
    ):
        # First PATCH to 'complete' — should trigger notification
        resp = await tenant_a_client.patch(
            f"/api/v1/tasks/{task_id}",
            json={"status": "complete"},
        )
        assert resp.status_code == 200, f"PATCH task failed: {resp.text}"
        assert resp.json()["status"] == "complete"
        assert len(call_log) == 1
        assert call_log[0]["task_id"] == task_id
        assert call_log[0]["trade_scope_name"] == trade_scope_name

        # Idempotent re-PATCH to 'complete' — should NOT trigger again
        resp2 = await tenant_a_client.patch(
            f"/api/v1/tasks/{task_id}",
            json={"status": "complete"},
        )
        assert resp2.status_code == 200
        assert len(call_log) == 1  # still only 1 call


@pytest.mark.asyncio
async def test_task_completion_notification_failure_does_not_block(tenant_a_client, setup_task):
    """PATCH still returns 200 even if queue_task_completion_digest raises an error."""
    task_id = setup_task["task"]["id"]

    async def mock_digest_raises(*args, **kwargs) -> None:
        raise RuntimeError("FCM unavailable")

    with patch(
        "app.features.notifications.service.NotificationService.queue_task_completion_digest",
        new=mock_digest_raises,
    ):
        resp = await tenant_a_client.patch(
            f"/api/v1/tasks/{task_id}",
            json={"status": "complete"},
        )
        # Task update must succeed even when notification raises
        assert resp.status_code == 200
        assert resp.json()["status"] == "complete"
