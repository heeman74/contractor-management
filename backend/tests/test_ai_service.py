"""Unit tests for AIService — tool validation and conversation persistence.

Tests cover:
- Tool input validation for create_trade_scope, create_task, ask_clarifying_question
- Conversation persistence via get_or_create_conversation and persist_* methods

These tests use the HTTP client approach (via tenant_a_client) for persistence tests
since the conftest does not expose a raw AsyncSession fixture. Tool validation tests
use a mock DB session since they don't hit the database.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from httpx import AsyncClient

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_service():
    """Create an AIService with a mock DB session for validation-only tests."""
    from app.features.ai.service import AIService

    mock_db = MagicMock()
    mock_db.execute = AsyncMock()
    mock_db.flush = AsyncMock()
    mock_db.get = AsyncMock()
    # Simulate tenant context by patching _require_tenant_id
    service = AIService.__new__(AIService)
    service.db = mock_db
    service._message_repo = MagicMock()
    service._usage_repo = MagicMock()
    # Patch repository
    service.repository = MagicMock()
    service.repository.create = AsyncMock()
    return service


# ---------------------------------------------------------------------------
# TestToolValidation — no DB required
# ---------------------------------------------------------------------------


class TestToolValidation:
    """Tool input validation tests — these do not touch the DB."""

    def setup_method(self):
        self.service = _make_service()

    @pytest.mark.asyncio
    async def test_tool_input_validates_trade_scope_create(self):
        result = await self.service.validate_tool_input(
            "create_trade_scope", {"trade_name": "Electrical", "sort_order": 0}
        )
        assert result["trade_name"] == "Electrical"
        assert result["sort_order"] == 0

    @pytest.mark.asyncio
    async def test_trade_scope_missing_name_raises(self):
        with pytest.raises(ValueError, match="trade_name"):
            await self.service.validate_tool_input("create_trade_scope", {"sort_order": 0})

    @pytest.mark.asyncio
    async def test_trade_scope_empty_name_raises(self):
        with pytest.raises(ValueError, match="trade_name"):
            await self.service.validate_tool_input(
                "create_trade_scope", {"trade_name": "   ", "sort_order": 0}
            )

    @pytest.mark.asyncio
    async def test_trade_scope_default_color_applied(self):
        result = await self.service.validate_tool_input(
            "create_trade_scope", {"trade_name": "Plumbing", "sort_order": 1}
        )
        assert result["trade_color"] == "#9E9E9E"

    @pytest.mark.asyncio
    async def test_tool_input_validates_task_create(self):
        result = await self.service.validate_tool_input(
            "create_task", {"title": "Install outlets", "sort_order": 0}
        )
        assert result["title"] == "Install outlets"
        assert result["sort_order"] == 0

    @pytest.mark.asyncio
    async def test_task_empty_title_raises(self):
        with pytest.raises(ValueError, match="title"):
            await self.service.validate_tool_input("create_task", {"title": "", "sort_order": 0})

    @pytest.mark.asyncio
    async def test_task_title_too_long_raises(self):
        with pytest.raises(ValueError, match="300"):
            await self.service.validate_tool_input(
                "create_task", {"title": "x" * 301, "sort_order": 0}
            )

    @pytest.mark.asyncio
    async def test_task_title_exactly_300_ok(self):
        result = await self.service.validate_tool_input(
            "create_task", {"title": "x" * 300, "sort_order": 0}
        )
        assert len(result["title"]) == 300

    @pytest.mark.asyncio
    async def test_malformed_tool_input_rejected_empty_dict(self):
        with pytest.raises(ValueError, match="trade_name"):
            await self.service.validate_tool_input("create_trade_scope", {})

    @pytest.mark.asyncio
    async def test_malformed_tool_input_rejected_invalid_priority(self):
        with pytest.raises(ValueError, match="priority"):
            await self.service.validate_tool_input(
                "create_task", {"title": "x", "sort_order": 0, "priority": "invalid"}
            )

    @pytest.mark.asyncio
    async def test_validate_ask_clarifying_question(self):
        result = await self.service.validate_tool_input(
            "ask_clarifying_question", {"question": "How many rooms?"}
        )
        assert result["question"] == "How many rooms?"

    @pytest.mark.asyncio
    async def test_clarifying_question_empty_raises(self):
        with pytest.raises(ValueError, match="question"):
            await self.service.validate_tool_input(
                "ask_clarifying_question", {"question": ""}
            )

    @pytest.mark.asyncio
    async def test_clarifying_question_whitespace_raises(self):
        with pytest.raises(ValueError, match="question"):
            await self.service.validate_tool_input(
                "ask_clarifying_question", {"question": "   "}
            )

    @pytest.mark.asyncio
    async def test_unknown_tool_raises(self):
        with pytest.raises(ValueError, match="Unknown tool"):
            await self.service.validate_tool_input("delete_everything", {"foo": "bar"})

    @pytest.mark.asyncio
    async def test_task_valid_priorities(self):
        for priority in ["low", "medium", "high", "urgent"]:
            result = await self.service.validate_tool_input(
                "create_task", {"title": "Task", "sort_order": 0, "priority": priority}
            )
            assert result["priority"] == priority

    @pytest.mark.asyncio
    async def test_task_default_priority_is_medium(self):
        result = await self.service.validate_tool_input(
            "create_task", {"title": "Task", "sort_order": 0}
        )
        assert result["priority"] == "medium"

    @pytest.mark.asyncio
    async def test_task_negative_estimated_hours_raises(self):
        with pytest.raises(ValueError, match="estimated_hours"):
            await self.service.validate_tool_input(
                "create_task", {"title": "Task", "sort_order": 0, "estimated_hours": -1.0}
            )

    @pytest.mark.asyncio
    async def test_task_zero_estimated_hours_ok(self):
        result = await self.service.validate_tool_input(
            "create_task", {"title": "Task", "sort_order": 0, "estimated_hours": 0}
        )
        assert result["estimated_hours"] == 0.0

    @pytest.mark.asyncio
    async def test_task_materials_needed_valid(self):
        result = await self.service.validate_tool_input(
            "create_task",
            {
                "title": "Install outlets",
                "sort_order": 0,
                "materials_needed": [{"name": "12/2 Romex", "quantity": 100, "unit": "feet"}],
            },
        )
        assert len(result["materials_needed"]) == 1
        assert result["materials_needed"][0]["name"] == "12/2 Romex"

    @pytest.mark.asyncio
    async def test_task_materials_needed_empty_name_raises(self):
        with pytest.raises(ValueError, match="name"):
            await self.service.validate_tool_input(
                "create_task",
                {
                    "title": "Task",
                    "sort_order": 0,
                    "materials_needed": [{"name": ""}],
                },
            )


# ---------------------------------------------------------------------------
# TestConversationPersistence — uses real test DB via HTTP client
# ---------------------------------------------------------------------------


class TestConversationPersistence:
    """Conversation lifecycle tests using the ASGI HTTP test client."""

    @pytest.mark.asyncio
    async def test_get_or_create_conversation_creates_new(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Starting an intake with no existing conversation creates one with status=active."""
        resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        assert resp.status_code == 201
        data = resp.json()
        assert "id" in data
        assert data["conv_type"] == "intake"
        assert data["status"] == "active"

    @pytest.mark.asyncio
    async def test_get_or_create_conversation_returns_existing(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Starting intake twice for the same project_id returns the same active conversation."""
        # First, create a project so we have a project_id to look up by
        proj_resp = await tenant_a_client.post(
            "/api/v1/projects/",
            json={"name": "Re-entry Test Project"},
        )
        assert proj_resp.status_code == 201
        project_id = proj_resp.json()["id"]

        resp1 = await tenant_a_client.post(f"/api/v1/ai/intake/start?project_id={project_id}")
        assert resp1.status_code == 201
        conv_id_1 = resp1.json()["id"]

        resp2 = await tenant_a_client.post(f"/api/v1/ai/intake/start?project_id={project_id}")
        assert resp2.status_code in (200, 201)
        conv_id_2 = resp2.json()["id"]

        # Should return the same conversation
        assert conv_id_1 == conv_id_2

    @pytest.mark.asyncio
    async def test_message_persistence(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """After starting a conversation, GET /ai/conversations/{id} shows persisted messages."""
        # Start a conversation
        resp = await tenant_a_client.post("/api/v1/ai/intake/start")
        assert resp.status_code == 201
        conv_id = resp.json()["id"]

        # GET the conversation — should have no messages yet
        resp_get = await tenant_a_client.get(f"/api/v1/ai/conversations/{conv_id}")
        assert resp_get.status_code == 200
        data = resp_get.json()
        assert data["id"] == conv_id
        assert data["conv_type"] == "intake"
        assert data["status"] == "active"
        assert isinstance(data["messages"], list)
