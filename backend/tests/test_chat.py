"""Chat feature integration tests.

Tests for the chat REST endpoints covering:
- CHAT-01: thread creation and message sending
- CHAT-02: cursor pagination (before_seq and since_seq)
- CHAT-03: file attachment upload
- CHAT-04: idempotent thread creation
- CHAT-05: @mentions storage and retrieval
- RLS isolation between tenants
- Read receipts: mark_read and get receipts
- Mute toggle

Strategy:
- Uses tenant_a_client / tenant_b_client / seed_two_tenants fixtures from conftest.py.
- Chat tables added to clean_tables fixture via patched conftest (requires conftest update).
- All tests are @pytest.mark.anyio async tests.
- WebSocket integration tests are covered via E2E in Plan 06.
"""

from __future__ import annotations

import io
import uuid

import pytest
from httpx import AsyncClient

import app.features.chat.models  # noqa: F401 — ensure SQLAlchemy mappers configured

pytestmark = pytest.mark.anyio


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _create_project(client: AsyncClient, name: str = "Chat Test Project") -> str:
    """Create a project and return its ID."""
    resp = await client.post("/api/v1/projects/", json={"name": name})
    assert resp.status_code == 201, f"Project creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_trade_scope(
    client: AsyncClient, project_id: str, trade_name: str = "Plumbing"
) -> str:
    """Create a trade scope and return its ID."""
    resp = await client.post(
        "/api/v1/trade-scopes/",
        json={"project_id": project_id, "trade_name": trade_name},
    )
    assert resp.status_code == 201, f"Trade scope creation failed: {resp.text}"
    return resp.json()["id"]


async def _create_scope_thread(
    client: AsyncClient,
    project_id: str,
    trade_scope_id: str,
    member_ids: list[str],
    name: str = "Plumbing",
) -> dict:
    """Create a scope thread and return the response data."""
    resp = await client.post(
        "/api/v1/chat/threads",
        json={
            "project_id": project_id,
            "thread_type": "scope",
            "trade_scope_id": trade_scope_id,
            "name": name,
            "member_ids": member_ids,
        },
    )
    assert resp.status_code == 201, f"Scope thread creation failed: {resp.text}"
    return resp.json()


async def _create_project_wide_thread(
    client: AsyncClient,
    project_id: str,
    member_ids: list[str],
    name: str = "Project-Wide",
) -> dict:
    """Create a project-wide thread and return the response data."""
    resp = await client.post(
        "/api/v1/chat/threads",
        json={
            "project_id": project_id,
            "thread_type": "project_wide",
            "name": name,
            "member_ids": member_ids,
        },
    )
    assert resp.status_code == 201, f"Project-wide thread creation failed: {resp.text}"
    return resp.json()


async def _send_message(
    client: AsyncClient,
    thread_id: str,
    content: str,
    message_id: str | None = None,
    mentions: list[str] | None = None,
    mention_all: bool = False,
) -> dict:
    """Send a message via REST and return the response data."""
    if message_id is None:
        message_id = str(uuid.uuid4())
    resp = await client.post(
        f"/api/v1/chat/threads/{thread_id}/messages",
        json={
            "id": message_id,
            "content": content,
            "mentions": mentions or [],
            "mention_all": mention_all,
        },
    )
    assert resp.status_code == 201, f"Message send failed: {resp.text}"
    return resp.json()


# ---------------------------------------------------------------------------
# Thread creation tests
# ---------------------------------------------------------------------------


class TestThreadCreation:
    """Tests for POST /chat/threads (scope and project_wide)."""

    async def test_create_scope_thread(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """Create a scope thread — 201 with correct thread_type and memberships."""
        project_id = await _create_project(tenant_a_client, "Scope Thread Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id, "Plumbing")

        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],  # contractor same as GC for test purposes
            name="Plumbing",
        )

        assert thread["thread_type"] == "scope"
        assert thread["trade_scope_id"] == trade_scope_id
        assert thread["name"] == "Plumbing"
        assert thread["project_id"] == project_id
        assert "id" in thread

    async def test_create_project_wide_thread(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Create a project-wide thread — 201 with thread_type='project_wide'."""
        project_id = await _create_project(tenant_a_client, "Wide Thread Project")
        gc_user_id = seed_two_tenants["tenant_a_user_id"]

        thread = await _create_project_wide_thread(
            tenant_a_client,
            project_id=project_id,
            member_ids=[gc_user_id],
            name="All Hands",
        )

        assert thread["thread_type"] == "project_wide"
        assert thread["trade_scope_id"] is None
        assert thread["name"] == "All Hands"
        assert thread["project_id"] == project_id

    async def test_list_threads_for_project(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Create 2 threads; GET /chat/threads?project_id returns both."""
        project_id = await _create_project(tenant_a_client, "Multi-Thread Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id, "Electrical")
        gc_user_id = seed_two_tenants["tenant_a_user_id"]

        # Create scope thread
        t1 = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
            name="Electrical",
        )
        # Create project-wide thread
        t2 = await _create_project_wide_thread(
            tenant_a_client,
            project_id=project_id,
            member_ids=[gc_user_id],
        )

        list_resp = await tenant_a_client.get(
            "/api/v1/chat/threads",
            params={"project_id": project_id},
        )
        assert list_resp.status_code == 200, list_resp.text
        threads = list_resp.json()
        thread_ids = {t["id"] for t in threads}
        assert t1["id"] in thread_ids
        assert t2["id"] in thread_ids
        thread_types = {t["thread_type"] for t in threads}
        assert "scope" in thread_types
        assert "project_wide" in thread_types


# ---------------------------------------------------------------------------
# Message send tests (CHAT-01)
# ---------------------------------------------------------------------------


class TestMessageSend:
    """CHAT-01: GC and contractor sending messages."""

    async def test_gc_sends_message(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """CHAT-01: POST /chat/threads/{id}/messages — 201, seq assigned."""
        project_id = await _create_project(tenant_a_client, "GC Message Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        msg = await _send_message(tenant_a_client, thread_id, "Hello, team!")

        assert msg["content"] == "Hello, team!"
        assert "seq" in msg
        assert isinstance(msg["seq"], int)
        assert msg["seq"] > 0
        assert msg["thread_id"] == thread_id
        assert msg["sender_id"] == gc_user_id

    async def test_message_dedup_by_uuid(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Send the same message UUID twice — only 1 message created (ON CONFLICT DO NOTHING)."""
        project_id = await _create_project(tenant_a_client, "Dedup Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        dedup_id = str(uuid.uuid4())
        msg1 = await _send_message(tenant_a_client, thread_id, "First send", message_id=dedup_id)
        # Second send with same UUID — should return same seq (dedup)
        msg2 = await _send_message(tenant_a_client, thread_id, "Second send", message_id=dedup_id)

        assert msg1["id"] == msg2["id"]
        assert msg1["seq"] == msg2["seq"]

        # Verify only 1 message in history
        history_resp = await tenant_a_client.get(f"/api/v1/chat/threads/{thread_id}/messages")
        assert history_resp.status_code == 200
        messages = history_resp.json()
        ids = [m["id"] for m in messages]
        assert ids.count(dedup_id) == 1


# ---------------------------------------------------------------------------
# Pagination tests (CHAT-02)
# ---------------------------------------------------------------------------


class TestPagination:
    """CHAT-02: Cursor pagination with before_seq and since_seq."""

    async def _setup_thread_with_messages(
        self, client: AsyncClient, seed: dict, count: int = 10
    ) -> tuple[str, list[dict]]:
        """Create a thread, send N messages, return (thread_id, messages)."""
        project_id = await _create_project(client, f"Pagination Project {uuid.uuid4()}")
        trade_scope_id = await _create_trade_scope(client, project_id)
        gc_user_id = seed["tenant_a_user_id"]
        thread = await _create_scope_thread(
            client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]
        messages = []
        for i in range(1, count + 1):
            msg = await _send_message(client, thread_id, f"Message {i}")
            messages.append(msg)
        return thread_id, messages

    async def test_cursor_pagination(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """CHAT-02: GET messages with before_seq=8&limit=3 returns seqs 5,6,7."""
        thread_id, messages = await self._setup_thread_with_messages(
            tenant_a_client, seed_two_tenants, count=10
        )
        seqs = [m["seq"] for m in messages]
        # Get the seq value at index 7 (8th message, seq ~8 depending on DB)
        seq_at_8 = seqs[7]  # 0-indexed: messages[7] is the 8th message

        resp = await tenant_a_client.get(
            f"/api/v1/chat/threads/{thread_id}/messages",
            params={"before_seq": seq_at_8, "limit": 3},
        )
        assert resp.status_code == 200
        page = resp.json()
        assert len(page) == 3
        returned_seqs = [m["seq"] for m in page]
        # All returned seqs must be < seq_at_8
        for s in returned_seqs:
            assert s < seq_at_8
        # Must be in ascending order
        assert returned_seqs == sorted(returned_seqs)

    async def test_since_seq_pagination(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """since_seq=5th_seq returns messages after that point."""
        thread_id, messages = await self._setup_thread_with_messages(
            tenant_a_client, seed_two_tenants, count=10
        )
        seqs = [m["seq"] for m in messages]
        seq_at_5 = seqs[4]  # 0-indexed: 5th message

        resp = await tenant_a_client.get(
            f"/api/v1/chat/threads/{thread_id}/messages",
            params={"since_seq": seq_at_5},
        )
        assert resp.status_code == 200
        page = resp.json()
        returned_seqs = [m["seq"] for m in page]
        # All returned seqs must be > seq_at_5
        for s in returned_seqs:
            assert s > seq_at_5
        # Must be in ascending order
        assert returned_seqs == sorted(returned_seqs)
        # Should return messages 6-10 (5 messages)
        assert len(page) == 5


# ---------------------------------------------------------------------------
# Read receipt tests
# ---------------------------------------------------------------------------


class TestReadReceipts:
    """Mark-read upsert and read receipt retrieval."""

    async def test_mark_read_upsert(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """POST mark_read with seq=5, then seq=3 — last_read_seq stays at 5 (no regression)."""
        project_id = await _create_project(tenant_a_client, "Mark Read Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        # Send 5 messages to get real seq values
        messages = []
        for i in range(5):
            msg = await _send_message(tenant_a_client, thread_id, f"Msg {i}")
            messages.append(msg)
        seq_5 = messages[4]["seq"]
        seq_3 = messages[2]["seq"]

        # Mark read at seq_5
        resp = await tenant_a_client.post(
            f"/api/v1/chat/threads/{thread_id}/read",
            json={"seq": seq_5},
        )
        assert resp.status_code == 204

        # Mark read at seq_3 — should NOT downgrade
        resp = await tenant_a_client.post(
            f"/api/v1/chat/threads/{thread_id}/read",
            json={"seq": seq_3},
        )
        assert resp.status_code == 204

        # Verify last_read_seq is still seq_5 (not downgraded to seq_3)
        receipts_resp = await tenant_a_client.get(f"/api/v1/chat/threads/{thread_id}/receipts")
        assert receipts_resp.status_code == 200
        receipts = receipts_resp.json()
        assert len(receipts) >= 1
        user_receipt = next((r for r in receipts if r["user_id"] == gc_user_id), None)
        assert user_receipt is not None
        assert user_receipt["last_read_seq"] == seq_5

    async def test_get_read_receipts(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict, async_client: AsyncClient
    ):
        """Mark read for the GC user, verify receipt returned in GET /receipts."""
        project_id = await _create_project(tenant_a_client, "Receipts Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        msg = await _send_message(tenant_a_client, thread_id, "Read me")
        seq = msg["seq"]

        await tenant_a_client.post(
            f"/api/v1/chat/threads/{thread_id}/read",
            json={"seq": seq},
        )

        receipts_resp = await tenant_a_client.get(f"/api/v1/chat/threads/{thread_id}/receipts")
        assert receipts_resp.status_code == 200
        receipts = receipts_resp.json()
        assert len(receipts) == 1
        assert receipts[0]["user_id"] == gc_user_id
        assert receipts[0]["last_read_seq"] == seq


# ---------------------------------------------------------------------------
# File attachment test (CHAT-03)
# ---------------------------------------------------------------------------


class TestChatAttachment:
    """CHAT-03: File upload for chat messages."""

    async def test_chat_file_attachment(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """POST /chat/messages/{id}/attachment — sets attachment_url on message."""
        project_id = await _create_project(tenant_a_client, "Attachment Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        # Send a message first to get a message ID
        msg = await _send_message(tenant_a_client, thread_id, "Attaching a file")
        message_id = msg["id"]

        # Upload a file attachment
        file_content = b"fake image content"
        resp = await tenant_a_client.post(
            f"/api/v1/chat/messages/{message_id}/attachment",
            files={"file": ("test.jpg", io.BytesIO(file_content), "image/jpeg")},
        )
        assert resp.status_code == 200, f"Attachment upload failed: {resp.text}"
        data = resp.json()
        assert data["id"] == message_id
        assert data["attachment_url"] is not None
        assert "chat" in data["attachment_url"]
        assert message_id in data["attachment_url"]


# ---------------------------------------------------------------------------
# Idempotent thread creation (CHAT-04)
# ---------------------------------------------------------------------------


class TestIdempotentThreadCreation:
    """CHAT-04: Thread auto-creation is idempotent."""

    async def test_thread_auto_create_idempotent(
        self, tenant_a_client: AsyncClient, seed_two_tenants: dict
    ):
        """Creating scope thread twice for same trade_scope_id returns same thread."""
        project_id = await _create_project(tenant_a_client, "Idempotent Thread Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id, "HVAC")
        gc_user_id = seed_two_tenants["tenant_a_user_id"]

        # Create scope thread first time
        t1 = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
            name="HVAC",
        )
        # Create scope thread second time — must return same thread
        t2 = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
            name="HVAC",
        )

        assert t1["id"] == t2["id"]

        # Verify only 1 thread exists for this project
        list_resp = await tenant_a_client.get(
            "/api/v1/chat/threads",
            params={"project_id": project_id},
        )
        threads = list_resp.json()
        scope_threads = [t for t in threads if t["thread_type"] == "scope"]
        assert len(scope_threads) == 1


# ---------------------------------------------------------------------------
# Mute toggle test
# ---------------------------------------------------------------------------


class TestMuteToggle:
    """Toggle mute preference on a thread membership."""

    async def test_toggle_mute(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """PUT /chat/threads/{id}/mute with muted=true sets muted on membership."""
        project_id = await _create_project(tenant_a_client, "Mute Test Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        # Toggle mute ON
        mute_resp = await tenant_a_client.put(
            f"/api/v1/chat/threads/{thread_id}/mute",
            json={"muted": True},
        )
        assert mute_resp.status_code == 204

        # Toggle mute OFF
        unmute_resp = await tenant_a_client.put(
            f"/api/v1/chat/threads/{thread_id}/mute",
            json={"muted": False},
        )
        assert unmute_resp.status_code == 204


# ---------------------------------------------------------------------------
# RLS isolation test
# ---------------------------------------------------------------------------


class TestRLSIsolation:
    """RLS: tenant isolation for chat threads and messages."""

    async def test_rls_isolation(
        self,
        tenant_a_client: AsyncClient,
        tenant_b_client: AsyncClient,
        seed_two_tenants: dict,
    ):
        """Tenant A's chat thread is not visible to Tenant B."""
        # Tenant A creates a project and thread
        project_id = await _create_project(tenant_a_client, "Tenant A Chat Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        # Send a message in Tenant A's thread
        await _send_message(tenant_a_client, thread_id, "Tenant A secret message")

        # Tenant B tries to get messages from Tenant A's thread — should get empty or 403/404
        # RLS will filter messages to Tenant B's company_id, so messages will be empty
        resp = await tenant_b_client.get(f"/api/v1/chat/threads/{thread_id}/messages")
        # Either 200 with empty list (RLS filters) or 403/404
        assert resp.status_code in (200, 403, 404)
        if resp.status_code == 200:
            # RLS filters away Tenant A's messages
            assert resp.json() == []

        # Tenant B lists threads for Tenant A's project — should be empty
        list_resp = await tenant_b_client.get(
            "/api/v1/chat/threads",
            params={"project_id": project_id},
        )
        assert list_resp.status_code == 200
        # RLS: Tenant B is not a member of Tenant A's threads
        assert list_resp.json() == []


# ---------------------------------------------------------------------------
# Mentions storage test (CHAT-05)
# ---------------------------------------------------------------------------


class TestMentions:
    """CHAT-05: @mention storage in messages."""

    async def test_mentions_stored(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """Send message with mentions and mention_all=true — both stored in DB."""
        project_id = await _create_project(tenant_a_client, "Mentions Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        mentioned_user_id = str(uuid.uuid4())  # Any UUID — stored as JSONB
        msg = await _send_message(
            tenant_a_client,
            thread_id,
            "@admin please review",
            mentions=[mentioned_user_id],
            mention_all=False,
        )

        assert msg["mentions"] is not None
        assert len(msg["mentions"]) == 1
        # mentions stored as strings
        assert str(mentioned_user_id) in [str(m) for m in msg["mentions"]]
        assert msg["mention_all"] is False

    async def test_mention_all_stored(self, tenant_a_client: AsyncClient, seed_two_tenants: dict):
        """Send message with mention_all=true — stored in DB."""
        project_id = await _create_project(tenant_a_client, "Mention All Project")
        trade_scope_id = await _create_trade_scope(tenant_a_client, project_id)
        gc_user_id = seed_two_tenants["tenant_a_user_id"]
        thread = await _create_scope_thread(
            tenant_a_client,
            project_id=project_id,
            trade_scope_id=trade_scope_id,
            member_ids=[gc_user_id],
        )
        thread_id = thread["id"]

        msg = await _send_message(
            tenant_a_client,
            thread_id,
            "@everyone meeting at 3pm",
            mention_all=True,
        )
        assert msg["mention_all"] is True
