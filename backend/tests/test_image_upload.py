"""Integration tests for the generic image upload endpoint (POST /files/images)."""

from uuid import UUID, uuid4

import pytest

from app.core.security import create_access_token

# Minimal valid PNG header bytes — enough for an upload body.
_PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


@pytest.mark.asyncio
async def test_upload_image_returns_servable_url(tenant_a_client, seed_two_tenants):
    """An admin uploads an image and gets back a /files/images/... URL."""
    resp = await tenant_a_client.post(
        "/api/v1/files/images",
        files={"file": ("site.png", _PNG_BYTES, "image/png")},
    )
    assert resp.status_code == 201, resp.text
    remote_url = resp.json()["remote_url"]
    assert remote_url.startswith("/files/images/")
    assert remote_url.endswith(".png")


@pytest.mark.asyncio
async def test_upload_image_rejects_non_image(tenant_a_client, seed_two_tenants):
    """A non-image content type is rejected with 400."""
    resp = await tenant_a_client.post(
        "/api/v1/files/images",
        files={"file": ("report.pdf", b"%PDF-1.4", "application/pdf")},
    )
    assert resp.status_code == 400, resp.text


@pytest.mark.asyncio
async def test_upload_image_forbidden_without_photos_upload(async_client, seed_two_tenants):
    """A caller lacking photos.upload (client role) is 403."""
    company_id = seed_two_tenants["tenant_a_id"]
    token = create_access_token(uuid4(), UUID(company_id), ["client"])
    resp = await async_client.post(
        "/api/v1/files/images",
        files={"file": ("site.png", _PNG_BYTES, "image/png")},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 403, resp.text
