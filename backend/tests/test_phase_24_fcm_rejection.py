"""Phase 24 backend integration tests — INSP-04: FCM dispatch on task rejection.

Tests cover:
1. Rejection triggers FCM send_task_rejection_notification (mocked)
2. FCM gracefully skipped when _get_firebase_app returns None (no creds)
3. FCM failure does not block the inspect response (fire-and-forget)
4. FCM data payload contains correct type, task_id, rejection_reason

FCM is mocked at the service layer to avoid actual Firebase calls.
Tests verify the fire-and-forget behavior and payload correctness.

Strategy:
- Patch `app.features.notifications.service._get_firebase_app` for cases
  that test no-credentials graceful degradation.
- Patch `app.features.notifications.service.NotificationService.send_task_rejection_notification`
  directly to capture calls and verify arguments without needing actual Firebase.
"""

from __future__ import annotations

import asyncio
from unittest.mock import patch

import pytest
from httpx import AsyncClient

import app.features.inspection.models  # noqa: F401 — ensure mappers configured

pytestmark = pytest.mark.anyio


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


async def _create_project(client: AsyncClient, name: str = "FCM Test Project") -> str:
    resp = await client.post("/api/v1/projects/", json={"name": name})
    assert resp.status_code == 201, f"Project creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient,
    project_id: str,
    trade_name: str = "Electrical",
) -> str:
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name},
    )
    assert resp.status_code == 201, f"Trade scope creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_task_complete(
    client: AsyncClient,
    scope_id: str,
    title: str = "Task to Reject",
    assigned_to: str | None = None,
) -> tuple[str, str]:
    """Create a task and set it to 'complete'. Returns (task_id, scope_id)."""
    body: dict = {"trade_scope_id": scope_id, "title": title, "status": "in_progress"}
    if assigned_to:
        body["assigned_to"] = assigned_to
    create_resp = await client.post("/api/v1/tasks/", json=body)
    assert create_resp.status_code == 201, f"Task creation failed: {create_resp.text}"
    task_id = create_resp.json()["id"]

    update_resp = await client.patch(f"/api/v1/tasks/{task_id}", json={"status": "complete"})
    assert update_resp.status_code == 200, f"Task status update failed: {update_resp.text}"
    return task_id, scope_id


async def _get_task_status(client: AsyncClient, task_id: str, scope_id: str) -> str:
    """Get a task's current status via the list endpoint (no single-task GET)."""
    resp = await client.get(f"/api/v1/tasks/?trade_scope_id={scope_id}")
    assert resp.status_code == 200, f"List tasks failed: {resp.text}"
    tasks = resp.json()
    for task in tasks:
        if task["id"] == task_id:
            return task["status"]
    raise AssertionError(f"Task {task_id} not found in scope {scope_id}")


# ---------------------------------------------------------------------------
# INSP-04: FCM rejection notification tests
# ---------------------------------------------------------------------------


class TestFCMRejection:
    async def test_rejection_triggers_fcm(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ) -> None:
        """Task rejection calls send_task_rejection_notification when task has assigned_to.

        The notification is fire-and-forget via asyncio.create_task.
        We mock the service method and verify it is called with correct args.
        """
        project_id = await _create_project(tenant_a_client, "FCM Triggers Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        user_id = seed_two_tenants["tenant_a_user_id"]
        task_id, _ = await _create_task_complete(
            tenant_a_client, scope_id, title="FCM Task", assigned_to=user_id
        )

        call_args = []

        async def fake_send_rejection(**kwargs):
            call_args.append(kwargs)

        with patch(
            "app.features.notifications.service.NotificationService.send_task_rejection_notification",
            side_effect=fake_send_rejection,
        ):
            resp = await tenant_a_client.post(
                f"/api/v1/tasks/{task_id}/inspect",
                json={
                    "decision": "rejected",
                    "rejection_reason": "rework_needed",
                    "rejection_comment": "Substandard work",
                },
            )
            assert resp.status_code == 201, f"Inspect failed: {resp.text}"

            # Allow the event loop to process fire-and-forget task
            await asyncio.sleep(0.05)

        # send_task_rejection_notification should have been called once
        assert len(call_args) == 1
        args = call_args[0]
        assert args["rejection_reason"] == "rework_needed"
        assert str(args["task_id"]) == task_id

    async def test_rejection_fcm_no_creds_graceful(self, tenant_a_client: AsyncClient) -> None:
        """When _get_firebase_app returns None, rejection still succeeds.

        This validates graceful degradation — dev/test environments without
        Firebase credentials do not fail the inspect endpoint.
        """
        project_id = await _create_project(tenant_a_client, "FCM No Creds Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        task_id, _ = await _create_task_complete(tenant_a_client, scope_id)

        # Mock _get_firebase_app to return None (no credentials configured)
        with patch(
            "app.features.notifications.service._get_firebase_app",
            return_value=None,
        ):
            resp = await tenant_a_client.post(
                f"/api/v1/tasks/{task_id}/inspect",
                json={
                    "decision": "rejected",
                    "rejection_reason": "incomplete",
                },
            )
            # Task rejection must succeed even with no FCM credentials
            assert resp.status_code == 201, f"Inspect failed: {resp.text}"
            assert resp.json()["decision"] == "rejected"

        # Task status must be 'rejected' — verify via list endpoint
        task_status = await _get_task_status(tenant_a_client, task_id, scope_id)
        assert task_status == "rejected"

    async def test_rejection_fcm_failure_does_not_block_inspect(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ) -> None:
        """FCM send failure (exception) does not propagate to the inspect endpoint.

        send_task_rejection_notification uses fire-and-forget — any internal
        exception is caught and logged, never raised to the caller.
        """
        project_id = await _create_project(tenant_a_client, "FCM Failure Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        user_id = seed_two_tenants["tenant_a_user_id"]
        task_id, _ = await _create_task_complete(tenant_a_client, scope_id, assigned_to=user_id)

        async def fail_send(**kwargs):
            raise RuntimeError("Simulated FCM network failure")

        with patch(
            "app.features.notifications.service.NotificationService.send_task_rejection_notification",
            side_effect=fail_send,
        ):
            resp = await tenant_a_client.post(
                f"/api/v1/tasks/{task_id}/inspect",
                json={
                    "decision": "rejected",
                    "rejection_reason": "safety_concern",
                },
            )
            # Endpoint must succeed despite FCM failure
            assert resp.status_code == 201, f"Inspect failed despite FCM mock: {resp.text}"
            assert resp.json()["decision"] == "rejected"

            # Allow fire-and-forget task to process
            await asyncio.sleep(0.05)

        # Task should still be rejected — verify via list endpoint
        task_status = await _get_task_status(tenant_a_client, task_id, scope_id)
        assert task_status == "rejected"

    async def test_rejection_fcm_data_payload(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ) -> None:
        """Verify FCM data payload contains required keys for task rejection.

        Validates that send_task_rejection_notification is called with:
        - task_id matching the rejected task
        - rejection_reason matching the request
        - task_title matching the task title
        - contractor_id matching assigned_to
        """
        project_id = await _create_project(tenant_a_client, "FCM Payload Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        user_id = seed_two_tenants["tenant_a_user_id"]
        task_id, _ = await _create_task_complete(
            tenant_a_client, scope_id, title="Plumbing Inspection Task", assigned_to=user_id
        )

        captured = {}

        async def capture_call(**kwargs):
            captured.update(kwargs)

        with patch(
            "app.features.notifications.service.NotificationService.send_task_rejection_notification",
            side_effect=capture_call,
        ):
            resp = await tenant_a_client.post(
                f"/api/v1/tasks/{task_id}/inspect",
                json={
                    "decision": "rejected",
                    "rejection_reason": "wrong_materials",
                    "rejection_comment": "Used PVC when copper was required",
                },
            )
            assert resp.status_code == 201

            # Allow fire-and-forget to process
            await asyncio.sleep(0.05)

        # Verify the notification payload
        assert captured, "send_task_rejection_notification was not called"
        assert str(captured["task_id"]) == task_id
        assert captured["rejection_reason"] == "wrong_materials"
        assert "Plumbing Inspection Task" in captured["task_title"]
        assert str(captured["contractor_id"]) == user_id

    async def test_approval_does_not_trigger_fcm(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ) -> None:
        """Approving a task does NOT trigger FCM notification."""
        project_id = await _create_project(tenant_a_client, "FCM Approve No Notify")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        user_id = seed_two_tenants["tenant_a_user_id"]
        task_id, _ = await _create_task_complete(tenant_a_client, scope_id, assigned_to=user_id)

        call_count = 0

        async def track_call(**kwargs):
            nonlocal call_count
            call_count += 1

        with patch(
            "app.features.notifications.service.NotificationService.send_task_rejection_notification",
            side_effect=track_call,
        ):
            resp = await tenant_a_client.post(
                f"/api/v1/tasks/{task_id}/inspect",
                json={
                    "decision": "approved",
                    "checklist_results": [{"item": "Quality", "checked": True}],
                },
            )
            assert resp.status_code == 201

            await asyncio.sleep(0.05)

        # Approval should NOT trigger rejection FCM
        assert call_count == 0, "Approval incorrectly triggered rejection FCM notification"
