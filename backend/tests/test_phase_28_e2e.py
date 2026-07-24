"""Phase 28 E2E — web media authoring across all three surfaces.

Exercises the full upload/annotation data flows the web app drives:
  1. Job notes    — create job → note → upload photo + drawing attachments.
  2. Task photos  — upload photo to a task, then non-destructive annotation via PATCH.
  3. Foreman      — generic image upload → status update carrying photo URLs.
Plus auth/permission and tenant-isolation guards.

All flows run through the real ASGI app + Postgres (RLS enforced), using multipart
uploads exactly as the browser sends them.
"""

import io
from uuid import UUID, uuid4

import pytest

from app.core.security import create_access_token

pytestmark = pytest.mark.asyncio

_PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 128


def _png_file(name: str = "shot.png"):
    return {"file": (name, io.BytesIO(_PNG), "image/png")}


# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------


async def _create_job(client) -> str:
    resp = await client.post(
        "/api/v1/jobs/",
        json={"description": "Media test job", "trade_type": "plumbing"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_note(client, job_id: str) -> str:
    resp = await client.post(f"/api/v1/jobs/{job_id}/notes", json={"body": "Note with media"})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_project(client, name: str = "Media Project") -> str:
    resp = await client.post("/api/v1/projects/", json={"name": name})
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _create_task(client, project_id: str) -> str:
    scope = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": "Electrical"},
    )
    assert scope.status_code == 201, scope.text
    scope_id = scope.json()["id"]
    task = await client.post(
        "/api/v1/tasks/",
        json={"trade_scope_id": scope_id, "title": "Install panel", "status": "in_progress"},
    )
    assert task.status_code == 201, task.text
    return task.json()["id"]


# ---------------------------------------------------------------------------
# Surface 1 — Job notes: photo + drawing attachments
# ---------------------------------------------------------------------------


async def test_job_note_photo_and_drawing_attachments(tenant_a_client, seed_two_tenants):
    """A note can carry both a photo and a from-scratch drawing; both surface on GET."""
    job_id = await _create_job(tenant_a_client)
    note_id = await _create_note(tenant_a_client, job_id)

    photo = await tenant_a_client.post(
        "/api/v1/files/upload",
        files=_png_file("photo.png"),
        data={"note_id": note_id, "attachment_type": "photo"},
    )
    assert photo.status_code == 201, photo.text
    assert photo.json()["attachment_type"] == "photo"
    assert "/files/attachments/" in photo.json()["remote_url"]

    drawing = await tenant_a_client.post(
        "/api/v1/files/upload",
        files=_png_file("sketch.png"),
        data={"note_id": note_id, "attachment_type": "drawing"},
    )
    assert drawing.status_code == 201, drawing.text
    assert drawing.json()["attachment_type"] == "drawing"

    notes = await tenant_a_client.get(f"/api/v1/jobs/{job_id}/notes")
    assert notes.status_code == 200, notes.text
    target = next(n for n in notes.json() if n["id"] == note_id)
    types = sorted(a["attachment_type"] for a in target["attachments"])
    assert types == ["drawing", "photo"]


async def test_upload_rejects_invalid_attachment_type(tenant_a_client, seed_two_tenants):
    job_id = await _create_job(tenant_a_client)
    note_id = await _create_note(tenant_a_client, job_id)
    resp = await tenant_a_client.post(
        "/api/v1/files/upload",
        files=_png_file(),
        data={"note_id": note_id, "attachment_type": "hologram"},
    )
    assert resp.status_code == 400, resp.text


async def test_upload_to_missing_note_returns_404(tenant_a_client, seed_two_tenants):
    resp = await tenant_a_client.post(
        "/api/v1/files/upload",
        files=_png_file(),
        data={"note_id": str(uuid4()), "attachment_type": "photo"},
    )
    assert resp.status_code == 404, resp.text


async def test_attachment_upload_is_tenant_isolated(
    tenant_a_client, tenant_b_client, seed_two_tenants
):
    """Tenant B cannot attach to Tenant A's note (RLS hides it → 404)."""
    job_id = await _create_job(tenant_a_client)
    note_id = await _create_note(tenant_a_client, job_id)
    resp = await tenant_b_client.post(
        "/api/v1/files/upload",
        files=_png_file(),
        data={"note_id": note_id, "attachment_type": "photo"},
    )
    assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# Surface 2 — Task photos: upload + non-destructive annotation
# ---------------------------------------------------------------------------


async def test_task_photo_upload_then_nondestructive_annotation(tenant_a_client, seed_two_tenants):
    """Upload a task photo, then PATCH an annotation layer that persists (image untouched)."""
    project_id = await _create_project(tenant_a_client)
    task_id = await _create_task(tenant_a_client, project_id)

    upload = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        files=_png_file("task.png"),
        data={"attachment_type": "photo"},
    )
    assert upload.status_code == 201, upload.text
    attachment = upload.json()
    assert "/files/task-attachments/" in attachment["remote_url"]
    assert attachment["annotation_data"] is None
    attachment_id = attachment["id"]

    layer = {
        "version": 1,
        "canvasWidth": 800,
        "canvasHeight": 600,
        "annotations": [
            {
                "id": "a1",
                "tool": "arrow",
                "color": "#D32F2F",
                "thickness": 3,
                "startX": 0.1,
                "startY": 0.1,
                "endX": 0.5,
                "endY": 0.5,
            }
        ],
    }
    patched = await tenant_a_client.patch(
        f"/api/v1/tasks/{task_id}/attachments/{attachment_id}",
        json={"annotation_data": layer},
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["annotation_data"]["annotations"][0]["tool"] == "arrow"
    # Same remote_url — the original image is never modified by annotation.
    assert patched.json()["remote_url"] == attachment["remote_url"]

    listing = await tenant_a_client.get(f"/api/v1/tasks/{task_id}/attachments")
    assert listing.status_code == 200, listing.text
    stored = next(a for a in listing.json() if a["id"] == attachment_id)
    assert stored["annotation_data"]["annotations"][0]["startX"] == 0.1


async def test_task_annotation_can_be_edited_again(tenant_a_client, seed_two_tenants):
    """Re-PATCHing replaces the annotation layer (editable later)."""
    project_id = await _create_project(tenant_a_client)
    task_id = await _create_task(tenant_a_client, project_id)
    upload = await tenant_a_client.post(
        f"/api/v1/tasks/{task_id}/attachments",
        files=_png_file(),
        data={"attachment_type": "photo"},
    )
    attachment_id = upload.json()["id"]

    first = {"version": 1, "canvasWidth": 10, "canvasHeight": 10, "annotations": []}
    await tenant_a_client.patch(
        f"/api/v1/tasks/{task_id}/attachments/{attachment_id}",
        json={"annotation_data": first},
    )
    second = {
        "version": 1,
        "canvasWidth": 10,
        "canvasHeight": 10,
        "annotations": [
            {
                "id": "c1",
                "tool": "circle",
                "color": "#000",
                "thickness": 2,
                "x": 0.2,
                "y": 0.2,
                "width": 0.3,
                "height": 0.3,
            }
        ],
    }
    resp = await tenant_a_client.patch(
        f"/api/v1/tasks/{task_id}/attachments/{attachment_id}",
        json={"annotation_data": second},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["annotation_data"]["annotations"][0]["tool"] == "circle"


# ---------------------------------------------------------------------------
# Surface 3 — Generic image upload + foreman status photos
# ---------------------------------------------------------------------------


async def test_generic_image_upload_returns_servable_url(tenant_a_client, seed_two_tenants):
    resp = await tenant_a_client.post("/api/v1/files/images", files=_png_file("site.png"))
    assert resp.status_code == 201, resp.text
    assert resp.json()["remote_url"].startswith("/files/images/")


async def test_generic_image_upload_rejects_non_image(tenant_a_client, seed_two_tenants):
    resp = await tenant_a_client.post(
        "/api/v1/files/images",
        files={"file": ("doc.pdf", io.BytesIO(b"%PDF-1.4"), "application/pdf")},
    )
    assert resp.status_code == 400, resp.text


async def test_generic_image_upload_requires_photos_permission(async_client, seed_two_tenants):
    company_id = seed_two_tenants["tenant_a_id"]
    token = create_access_token(uuid4(), UUID(company_id), ["client"])
    resp = await async_client.post(
        "/api/v1/files/images",
        files=_png_file(),
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 403, resp.text


async def test_foreman_status_update_carries_uploaded_photos(tenant_a_client, seed_two_tenants):
    """Upload an image, then attach its URL to a foreman daily status update.

    Status updates require an assigned foreman, so set one up: create a contractor,
    assign them to the project, and post the update (with the photo) as that user.
    """
    company_id = seed_two_tenants["tenant_a_id"]
    project_id = await _create_project(tenant_a_client, "Foreman Media Project")

    user_resp = await tenant_a_client.post(
        "/api/v1/users/", json={"email": "foreman-media@tenant-a.com"}
    )
    assert user_resp.status_code == 201, user_resp.text
    user_id = user_resp.json()["id"]
    role_resp = await tenant_a_client.post(
        f"/api/v1/users/{user_id}/roles",
        json={"user_id": user_id, "role": "contractor"},
    )
    assert role_resp.status_code == 201, role_resp.text
    assign_resp = await tenant_a_client.post(
        "/api/v1/foreman/assignments",
        json={"project_id": project_id, "user_id": user_id},
    )
    assert assign_resp.status_code == 201, assign_resp.text

    foreman_auth = {
        "Authorization": f"Bearer {create_access_token(UUID(user_id), UUID(company_id), ['contractor'])}"
    }

    img = await tenant_a_client.post(
        "/api/v1/files/images", files=_png_file("progress.png"), headers=foreman_auth
    )
    assert img.status_code == 201, img.text
    photo_url = img.json()["remote_url"]

    status_resp = await tenant_a_client.post(
        "/api/v1/foreman/status-updates",
        json={
            "project_id": project_id,
            "status_text": "Framing complete on the north wall.",
            "photos": [photo_url],
        },
        headers=foreman_auth,
    )
    assert status_resp.status_code == 201, status_resp.text
    assert status_resp.json()["photos"] == [photo_url]

    listing = await tenant_a_client.get(f"/api/v1/foreman/status-updates/{project_id}")
    assert listing.status_code == 200, listing.text
    assert any(photo_url in update["photos"] for update in listing.json()["items"])
