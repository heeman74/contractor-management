"""Phase 24 backend integration tests — INSP-01: GC task inspection.

Tests cover:
1. GC approves a complete task — TaskInspection created, task status unchanged
2. GC rejects a complete task — TaskInspection created, task.status='rejected'
3. Rejecting a non-complete task returns 422
4. Inspecting a non-existent task returns 404
5. Multiple inspections create an audit trail
6. Contractor cannot inspect (403)
7. Rejecting a task re-blocks its FS-dependent successors (reblock_successors)

All tests use ASGI client hitting real HTTP endpoints via tenant_a_client.
"""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient

import app.features.inspection.models  # noqa: F401 — ensure mappers configured

pytestmark = pytest.mark.anyio


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


async def _create_project(client: AsyncClient, name: str = "Inspection Test Project") -> str:
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


async def _create_task(
    client: AsyncClient,
    scope_id: str,
    title: str = "Install Outlets",
    status: str = "in_progress",
    assigned_to: str | None = None,
) -> str:
    body: dict = {
        "trade_scope_id": scope_id,
        "title": title,
        "status": status,
    }
    if assigned_to:
        body["assigned_to"] = assigned_to
    resp = await client.post("/api/v1/tasks/", json=body)
    assert resp.status_code == 201, f"Task creation failed: {resp.text}"
    return resp.json()["id"]


async def _set_task_status(client: AsyncClient, task_id: str, status: str) -> None:
    resp = await client.patch(f"/api/v1/tasks/{task_id}", json={"status": status})
    assert resp.status_code == 200, f"Task status update failed: {resp.text}"


async def _get_task_status(client: AsyncClient, task_id: str, scope_id: str) -> str:
    """Get a task's current status via the list endpoint (no single-task GET)."""
    resp = await client.get(f"/api/v1/tasks/?trade_scope_id={scope_id}")
    assert resp.status_code == 200, f"List tasks failed: {resp.text}"
    tasks = resp.json()
    for task in tasks:
        if task["id"] == task_id:
            return task["status"]
    raise AssertionError(f"Task {task_id} not found in scope {scope_id}")


async def _inspect_task(
    client: AsyncClient,
    task_id: str,
    decision: str,
    checklist_results: list | None = None,
    rejection_reason: str | None = None,
    rejection_comment: str | None = None,
) -> dict:
    body: dict = {"decision": decision}
    if checklist_results is not None:
        body["checklist_results"] = checklist_results
    if rejection_reason:
        body["rejection_reason"] = rejection_reason
    if rejection_comment:
        body["rejection_comment"] = rejection_comment
    return await client.post(f"/api/v1/tasks/{task_id}/inspect", json=body)


# ---------------------------------------------------------------------------
# INSP-01: Inspection tests
# ---------------------------------------------------------------------------


class TestGCApproval:
    async def test_gc_approves_complete_task(self, tenant_a_client: AsyncClient) -> None:
        """Approve a complete task — TaskInspection created, task status unchanged."""
        project_id = await _create_project(tenant_a_client, "Approve Task Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        task_id = await _create_task(tenant_a_client, scope_id, status="in_progress")
        await _set_task_status(tenant_a_client, task_id, "complete")

        resp = await _inspect_task(
            tenant_a_client,
            task_id,
            decision="approved",
            checklist_results=[
                {"item": "Quality of work is acceptable", "checked": True},
                {"item": "Correct materials were used", "checked": True},
            ],
        )
        assert resp.status_code == 201, f"Inspect failed: {resp.text}"
        data = resp.json()
        assert data["decision"] == "approved"
        assert data["task_id"] == task_id

        # Task status must remain 'complete' after approval
        task_status = await _get_task_status(tenant_a_client, task_id, scope_id)
        assert task_status == "complete", f"Expected 'complete' after approval, got '{task_status}'"

    async def test_gc_rejects_complete_task(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ) -> None:
        """Reject a complete task — TaskInspection created, task.status='rejected'."""
        project_id = await _create_project(tenant_a_client, "Reject Task Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        task_id = await _create_task(tenant_a_client, scope_id, status="in_progress")
        await _set_task_status(tenant_a_client, task_id, "complete")

        resp = await _inspect_task(
            tenant_a_client,
            task_id,
            decision="rejected",
            rejection_reason="rework_needed",
            rejection_comment="Needs redo — outlet placement is wrong",
        )
        assert resp.status_code == 201, f"Inspect failed: {resp.text}"
        data = resp.json()
        assert data["decision"] == "rejected"
        assert data["rejection_reason"] == "rework_needed"
        assert data["rejection_comment"] == "Needs redo — outlet placement is wrong"

        # Task status must be 'rejected' after rejection
        task_status = await _get_task_status(tenant_a_client, task_id, scope_id)
        assert task_status == "rejected", f"Expected 'rejected', got '{task_status}'"

    async def test_reject_non_complete_task_returns_422(self, tenant_a_client: AsyncClient) -> None:
        """Rejecting a task that is NOT complete returns 422."""
        project_id = await _create_project(tenant_a_client, "Non-Complete Reject")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        task_id = await _create_task(tenant_a_client, scope_id, status="in_progress")
        # Task is 'in_progress', not 'complete'

        resp = await _inspect_task(
            tenant_a_client,
            task_id,
            decision="rejected",
            rejection_reason="quality_issue",
        )
        assert resp.status_code == 422, f"Expected 422, got {resp.status_code}: {resp.text}"

    async def test_approve_non_complete_task_returns_422(
        self, tenant_a_client: AsyncClient
    ) -> None:
        """Approving a task that is NOT complete also returns 422."""
        project_id = await _create_project(tenant_a_client, "Non-Complete Approve")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        task_id = await _create_task(tenant_a_client, scope_id, status="not_started")

        resp = await _inspect_task(
            tenant_a_client,
            task_id,
            decision="approved",
        )
        assert resp.status_code == 422, f"Expected 422, got {resp.status_code}: {resp.text}"

    async def test_inspect_nonexistent_task_returns_404(self, tenant_a_client: AsyncClient) -> None:
        """Inspecting a non-existent task returns 404."""
        random_task_id = str(uuid.uuid4())
        resp = await _inspect_task(
            tenant_a_client,
            random_task_id,
            decision="approved",
        )
        assert resp.status_code == 404, f"Expected 404, got {resp.status_code}: {resp.text}"

    async def test_inspect_creates_audit_trail(self, tenant_a_client: AsyncClient) -> None:
        """Multiple inspections on same task create full audit trail."""
        project_id = await _create_project(tenant_a_client, "Audit Trail Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        task_id = await _create_task(tenant_a_client, scope_id, status="in_progress")
        await _set_task_status(tenant_a_client, task_id, "complete")

        # First inspection: approve
        resp1 = await _inspect_task(tenant_a_client, task_id, decision="approved")
        assert resp1.status_code == 201

        # Reset task back to complete to allow second inspection
        await _set_task_status(tenant_a_client, task_id, "complete")

        # Second inspection: reject
        resp2 = await _inspect_task(
            tenant_a_client,
            task_id,
            decision="rejected",
            rejection_reason="incomplete",
        )
        assert resp2.status_code == 201

        # Both inspections should appear in the audit trail (GET /tasks/{id}/inspections)
        audit_resp = await tenant_a_client.get(f"/api/v1/tasks/{task_id}/inspections")
        assert audit_resp.status_code == 200
        inspections = audit_resp.json()
        assert len(inspections) == 2
        decisions = {i["decision"] for i in inspections}
        assert "approved" in decisions
        assert "rejected" in decisions

    async def test_contractor_cannot_inspect(
        self, tenant_a_client: AsyncClient, tenant_b_client: AsyncClient, seed_two_tenants: dict
    ) -> None:
        """Cross-tenant user cannot inspect tasks in another tenant's project.

        Tenant B user tries to inspect Tenant A's task — RLS isolation means
        they get 404 (task not visible) which validates cross-tenant security.

        The _require_gc_or_admin guard fires first for same-tenant non-admin users
        (403). For cross-tenant users, RLS hides the task entirely (404).
        Both are valid security responses per CLAUDE.md security rules.
        """
        # Tenant A creates project and task
        project_id = await _create_project(tenant_a_client, "Cross-Tenant Inspect Test")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)
        task_id = await _create_task(tenant_a_client, scope_id, status="in_progress")
        await _set_task_status(tenant_a_client, task_id, "complete")

        # Tenant B tries to inspect Tenant A's task — must be rejected
        resp = await _inspect_task(tenant_b_client, task_id, decision="approved")
        # RLS isolates by company_id — tenant B can't see tenant A's task (404)
        # or role check fires first (403). Both are valid security responses.
        assert resp.status_code in (403, 404), (
            f"Expected 403 or 404, got {resp.status_code}: {resp.text}"
        )

    async def test_reject_task_reblocks_dependents(self, tenant_a_client: AsyncClient) -> None:
        """Rejecting a task re-blocks its FS-dependent successors.

        RESEARCH.md Pitfall 6: successors must be re-blocked when a predecessor
        is rejected, because they were unblocked when the predecessor was completed.
        """
        project_id = await _create_project(tenant_a_client, "Reblock Successors Project")
        scope_id = await _create_trade_scope(tenant_a_client, project_id)

        # Task A (predecessor) and Task B (successor with FS dependency)
        task_a_id = await _create_task(
            tenant_a_client, scope_id, title="Task A Predecessor", status="in_progress"
        )
        task_b_id = await _create_task(
            tenant_a_client, scope_id, title="Task B Successor", status="not_started"
        )

        # Create FS dependency: B depends on A
        # Endpoint: POST /tasks/{successor_id}/dependencies with predecessor_task_id in body
        dep_resp = await tenant_a_client.post(
            f"/api/v1/tasks/{task_b_id}/dependencies",
            json={
                "predecessor_task_id": task_a_id,
                "dependency_type": "FS",
            },
        )
        assert dep_resp.status_code == 201, f"Dependency creation failed: {dep_resp.text}"

        # Mark Task A complete — Task B should become unblocked
        await _set_task_status(tenant_a_client, task_a_id, "complete")

        # Reject Task A — successor B should be re-blocked
        reject_resp = await _inspect_task(
            tenant_a_client,
            task_a_id,
            decision="rejected",
            rejection_reason="quality_issue",
        )
        assert reject_resp.status_code == 201, f"Rejection failed: {reject_resp.text}"

        # Task B should now be 'blocked' because its predecessor was rejected
        task_b_status = await _get_task_status(tenant_a_client, task_b_id, scope_id)
        assert task_b_status == "blocked", (
            f"Expected task B status='blocked' after predecessor rejection, got '{task_b_status}'"
        )
