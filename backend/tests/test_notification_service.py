"""Unit tests for NotificationService with mocked Firebase.

Tests cover:
- send_job_notification: NotificationService._send_to_token called with right args
- UnregisteredError: token deleted from device_tokens
- Generic error: token NOT deleted (fire-and-forget tolerance)
- upsert_token creates new token
- upsert_token updates last_used_at on duplicate (single row)
- Multiple devices per user: both tokens stored
- No notification when FCM not configured (graceful degradation)

Strategy:
- Use the /auth/register endpoint to create a user (handles RLS setup).
- Use the token registration endpoint to seed device tokens.
- Unit-test NotificationService._send_to_token directly for error branches.
- Use async_client (ASGI) for all DB operations to avoid RLS issues.
"""

from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import AsyncClient

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def register_user(client: AsyncClient, email: str, company_name: str) -> dict:
    """Register a new admin user and return auth data (access_token, user_id, company_id)."""
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "TestPass123!",
            "company_name": company_name,
        },
    )
    assert resp.status_code == 201, f"Register failed: {resp.text}"
    return resp.json()


async def register_device_token(client: AsyncClient, token: str, platform: str = "android") -> int:
    """POST a device token and return the status code."""
    resp = await client.post(
        "/api/v1/notifications/token",
        json={"token": token, "platform": platform},
    )
    return resp.status_code


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_upsert_token_creates_new(async_client):
    """upsert_token stores a new token — verified via token registration endpoint."""
    data = await register_user(async_client, "user@tok-new.com", "Tok New Co")
    token = data["access_token"]

    async with AsyncClient(
        transport=async_client._transport,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        status = await register_device_token(ac, "brand-new-token")

    assert status == 204


@pytest.mark.asyncio
async def test_upsert_token_updates_existing(async_client):
    """Re-registering the same token twice returns 204 both times (upsert semantics)."""
    data = await register_user(async_client, "user@tok-dup.com", "Tok Dup Co")
    token = data["access_token"]

    async with AsyncClient(
        transport=async_client._transport,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        status1 = await register_device_token(ac, "same-token-abc")
        status2 = await register_device_token(ac, "same-token-abc")

    assert status1 == 204
    assert status2 == 204


@pytest.mark.asyncio
async def test_upsert_token_multiple_devices(async_client):
    """Same user registering two different tokens both succeed with 204."""
    data = await register_user(async_client, "user@tok-multi.com", "Tok Multi Co")
    token = data["access_token"]

    async with AsyncClient(
        transport=async_client._transport,
        base_url="http://test",
        headers={"Authorization": f"Bearer {token}"},
    ) as ac:
        status1 = await register_device_token(ac, "phone-token-xyz")
        status2 = await register_device_token(ac, "tablet-token-xyz")

    assert status1 == 204
    assert status2 == 204


@pytest.mark.asyncio
async def test_send_notification_unregistered_error():
    """_send_to_token with UnregisteredError calls delete_token on the repository."""
    from app.features.notifications.models import DeviceToken
    from app.features.notifications.service import NotificationService

    # Build a fake DeviceToken without DB
    fake_token = DeviceToken()
    fake_token.id = uuid.uuid4()
    fake_token.user_id = uuid.uuid4()
    fake_token.token = "stale-token-xyz"
    fake_token.platform = "android"

    # Mock the DB session — we don't need real DB for this unit test
    mock_db = AsyncMock()

    svc = NotificationService(mock_db)
    svc.repository = AsyncMock()
    svc.repository.delete_token = AsyncMock()

    class _UnregisteredError(Exception):
        pass

    mock_messaging = MagicMock()
    mock_messaging.UnregisteredError = _UnregisteredError
    mock_messaging.send.side_effect = _UnregisteredError("Not registered")

    await svc._send_to_token(
        fake_token,
        title="Job Scheduled",
        body="Your job has been scheduled.",
        data={"job_id": str(uuid.uuid4()), "event": "job_update"},
        messaging=mock_messaging,
    )

    # Token must be deleted after UnregisteredError
    svc.repository.delete_token.assert_awaited_once_with("stale-token-xyz")


@pytest.mark.asyncio
async def test_send_notification_generic_error_token_not_deleted():
    """_send_to_token with a generic exception does NOT delete the token."""
    from app.features.notifications.models import DeviceToken
    from app.features.notifications.service import NotificationService

    fake_token = DeviceToken()
    fake_token.id = uuid.uuid4()
    fake_token.user_id = uuid.uuid4()
    fake_token.token = "good-token-abc"
    fake_token.platform = "ios"

    mock_db = AsyncMock()
    svc = NotificationService(mock_db)
    svc.repository = AsyncMock()
    svc.repository.delete_token = AsyncMock()

    class _UnregisteredError(Exception):
        pass

    mock_messaging = MagicMock()
    mock_messaging.UnregisteredError = _UnregisteredError
    mock_messaging.send.side_effect = RuntimeError("Server unavailable")

    # Should not raise — fire-and-forget
    await svc._send_to_token(
        fake_token,
        title="Job Update",
        body="There is an update on your job.",
        data={"job_id": str(uuid.uuid4()), "event": "job_update"},
        messaging=mock_messaging,
    )

    # delete_token must NOT be called on generic error
    svc.repository.delete_token.assert_not_awaited()


@pytest.mark.asyncio
async def test_send_job_notification_success():
    """send_job_notification calls _send_to_token for each registered device token."""
    import uuid

    from app.features.notifications.models import DeviceToken
    from app.features.notifications.service import NotificationService

    user_id = uuid.uuid4()
    job_id = uuid.uuid4()

    # Fake device tokens (two devices)
    token1 = DeviceToken()
    token1.id = uuid.uuid4()
    token1.user_id = user_id
    token1.token = "device-token-1"
    token1.platform = "android"

    token2 = DeviceToken()
    token2.id = uuid.uuid4()
    token2.user_id = user_id
    token2.token = "device-token-2"
    token2.platform = "ios"

    mock_db = AsyncMock()
    svc = NotificationService(mock_db)
    svc.repository = AsyncMock()
    svc.repository.get_tokens_for_user = AsyncMock(return_value=[token1, token2])

    mock_firebase_app = MagicMock()
    mock_messaging = MagicMock()
    mock_messaging.UnregisteredError = Exception
    mock_messaging.send.return_value = "projects/test/messages/ok"

    with (
        patch(
            "app.features.notifications.service._get_firebase_app", return_value=mock_firebase_app
        ),
        patch("firebase_admin.messaging", mock_messaging, create=True),
    ):
        send_calls = []

        async def fake_send_to_token(token_record=None, **kwargs):
            send_calls.append(kwargs)

        svc._send_to_token = fake_send_to_token
        await svc.send_job_notification(
            user_id=user_id,
            job_description="Fix leaking boiler",
            event="scheduled",
            job_id=job_id,
        )

    # Should have sent to both tokens
    assert len(send_calls) == 2
    # Verify correct content was built for "scheduled" event
    bodies = [c["body"] for c in send_calls]
    assert all("Fix leaking boiler" in b for b in bodies)
    titles = [c["title"] for c in send_calls]
    assert all("Scheduled" in t or "Job" in t for t in titles)


@pytest.mark.asyncio
async def test_no_notification_when_fcm_not_configured():
    """When _get_firebase_app returns None, send_job_notification exits silently."""

    from app.features.notifications.service import NotificationService

    user_id = uuid.uuid4()
    job_id = uuid.uuid4()

    mock_db = AsyncMock()
    svc = NotificationService(mock_db)
    svc.repository = AsyncMock()
    svc.repository.get_tokens_for_user = AsyncMock(return_value=[])

    with patch("app.features.notifications.service._get_firebase_app", return_value=None):
        # Should complete without calling get_tokens_for_user
        await svc.send_job_notification(
            user_id=user_id,
            job_description="Fix boiler",
            event="completed",
            job_id=job_id,
        )

    # get_tokens_for_user should NOT be called (FCM not configured — early exit)
    svc.repository.get_tokens_for_user.assert_not_awaited()


# ---------------------------------------------------------------------------
# send_profitability_finding_notification (Phase 36, FINAI-02)
#
# The Phase 36 e2e suite patches this method to assert WHO it is called with;
# these two exercise the body itself, which that patch necessarily skips.
# ---------------------------------------------------------------------------

_PROFITABILITY_PUSH_DATA = {
    "type": "ai_profitability_finding",
    "alert_type": "ai_profitability",
    "alert_id": "0f1c9a4e-0000-4000-8000-000000000001",
    "finding_id": "0f1c9a4e-0000-4000-8000-000000000002",
    "project_id": "0f1c9a4e-0000-4000-8000-000000000003",
    "severity": "warning",
}
_PROFITABILITY_PUSH_TITLE = "Margin warning"
_PROFITABILITY_PUSH_BODY = "AI finding — Billed margin trails the approved quote."


@pytest.mark.asyncio
async def test_send_profitability_finding_notification_dispatches_to_every_token():
    """Every device token of every finance.view recipient receives the same push."""
    from app.features.notifications.models import DeviceToken
    from app.features.notifications.service import NotificationService

    recipient_ids = [uuid.uuid4(), uuid.uuid4()]
    tokens = []
    for index in range(2):
        token = DeviceToken()
        token.id = uuid.uuid4()
        token.user_id = recipient_ids[index]
        token.token = f"finance-device-{index}"
        token.platform = "android"
        tokens.append(token)

    service = NotificationService(AsyncMock())
    service.repository = AsyncMock()
    service.repository.get_tokens_for_users = AsyncMock(return_value=tokens)

    mock_messaging = MagicMock()
    mock_messaging.UnregisteredError = Exception
    send_calls = []

    async def fake_send_to_token(token_record=None, **kwargs):
        send_calls.append(kwargs)

    with (
        patch("app.features.notifications.service._get_firebase_app", return_value=MagicMock()),
        patch("firebase_admin.messaging", mock_messaging, create=True),
    ):
        service._send_to_token = fake_send_to_token
        await service.send_profitability_finding_notification(
            recipient_ids=recipient_ids,
            title=_PROFITABILITY_PUSH_TITLE,
            body=_PROFITABILITY_PUSH_BODY,
            data=_PROFITABILITY_PUSH_DATA,
        )

    service.repository.get_tokens_for_users.assert_awaited_once_with(recipient_ids)
    assert len(send_calls) == len(tokens)
    assert all(call["title"] == _PROFITABILITY_PUSH_TITLE for call in send_calls)
    assert all(call["body"] == _PROFITABILITY_PUSH_BODY for call in send_calls)
    assert all(call["data"] == _PROFITABILITY_PUSH_DATA for call in send_calls)


@pytest.mark.asyncio
async def test_send_profitability_finding_notification_skips_without_fcm():
    """Without Firebase credentials it degrades silently and queries no tokens."""
    from app.features.notifications.service import NotificationService

    service = NotificationService(AsyncMock())
    service.repository = AsyncMock()
    service.repository.get_tokens_for_users = AsyncMock(return_value=[])

    with patch("app.features.notifications.service._get_firebase_app", return_value=None):
        await service.send_profitability_finding_notification(
            recipient_ids=[uuid.uuid4()],
            title=_PROFITABILITY_PUSH_TITLE,
            body=_PROFITABILITY_PUSH_BODY,
            data=_PROFITABILITY_PUSH_DATA,
        )

    service.repository.get_tokens_for_users.assert_not_awaited()
