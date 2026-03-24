"""Phase 21 E2E integration tests — AI intake and interview flows.

Tests verify the full HTTP -> service -> DB state path for:
- AI project intake (start, message, complete)
- AI contractor interview (start, message, complete)
- SSE streaming
- Tool validation
- Transaction rollback on partial failure
- Dependency edge creation (D-23)

All tests mock the Anthropic API to avoid real API calls.
All tests use seed_two_tenants + clean_tables for isolation.
"""

from __future__ import annotations

import io
import json
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import pytest_asyncio
from httpx import AsyncClient
from PIL import Image as PILImage

# ---------------------------------------------------------------------------
# Mock Anthropic helpers
# ---------------------------------------------------------------------------


def _make_stream_mock(events: list[dict]) -> MagicMock:
    """Create a mock stream context manager yielding the given event dicts.

    Each event dict should have 'type' and any other relevant fields.
    """
    mock_stream = MagicMock()

    async def _async_gen():
        for event in events:
            mock_event = MagicMock()
            mock_event.type = event["type"]
            if event["type"] == "content_block_delta":
                mock_delta = MagicMock()
                mock_delta.type = "text_delta"
                mock_delta.text = event.get("text", "")
                mock_event.delta = mock_delta
            yield mock_event

    # Final message mock
    final_msg = MagicMock()
    final_msg.stop_reason = "end_turn"
    final_msg.content = []
    for event in events:
        if event["type"] == "tool_use":
            block = MagicMock()
            block.type = "tool_use"
            block.name = event["name"]
            block.input = event["input"]
            block.id = event.get("id", f"toolu_{uuid.uuid4().hex[:16]}")
            final_msg.content.append(block)

    mock_stream.__aiter__ = lambda self: _async_gen()
    mock_stream.get_final_message = AsyncMock(return_value=final_msg)

    mock_ctx = MagicMock()
    mock_ctx.__aenter__ = AsyncMock(return_value=mock_stream)
    mock_ctx.__aexit__ = AsyncMock(return_value=False)
    return mock_ctx


@pytest_asyncio.fixture
def mock_anthropic_text():
    """Mock Anthropic client to return a simple text response."""
    ctx = _make_stream_mock([{"type": "content_block_delta", "text": "Hello from AI"}])
    with patch("app.features.ai.service._anthropic_client") as mock_client:
        mock_client.messages.stream.return_value = ctx
        yield mock_client


@pytest_asyncio.fixture
def mock_anthropic_tool_create_scopes():
    """Mock Anthropic client to return 3 create_trade_scope tool calls."""
    scopes = [
        {"trade_name": "Electrical", "sort_order": 0, "trade_color": "#FFC107"},
        {"trade_name": "Plumbing", "sort_order": 1, "trade_color": "#2196F3"},
        {"trade_name": "Framing", "sort_order": 2, "trade_color": "#4CAF50"},
    ]
    events = [
        {
            "type": "tool_use",
            "name": "create_trade_scope",
            "input": scope,
            "id": f"toolu_{i:016d}",
        }
        for i, scope in enumerate(scopes)
    ]
    ctx = _make_stream_mock(events)
    with patch("app.features.ai.service._anthropic_client") as mock_client:
        mock_client.messages.stream.return_value = ctx
        yield mock_client


@pytest_asyncio.fixture
def mock_anthropic_clarifying_question():
    """Mock Anthropic client to return an ask_clarifying_question tool call."""
    events = [
        {
            "type": "tool_use",
            "name": "ask_clarifying_question",
            "input": {"question": "How many bathrooms does the project have?"},
            "id": "toolu_clarify_001",
        }
    ]
    ctx = _make_stream_mock(events)
    with patch("app.features.ai.service._anthropic_client") as mock_client:
        mock_client.messages.stream.return_value = ctx
        yield mock_client


@pytest_asyncio.fixture
def mock_anthropic_create_tasks():
    """Mock Anthropic client to return 3 create_task tool calls."""
    tasks = [
        {"title": "Install main panel", "sort_order": 0, "priority": "high"},
        {"title": "Run branch circuits", "sort_order": 1, "priority": "medium"},
        {"title": "Install outlets and switches", "sort_order": 2, "priority": "medium"},
    ]
    events = [
        {
            "type": "tool_use",
            "name": "create_task",
            "input": task,
            "id": f"toolu_task_{i:016d}",
        }
        for i, task in enumerate(tasks)
    ]
    ctx = _make_stream_mock(events)
    with patch("app.features.ai.service._anthropic_client") as mock_client:
        mock_client.messages.stream.return_value = ctx
        yield mock_client


# ---------------------------------------------------------------------------
# Helper: parse SSE events from streaming response
# ---------------------------------------------------------------------------


def _parse_sse_events(content: bytes) -> list[dict]:
    """Parse SSE event stream bytes into list of {event, data} dicts."""
    events = []
    lines = content.decode("utf-8").split("\n")
    current_event: dict[str, str] = {}
    for line in lines:
        if line.startswith("event: "):
            current_event["event"] = line[7:]
        elif line.startswith("data: "):
            current_event["data"] = line[6:]
        elif line == "" and current_event:
            if "event" in current_event and "data" in current_event:
                try:
                    current_event["parsed"] = json.loads(current_event["data"])
                except json.JSONDecodeError:
                    current_event["parsed"] = {}
                events.append(current_event)
            current_event = {}
    return events


# ---------------------------------------------------------------------------
# Intake flow tests
# ---------------------------------------------------------------------------


class TestIntakeFlow:
    @pytest.mark.asyncio
    async def test_intake_start_creates_conversation(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """POST /ai/intake/start returns 201 with conversation_id, type=intake, status=active."""
        resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        assert resp.status_code == 201, resp.text
        data = resp.json()
        assert "id" in data
        assert data["conv_type"] == "intake"
        assert data["status"] == "active"
        assert data["project_id"] is None

    @pytest.mark.asyncio
    async def test_intake_message_returns_sse_stream(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_text,
    ):
        """POST /ai/intake/message returns text/event-stream with token events."""
        # Start conversation
        start_resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        assert start_resp.status_code == 201
        conv_id = start_resp.json()["id"]

        # Send message
        resp = await tenant_a_client.post(
            "/api/v1/ai/intake/message",
            json={"conversation_id": conv_id, "message": "Build a 3-bedroom house"},
        )
        assert resp.status_code == 200
        assert "text/event-stream" in resp.headers.get("content-type", "")

        events = _parse_sse_events(resp.content)
        event_types = [e["event"] for e in events]
        # Should have at least a done event
        assert "done" in event_types

    @pytest.mark.asyncio
    async def test_intake_message_requires_auth(self, async_client: AsyncClient):
        """POST /ai/intake/message without token returns 401."""
        resp = await async_client.post(
            "/api/v1/ai/intake/message",
            json={"conversation_id": str(uuid.uuid4()), "message": "Hello"},
        )
        assert resp.status_code == 401

    @pytest.mark.asyncio
    async def test_intake_produces_trade_scopes(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_tool_create_scopes,
    ):
        """Full intake flow: start -> message -> complete creates 3 trade scopes."""
        # Start
        start_resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        assert start_resp.status_code == 201
        conv_id = start_resp.json()["id"]

        # Message (the mock streams tool_use blocks but we just verify SSE returned)
        msg_resp = await tenant_a_client.post(
            "/api/v1/ai/intake/message",
            json={
                "conversation_id": conv_id,
                "message": "Build a house with electrical, plumbing, framing",
            },
        )
        assert msg_resp.status_code == 200

        # Complete — provide the 3 trade scopes
        complete_resp = await tenant_a_client.post(
            "/api/v1/ai/intake/complete",
            json={
                "conversation_id": conv_id,
                "project_name": "New House Build",
                "trade_scopes": [
                    {"trade_name": "Electrical", "sort_order": 0, "trade_color": "#FFC107"},
                    {"trade_name": "Plumbing", "sort_order": 1, "trade_color": "#2196F3"},
                    {"trade_name": "Framing", "sort_order": 2, "trade_color": "#4CAF50"},
                ],
            },
        )
        assert complete_resp.status_code == 200, complete_resp.text
        result = complete_resp.json()
        assert "project_id" in result
        assert len(result["trade_scope_ids"]) == 3

        # Verify trade scopes exist via GET
        project_id = result["project_id"]
        scopes_resp = await tenant_a_client.get(f"/api/v1/trade-scopes/?project_id={project_id}")
        assert scopes_resp.status_code == 200
        scopes = scopes_resp.json()
        scope_names = [s["trade_name"] for s in scopes]
        assert "Electrical" in scope_names
        assert "Plumbing" in scope_names
        assert "Framing" in scope_names

    @pytest.mark.asyncio
    async def test_intake_complete_creates_dependency_edges(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_tool_create_scopes,
    ):
        """intake/complete with 3 sorted scopes creates 2 dependency edges (0->1, 1->2)."""
        # Start
        start_resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        conv_id = start_resp.json()["id"]

        # Complete with 3 scopes
        complete_resp = await tenant_a_client.post(
            "/api/v1/ai/intake/complete",
            json={
                "conversation_id": conv_id,
                "project_name": "Dependency Test Project",
                "trade_scopes": [
                    {"trade_name": "Framing", "sort_order": 0},
                    {"trade_name": "Electrical", "sort_order": 1},
                    {"trade_name": "Finishes", "sort_order": 2},
                ],
            },
        )
        assert complete_resp.status_code == 200, complete_resp.text
        result = complete_resp.json()
        scope_ids = result["trade_scope_ids"]
        assert len(scope_ids) == 3

        # Verify placeholder tasks exist for each scope
        all_placeholder_tasks = []
        for scope_id in scope_ids:
            tasks_resp = await tenant_a_client.get(f"/api/v1/tasks/?trade_scope_id={scope_id}")
            assert tasks_resp.status_code == 200
            scope_tasks = tasks_resp.json()
            placeholder_tasks = [t for t in scope_tasks if "[Scope placeholder]" in t["title"]]
            assert len(placeholder_tasks) == 1, (
                f"Expected 1 placeholder for scope {scope_id}, got {len(placeholder_tasks)}"
            )
            all_placeholder_tasks.extend(placeholder_tasks)

        assert len(all_placeholder_tasks) == 3

        # Verify dependency edges exist.
        # The GET endpoint returns edges where the task is predecessor OR successor.
        # scope0: 1 outgoing edge (scope0->scope1)
        # scope1: 2 edges (scope0->scope1 incoming, scope1->scope2 outgoing)
        # scope2: 1 incoming edge (scope1->scope2)
        # Total across all 3 tasks = 4 (each of the 2 edges is counted twice).
        # Deduplicate by unique edge ID to confirm exactly 2 unique edges exist.
        seen_edge_ids: set[str] = set()
        for task in all_placeholder_tasks:
            dep_resp = await tenant_a_client.get(f"/api/v1/tasks/{task['id']}/dependencies")
            assert dep_resp.status_code == 200
            deps = dep_resp.json()
            for dep in deps:
                seen_edge_ids.add(dep["id"])

        assert len(seen_edge_ids) == 2, (
            f"Expected 2 unique dependency edges, got {len(seen_edge_ids)}: {seen_edge_ids}"
        )

    @pytest.mark.asyncio
    async def test_intake_complete_rolls_back_on_partial_failure(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_tool_create_scopes,
    ):
        """If a trade scope creation fails mid-batch, no scopes or project are persisted."""
        # Start conversation
        start_resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        conv_id = start_resp.json()["id"]

        # Patch TradeScopeService.create to fail on the 2nd call
        from app.features.projects.service import TradeScopeService

        original_create = TradeScopeService.create
        call_count = [0]

        async def _failing_create(self_svc, data, user_id=None):
            call_count[0] += 1
            if call_count[0] == 2:
                raise RuntimeError("Simulated failure on 2nd scope")
            return await original_create(self_svc, data, user_id=user_id)

        # The test patches TradeScopeService.create to raise RuntimeError on 2nd call.
        # FastAPI/ASGI may propagate this as an exception rather than a 500 response
        # in the test transport. Catch either outcome.
        import contextlib

        resp = None
        with (
            patch.object(TradeScopeService, "create", _failing_create),
            contextlib.suppress(Exception),
        ):
            resp = await tenant_a_client.post(
                "/api/v1/ai/intake/complete",
                json={
                    "conversation_id": conv_id,
                    "project_name": "Rollback Test",
                    "trade_scopes": [
                        {"trade_name": "Scope A", "sort_order": 0},
                        {"trade_name": "Scope B", "sort_order": 1},
                        {"trade_name": "Scope C", "sort_order": 2},
                    ],
                },
            )

        # Either an exception was raised (resp is None) or an error response was returned
        if resp is not None:
            assert resp.status_code in (500, 422, 400), (
                f"Expected error, got {resp.status_code}: {resp.text}"
            )

        # Conversation should NOT be marked complete — it stays active because the
        # transaction rolled back (get_db's auto-rollback on exception)
        conv_resp = await tenant_a_client.get(f"/api/v1/ai/conversations/{conv_id}")
        assert conv_resp.status_code == 200
        conv_data = conv_resp.json()
        assert conv_data["status"] == "active"

    @pytest.mark.asyncio
    async def test_intake_asks_clarifying_questions(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_clarifying_question,
    ):
        """Mock streams ask_clarifying_question tool -> SSE includes tool_call event."""
        start_resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        conv_id = start_resp.json()["id"]

        resp = await tenant_a_client.post(
            "/api/v1/ai/intake/message",
            json={"conversation_id": conv_id, "message": "renovate"},
        )
        assert resp.status_code == 200

        events = _parse_sse_events(resp.content)
        event_types = [e["event"] for e in events]
        assert "tool_call" in event_types

        tool_events = [e for e in events if e["event"] == "tool_call"]
        assert any(e["parsed"]["tool"] == "ask_clarifying_question" for e in tool_events)


# ---------------------------------------------------------------------------
# Interview flow tests
# ---------------------------------------------------------------------------


class TestInterviewFlow:
    @pytest.mark.asyncio
    async def test_interview_start_requires_scope(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """POST /ai/interview/start without scope_id returns 422."""
        resp = await tenant_a_client.post("/api/v1/ai/interview/start")
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_interview_start_unknown_scope_returns_404(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """POST /ai/interview/start with unknown scope_id returns 404."""
        resp = await tenant_a_client.post(f"/api/v1/ai/interview/start?scope_id={uuid.uuid4()}")
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_interview_start_and_message(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_text,
    ):
        """Create project + scope then start/message interview."""
        # Create project and scope
        proj_resp = await tenant_a_client.post(
            "/api/v1/projects/",
            json={"name": "Interview Test Project"},
        )
        assert proj_resp.status_code == 201
        project_id = proj_resp.json()["id"]

        scope_resp = await tenant_a_client.post(
            "/api/v1/trade-scopes/",
            json={"project_id": project_id, "trade_name": "Electrical"},
        )
        assert scope_resp.status_code == 201
        scope_id = scope_resp.json()["id"]

        # Start interview
        start_resp = await tenant_a_client.post(f"/api/v1/ai/interview/start?scope_id={scope_id}")
        assert start_resp.status_code == 201
        data = start_resp.json()
        assert data["conv_type"] == "interview"
        assert data["status"] == "active"
        conv_id = data["id"]

        # Send message
        msg_resp = await tenant_a_client.post(
            "/api/v1/ai/interview/message",
            json={"conversation_id": conv_id, "message": "I'll install the electrical system"},
        )
        assert msg_resp.status_code == 200
        assert "text/event-stream" in msg_resp.headers.get("content-type", "")

    @pytest.mark.asyncio
    async def test_interview_produces_tasks(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_create_tasks,
    ):
        """Full interview flow: start -> message -> complete creates 3 tasks."""
        # Create project and scope
        proj_resp = await tenant_a_client.post(
            "/api/v1/projects/",
            json={"name": "Task Generation Project"},
        )
        project_id = proj_resp.json()["id"]

        scope_resp = await tenant_a_client.post(
            "/api/v1/trade-scopes/",
            json={"project_id": project_id, "trade_name": "Electrical"},
        )
        scope_id = scope_resp.json()["id"]

        # Start interview
        start_resp = await tenant_a_client.post(f"/api/v1/ai/interview/start?scope_id={scope_id}")
        conv_id = start_resp.json()["id"]

        # Message (mock returns create_task tool calls)
        await tenant_a_client.post(
            "/api/v1/ai/interview/message",
            json={"conversation_id": conv_id, "message": "I'm the licensed electrician"},
        )

        # Complete with 3 tasks
        complete_resp = await tenant_a_client.post(
            "/api/v1/ai/interview/complete",
            json={
                "conversation_id": conv_id,
                "tasks": [
                    {"title": "Install main panel", "sort_order": 0, "priority": "high"},
                    {"title": "Run branch circuits", "sort_order": 1, "priority": "medium"},
                    {"title": "Install outlets", "sort_order": 2, "priority": "medium"},
                ],
            },
        )
        assert complete_resp.status_code == 200, complete_resp.text
        result = complete_resp.json()
        assert len(result["task_ids"]) == 3

        # Verify tasks exist
        tasks_resp = await tenant_a_client.get(f"/api/v1/tasks/?trade_scope_id={scope_id}")
        assert tasks_resp.status_code == 200
        tasks = tasks_resp.json()
        titles = [t["title"] for t in tasks]
        assert "Install main panel" in titles
        assert "Run branch circuits" in titles
        assert "Install outlets" in titles

    @pytest.mark.asyncio
    async def test_conversation_reentry(
        self,
        tenant_a_client: AsyncClient,
        seed_two_tenants: dict,
        mock_anthropic_text,
    ):
        """Start conversation, send message, then GET conversation shows messages."""
        # Start
        start_resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        conv_id = start_resp.json()["id"]

        # Send message
        await tenant_a_client.post(
            "/api/v1/ai/intake/message",
            json={"conversation_id": conv_id, "message": "Build a warehouse"},
        )

        # GET conversation
        get_resp = await tenant_a_client.get(f"/api/v1/ai/conversations/{conv_id}")
        assert get_resp.status_code == 200
        data = get_resp.json()
        assert data["id"] == conv_id
        assert data["status"] == "active"
        # Should have at least the user message persisted
        assert len(data["messages"]) >= 1
        assert data["messages"][0]["role"] == "user"


# ---------------------------------------------------------------------------
# Cross-tenant isolation test
# ---------------------------------------------------------------------------


class TestTenantIsolation:
    @pytest.mark.asyncio
    async def test_conversation_not_visible_to_other_tenant(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        """Tenant A's conversation is not accessible by Tenant B."""
        # Tenant A starts a conversation
        resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        assert resp.status_code == 201
        conv_id = resp.json()["id"]

        # Tenant B tries to access it
        resp_b = await tenant_b_client.get(f"/api/v1/ai/conversations/{conv_id}")
        # Should return 404 (RLS hides the record) or 403
        assert resp_b.status_code in (404, 403)


# ---------------------------------------------------------------------------
# Image upload helpers
# ---------------------------------------------------------------------------


def _make_test_jpeg(width: int = 10, height: int = 10) -> bytes:
    """Create a minimal JPEG in memory."""
    img = PILImage.new("RGB", (width, height), color="red")
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


async def _start_intake_conversation(client) -> str:
    """Start an intake conversation and return the conversation_id."""
    resp = await client.post("/api/v1/ai/intake/start")
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


# ---------------------------------------------------------------------------
# Image upload tests
# ---------------------------------------------------------------------------


class TestImageUpload:
    @pytest.mark.asyncio
    async def test_image_upload_returns_ref_id(self, tenant_a_client, seed_two_tenants: dict):
        """POST /ai/intake/image with a JPEG returns 201 with a valid UUID id."""
        conv_id = await _start_intake_conversation(tenant_a_client)
        jpeg_bytes = _make_test_jpeg(10, 10)

        resp = await tenant_a_client.post(
            "/api/v1/ai/intake/image",
            files={"file": ("test.jpg", jpeg_bytes, "image/jpeg")},
            data={"conversation_id": conv_id},
        )
        assert resp.status_code == 201, resp.text
        data = resp.json()
        assert "id" in data
        # Verify the id is a valid UUID
        uuid.UUID(data["id"])
        assert data["conversation_id"] == conv_id
        assert data["media_type"] == "image/jpeg"
        assert data["original_filename"] == "test.jpg"

    @pytest.mark.asyncio
    async def test_image_upload_rejects_non_image(self, tenant_a_client, seed_two_tenants: dict):
        """POST /ai/intake/image with a .txt file returns 400 with 'image' in detail."""
        conv_id = await _start_intake_conversation(tenant_a_client)

        resp = await tenant_a_client.post(
            "/api/v1/ai/intake/image",
            files={"file": ("test.txt", b"hello world", "text/plain")},
            data={"conversation_id": conv_id},
        )
        assert resp.status_code == 400, resp.text
        detail = resp.json()["detail"].lower()
        assert "image" in detail

    @pytest.mark.asyncio
    async def test_image_upload_compresses_large_image(
        self, tenant_a_client, seed_two_tenants: dict
    ):
        """POST /ai/intake/image with 2000x2000 JPEG stores compressed file <= 1280x1280."""
        import glob
        import os

        conv_id = await _start_intake_conversation(tenant_a_client)
        large_jpeg = _make_test_jpeg(2000, 2000)

        resp = await tenant_a_client.post(
            "/api/v1/ai/intake/image",
            files={"file": ("large.jpg", large_jpeg, "image/jpeg")},
            data={"conversation_id": conv_id},
        )
        assert resp.status_code == 201, resp.text
        data = resp.json()

        # Verify the stored file dimensions are <= 1280x1280
        assert data["file_size_bytes"] > 0
        assert data["conversation_id"] == conv_id

        # Find the uploaded file on disk by convention (uploads/ai_images/{conv_id}/*.jpg)
        # The server saves files relative to the backend working directory
        backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        upload_pattern = os.path.join(backend_dir, f"uploads/ai_images/{conv_id}/*.jpg")
        uploaded_files = glob.glob(upload_pattern)
        assert len(uploaded_files) >= 1, f"No uploaded files found at pattern: {upload_pattern}"

        # Open the compressed file and verify its dimensions are <= 1280x1280
        compressed_img = PILImage.open(uploaded_files[0])
        width, height = compressed_img.size
        assert width <= 1280, f"Width {width} exceeds 1280"
        assert height <= 1280, f"Height {height} exceeds 1280"

    @pytest.mark.asyncio
    async def test_chat_turn_with_image_includes_vision_block(
        self, tenant_a_client, seed_two_tenants: dict, mock_anthropic_text
    ):
        """Upload image then POST intake/message with image_ref_id sends base64 vision block."""
        conv_id = await _start_intake_conversation(tenant_a_client)
        jpeg_bytes = _make_test_jpeg(10, 10)

        # Upload image
        upload_resp = await tenant_a_client.post(
            "/api/v1/ai/intake/image",
            files={"file": ("photo.jpg", jpeg_bytes, "image/jpeg")},
            data={"conversation_id": conv_id},
        )
        assert upload_resp.status_code == 201, upload_resp.text
        image_ref_id = upload_resp.json()["id"]

        # Capture the messages passed to the Anthropic mock
        captured_messages = []
        original_stream = mock_anthropic_text.messages.stream

        def capturing_stream(**kwargs):
            captured_messages.extend(kwargs.get("messages", []))
            return original_stream(**kwargs)

        mock_anthropic_text.messages.stream.side_effect = capturing_stream

        # Send chat turn with image_ref_id
        msg_resp = await tenant_a_client.post(
            "/api/v1/ai/intake/message",
            json={
                "conversation_id": conv_id,
                "message": "What do you see in this photo?",
                "image_ref_id": image_ref_id,
            },
        )
        assert msg_resp.status_code == 200, msg_resp.text

        # Find the user message in captured messages
        user_messages = [m for m in captured_messages if m.get("role") == "user"]
        assert len(user_messages) >= 1

        # The last user message should contain an image block
        last_user = user_messages[-1]
        content = last_user["content"]
        assert isinstance(content, list), f"Expected list content, got {type(content)}"

        image_blocks = [
            block for block in content if isinstance(block, dict) and block.get("type") == "image"
        ]
        assert len(image_blocks) >= 1, f"No image blocks found in content: {content}"
        image_block = image_blocks[0]
        assert image_block["source"]["type"] == "base64"
        assert "data" in image_block["source"]
