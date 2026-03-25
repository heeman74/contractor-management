"""Chat feature router — WebSocket endpoint and REST endpoints.

WebSocket endpoint:
  WS /ws/chat/{thread_id}?token={jwt}
    - JWT validated BEFORE websocket.accept() — close 4401 if invalid/expired
    - Re-validates every 5 minutes (STATE.md decision)
    - Message types: message, typing, read, ping
    - Broadcasts via Redis pub/sub (ConnectionManager)
    - Fires FCM for offline recipients on new messages

REST endpoints (all require Bearer auth):
  GET  /chat/threads?project_id={id}        — list threads for user on project
  POST /chat/threads                         — create a thread
  GET  /chat/threads/{id}/messages           — cursor-paginated messages
  POST /chat/threads/{id}/messages           — REST fallback send message
  POST /chat/threads/{id}/read              — mark read
  GET  /chat/threads/{id}/receipts          — read receipts
  POST /chat/messages/{id}/attachment        — file upload for chat message
  PUT  /chat/threads/{id}/mute              — toggle mute

Design notes:
- JWT in query param for WebSocket (browser WS API cannot send headers).
- Connection manager is the module-level singleton from ws_manager.py.
- FCM fired fire-and-forget — never blocks the message send path.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from pathlib import Path

import aiofiles
from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, decode_token, get_current_user
from app.core.tenant import set_current_tenant_id
from app.features.chat.schemas import (
    ChatMessageResponse,
    ChatReadReceiptResponse,
    ChatThreadResponse,
    MarkReadRequest,
    SendMessageRequest,
    ToggleMuteRequest,
)
from app.features.chat.service import ChatService
from app.features.chat.ws_manager import manager
from app.features.notifications.service import NotificationService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["chat"])

# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------

_WS_JWT_REVALIDATE_INTERVAL = 300  # seconds (5 minutes per STATE.md decision)
_WS_RECEIVE_TIMEOUT = 30.0  # seconds


def _is_valid_uuid(val: str) -> bool:
    """Check if a string is a valid UUID without raising."""
    try:
        uuid.UUID(val)
        return True
    except (ValueError, AttributeError):
        return False


# ------------------------------------------------------------------
# Helper: build ChatMessageResponse from ORM model
# ------------------------------------------------------------------


def _message_to_response(message) -> ChatMessageResponse:
    """Convert a ChatMessage ORM object to ChatMessageResponse schema."""
    return ChatMessageResponse(
        id=message.id,
        company_id=message.company_id,
        version=message.version,
        created_at=message.created_at,
        updated_at=message.updated_at,
        thread_id=message.thread_id,
        sender_id=message.sender_id,
        sender_name="",  # caller resolves name if needed
        content=message.content,
        seq=message.seq,
        attachment_url=message.attachment_url,
        attachment_type=message.attachment_type,
        annotation_data=message.annotation_data,
        mentions=message.mentions or [],
        mention_all=message.mention_all,
    )


# ------------------------------------------------------------------
# WebSocket endpoint
# ------------------------------------------------------------------


@router.websocket("/ws/chat/{thread_id}")
async def websocket_chat(
    websocket: WebSocket,
    thread_id: uuid.UUID,
    token: str = Query(..., description="JWT access token (WS cannot send headers)"),
    db: AsyncSession = Depends(get_db),
) -> None:
    """WebSocket endpoint for real-time chat messages.

    Auth flow:
    1. Validate JWT BEFORE websocket.accept() — close 4401 if invalid
    2. Verify user is a member of the thread — close 4403 if not
    3. Accept the connection and register with ConnectionManager
    4. Start Redis relay task (managed by ConnectionManager)
    5. Enter message loop with 5-minute JWT re-validation
    6. On disconnect: clean up connection + relay task

    Message protocol (incoming JSON):
    - {"type": "message", "id": "<uuid>", "content": "...", ...} — send message
    - {"type": "typing"} — broadcast typing indicator
    - {"type": "read", "seq": N} — mark read up to seq N
    - {"type": "ping"} — keepalive; server responds {"type": "pong"}

    WebSocket close codes:
    - 4401: JWT invalid, expired, or re-validation failed
    - 4403: user is not a member of the requested thread
    """
    # ----------------------------------------------------------------
    # Step 1: Validate JWT BEFORE accept()
    # ----------------------------------------------------------------
    payload = decode_token(token)
    if payload is None or payload.get("type") != "access":
        await websocket.close(code=4401)
        return

    try:
        user_id = uuid.UUID(payload["sub"])
        company_id = uuid.UUID(payload["company_id"])
    except (KeyError, ValueError):
        await websocket.close(code=4401)
        return

    # ----------------------------------------------------------------
    # Step 2: Set RLS tenant context for DB operations
    # ----------------------------------------------------------------
    set_current_tenant_id(company_id)

    # ----------------------------------------------------------------
    # Step 3: Verify thread membership
    # ----------------------------------------------------------------
    from sqlalchemy import select

    from app.features.chat.models import ChatMembership

    chat_service = ChatService(db)
    membership_result = await db.execute(
        select(ChatMembership).where(
            ChatMembership.thread_id == thread_id,
            ChatMembership.user_id == user_id,
        )
    )
    membership = membership_result.scalars().first()
    if membership is None:
        await websocket.close(code=4403)
        return

    # ----------------------------------------------------------------
    # Step 4: Accept the connection and register with ConnectionManager
    # ----------------------------------------------------------------
    await manager.connect(websocket, str(thread_id), str(user_id))

    # ----------------------------------------------------------------
    # Step 5: Message loop with JWT re-validation every 5 minutes
    # ----------------------------------------------------------------
    last_validated = asyncio.get_event_loop().time()
    try:
        while True:
            # JWT re-validation check
            now = asyncio.get_event_loop().time()
            if now - last_validated > _WS_JWT_REVALIDATE_INTERVAL:
                revalidated = decode_token(token)
                if revalidated is None or revalidated.get("type") != "access":
                    logger.info(
                        "WebSocket JWT expired — closing thread=%s user=%s", thread_id, user_id
                    )
                    await websocket.close(code=4401)
                    break
                last_validated = now

            try:
                data = await asyncio.wait_for(websocket.receive_json(), timeout=_WS_RECEIVE_TIMEOUT)
            except TimeoutError:
                # Timeout on receive — loop back to check JWT
                continue
            except WebSocketDisconnect:
                break

            msg_type = data.get("type")

            if msg_type == "ping":
                await websocket.send_json({"type": "pong"})

            elif msg_type == "typing":
                await manager.broadcast_to_thread(
                    str(thread_id),
                    {"type": "typing", "user_id": str(user_id)},
                )

            elif msg_type == "read":
                seq = data.get("seq")
                if isinstance(seq, int):
                    await chat_service.mark_read(
                        thread_id=thread_id,
                        user_id=user_id,
                        company_id=company_id,
                        seq=seq,
                    )
                    await manager.broadcast_to_thread(
                        str(thread_id),
                        {"type": "read_receipt", "user_id": str(user_id), "seq": seq},
                    )

            elif msg_type == "message":
                message_uuid = data.get("id")
                if not message_uuid:
                    continue

                try:
                    msg_id = uuid.UUID(message_uuid)
                except ValueError:
                    continue

                message = await chat_service.send_message(
                    thread_id=thread_id,
                    sender_id=user_id,
                    company_id=company_id,
                    message_id=msg_id,
                    content=data.get("content"),
                    attachment_url=data.get("attachment_url"),
                    attachment_type=data.get("attachment_type"),
                    annotation_data=data.get("annotation_data"),
                    mentions=[
                        uuid.UUID(m) for m in data.get("mentions", []) if m and _is_valid_uuid(m)
                    ],
                    mention_all=bool(data.get("mention_all", False)),
                )

                if message is not None:
                    # Broadcast message to all connected thread members
                    broadcast_payload = {
                        "type": "message",
                        "id": str(message.id),
                        "thread_id": str(thread_id),
                        "sender_id": str(user_id),
                        "content": message.content,
                        "seq": message.seq,
                        "attachment_url": message.attachment_url,
                        "attachment_type": message.attachment_type,
                        "annotation_data": message.annotation_data,
                        "mentions": message.mentions or [],
                        "mention_all": message.mention_all,
                        "created_at": message.created_at.isoformat()
                        if message.created_at
                        else None,
                    }
                    await manager.broadcast_to_thread(str(thread_id), broadcast_payload)

                    # Fire FCM for offline recipients (fire-and-forget)
                    # Pass primitive data — task creates its own DB session
                    asyncio.create_task(
                        _fire_chat_fcm(
                            thread_id=thread_id,
                            user_id=user_id,
                            company_id=company_id,
                            message_content=message.content,
                            message_mentions=message.mentions,
                            message_mention_all=message.mention_all,
                            thread_id_str=str(thread_id),
                        )
                    )

    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("WebSocket error: thread=%s user=%s", thread_id, user_id)
    finally:
        await manager.disconnect(websocket, str(thread_id), str(user_id))


async def _fire_chat_fcm(
    thread_id: uuid.UUID,
    user_id: uuid.UUID,
    company_id: uuid.UUID,
    message_content: str | None,
    message_mentions: list | None,
    message_mention_all: bool,
    thread_id_str: str,
) -> None:
    """Fire FCM notifications for offline recipients of a chat message.

    Called as fire-and-forget asyncio.create_task(). Never raises.
    Creates its own database session to avoid using the WebSocket handler's
    session which may be closed by the time this task executes.
    """
    try:
        from sqlalchemy import select

        from app.core.database import async_session_factory
        from app.core.tenant import set_current_tenant_id
        from app.features.chat.models import ChatMembership

        set_current_tenant_id(company_id)

        async with async_session_factory() as db:
            # Load all thread memberships to find recipients
            memberships_result = await db.execute(
                select(ChatMembership).where(ChatMembership.thread_id == thread_id)
            )
            memberships = memberships_result.scalars().all()

            # Connected user IDs on this worker for this thread
            connected = set(manager._connections.get(thread_id_str, {}).keys())

            # Recipients: members who are NOT the sender AND are not currently connected
            offline_recipients = [
                m.user_id
                for m in memberships
                if str(m.user_id) not in connected and m.user_id != user_id
            ]
            muted_recipients = [m.user_id for m in memberships if m.muted]

            if not offline_recipients:
                return

            # Determine mentioned user IDs
            import contextlib

            mention_uuids: list[uuid.UUID] = []
            if message_mentions:
                for m_id in message_mentions:
                    with contextlib.suppress(ValueError):
                        mention_uuids.append(uuid.UUID(str(m_id)))

            notif_service = NotificationService(db)
            await notif_service.send_chat_notification(
                thread_id=thread_id,
                sender_name=str(user_id),
                trade_scope_name=None,
                message_preview=(message_content or "")[:100],
                recipient_user_ids=offline_recipients,
                mention_all=message_mention_all,
                mentioned_user_ids=mention_uuids,
                muted_user_ids=muted_recipients,
            )
    except Exception:  # noqa: BLE001
        logger.exception("FCM fire-and-forget failed for thread %s", thread_id)


# ------------------------------------------------------------------
# REST endpoints
# ------------------------------------------------------------------


@router.get(
    "/chat/threads",
    response_model=list[ChatThreadResponse],
)
async def list_threads(
    project_id: uuid.UUID = Query(..., description="Filter threads by project"),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ChatThreadResponse]:
    """List all chat threads the current user belongs to within a project.

    Returns threads ordered by most recently active (updated_at DESC).
    """
    chat_service = ChatService(db)
    threads = await chat_service.list_threads_for_user(
        project_id=project_id,
        user_id=current_user.user_id,
    )

    result = []
    for thread in threads:
        result.append(
            ChatThreadResponse(
                id=thread.id,
                company_id=thread.company_id,
                version=thread.version,
                created_at=thread.created_at,
                updated_at=thread.updated_at,
                project_id=thread.project_id,
                thread_type=thread.thread_type,
                trade_scope_id=thread.trade_scope_id,
                name=thread.name,
                member_count=len(thread.memberships),
            )
        )
    return result


@router.post(
    "/chat/threads",
    response_model=ChatThreadResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_thread(
    body: dict,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ChatThreadResponse:
    """Create a chat thread (scope or project_wide).

    Body fields:
    - project_id: UUID
    - thread_type: 'scope' or 'project_wide'
    - name: display name
    - member_ids: list of user UUIDs to add as members
    - trade_scope_id: UUID (required for scope threads)
    """
    try:
        project_id = uuid.UUID(str(body["project_id"]))
    except (KeyError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="project_id is required and must be a valid UUID",
        ) from exc
    thread_type = body.get("thread_type", "project_wide")
    name = body.get("name", "")
    try:
        member_ids = [uuid.UUID(str(m)) for m in body.get("member_ids", [])]
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="member_ids must be valid UUIDs",
        ) from exc
    trade_scope_id = body.get("trade_scope_id")

    chat_service = ChatService(db)

    if thread_type == "scope":
        if not trade_scope_id or not member_ids:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="trade_scope_id and member_ids required for scope threads",
            )
        trade_scope_uuid = uuid.UUID(str(trade_scope_id))
        # For scope threads: first member_id is contractor, second is GC (or current user)
        contractor_id = member_ids[0]
        gc_user_id = member_ids[1] if len(member_ids) > 1 else current_user.user_id
        thread = await chat_service.create_scope_thread(
            project_id=project_id,
            trade_scope_id=trade_scope_uuid,
            trade_name=name,
            contractor_id=contractor_id,
            gc_user_id=gc_user_id,
            company_id=current_user.company_id,
        )
    else:
        # project_wide: include current user + all member_ids
        all_members = list({current_user.user_id, *member_ids})
        thread = await chat_service.create_project_wide_thread(
            project_id=project_id,
            project_name=name or "Project-Wide",
            member_user_ids=all_members,
            company_id=current_user.company_id,
        )

    # Re-fetch memberships for member_count
    from sqlalchemy import select

    from app.features.chat.models import ChatMembership

    memberships_result = await db.execute(
        select(ChatMembership).where(ChatMembership.thread_id == thread.id)
    )
    member_count = len(memberships_result.scalars().all())

    return ChatThreadResponse(
        id=thread.id,
        company_id=thread.company_id,
        version=thread.version,
        created_at=thread.created_at,
        updated_at=thread.updated_at,
        project_id=thread.project_id,
        thread_type=thread.thread_type,
        trade_scope_id=thread.trade_scope_id,
        name=thread.name,
        member_count=member_count,
    )


@router.get(
    "/chat/threads/{thread_id}/messages",
    response_model=list[ChatMessageResponse],
)
async def get_messages(
    thread_id: uuid.UUID,
    before_seq: int | None = Query(None, description="Fetch messages with seq < this value"),
    since_seq: int | None = Query(
        None, description="Fetch messages with seq > this value (reconnect catch-up)"
    ),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ChatMessageResponse]:
    """Return paginated messages for a thread.

    Cursor pagination:
    - before_seq: returns older messages (scroll-up history load)
    - since_seq: returns newer messages (reconnect catch-up)
    Both are mutually exclusive; before_seq takes precedence.

    RLS ensures the current user can only access threads in their company.
    Membership check is implicit via RLS (chat_messages.company_id).
    """
    chat_service = ChatService(db)

    if since_seq is not None and before_seq is None:
        # Reconnect catch-up: get messages since_seq
        messages = await chat_service.message_repo.list_by_thread(
            thread_id=thread_id,
            since_seq=since_seq,
            limit=limit,
        )
    else:
        messages = await chat_service.get_messages(
            thread_id=thread_id,
            before_seq=before_seq,
            limit=limit,
        )

    return [_message_to_response(m) for m in messages]


@router.post(
    "/chat/threads/{thread_id}/messages",
    response_model=ChatMessageResponse,
    status_code=status.HTTP_201_CREATED,
)
async def send_message_rest(
    thread_id: uuid.UUID,
    body: SendMessageRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ChatMessageResponse:
    """REST fallback for sending a message (offline sync drain).

    Idempotent via client-generated UUID in body.id.
    Returns the message (or existing message if UUID already in DB).
    """
    chat_service = ChatService(db)
    message = await chat_service.send_message(
        thread_id=thread_id,
        sender_id=current_user.user_id,
        company_id=current_user.company_id,
        message_id=body.id,
        content=body.content,
        attachment_url=body.attachment_url,
        attachment_type=body.attachment_type,
        annotation_data=body.annotation_data,
        mentions=body.mentions,
        mention_all=body.mention_all,
    )

    if message is None:
        # Duplicate — return the existing message
        from sqlalchemy import select

        from app.features.chat.models import ChatMessage

        result = await db.execute(select(ChatMessage).where(ChatMessage.id == body.id))
        message = result.scalars().first()
        if message is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")
    else:
        # Broadcast via Redis so connected clients see the message
        broadcast_payload = {
            "type": "message",
            "id": str(message.id),
            "thread_id": str(thread_id),
            "sender_id": str(current_user.user_id),
            "content": message.content,
            "seq": message.seq,
            "attachment_url": message.attachment_url,
            "attachment_type": message.attachment_type,
            "annotation_data": message.annotation_data,
            "mentions": message.mentions or [],
            "mention_all": message.mention_all,
            "created_at": message.created_at.isoformat() if message.created_at else None,
        }
        asyncio.create_task(manager.broadcast_to_thread(str(thread_id), broadcast_payload))

    return _message_to_response(message)


@router.post(
    "/chat/threads/{thread_id}/read",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def mark_read(
    thread_id: uuid.UUID,
    body: MarkReadRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Mark all messages up to seq as read for the current user."""
    chat_service = ChatService(db)
    await chat_service.mark_read(
        thread_id=thread_id,
        user_id=current_user.user_id,
        company_id=current_user.company_id,
        seq=body.seq,
    )


@router.get(
    "/chat/threads/{thread_id}/receipts",
    response_model=list[ChatReadReceiptResponse],
)
async def get_read_receipts(
    thread_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[ChatReadReceiptResponse]:
    """Return all read receipt positions for a thread (for "seen by" display)."""
    chat_service = ChatService(db)
    receipts = await chat_service.get_read_receipts(thread_id=thread_id)
    return [
        ChatReadReceiptResponse(
            id=r.id,
            version=r.version,
            created_at=r.created_at,
            updated_at=r.updated_at,
            thread_id=r.thread_id,
            user_id=r.user_id,
            user_name="",
            last_read_seq=r.last_read_seq,
            read_at=r.read_at,
        )
        for r in receipts
    ]


@router.post(
    "/chat/messages/{message_id}/attachment",
    response_model=ChatMessageResponse,
    status_code=status.HTTP_200_OK,
)
async def upload_chat_attachment(
    message_id: uuid.UUID,
    file: UploadFile,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ChatMessageResponse:
    """Upload a file attachment for an existing chat message.

    Saves the file to uploads/chat/{message_id}/{filename}.
    Updates message.attachment_url with the path.
    The file is served via the /uploads/chat static mount in main.py.
    """
    from sqlalchemy import select

    from app.features.chat.models import ChatMessage

    # Fetch the existing message (RLS ensures company scope)
    result = await db.execute(
        select(ChatMessage).where(
            ChatMessage.id == message_id,
        )
    )
    message = result.scalars().first()
    if message is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Message {message_id} not found",
        )

    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No file provided.",
        )

    # Read and validate file size (max 10 MB)
    content = await file.read()
    max_attachment_size = 10 * 1024 * 1024  # 10 MB
    if len(content) > max_attachment_size:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large. Maximum size is 10 MB.",
        )

    # Save file to uploads/chat/{message_id}/{filename}
    original_suffix = Path(file.filename).suffix.lower() or ".bin"
    unique_filename = f"{uuid.uuid4()}{original_suffix}"
    upload_dir = Path("uploads") / "chat" / str(message_id)
    upload_dir.mkdir(parents=True, exist_ok=True)
    dest_path = upload_dir / unique_filename
    async with aiofiles.open(dest_path, "wb") as f:
        await f.write(content)

    # Update message attachment_url
    attachment_url = f"/uploads/chat/{message_id}/{unique_filename}"
    message.attachment_url = attachment_url
    await db.flush()
    await db.refresh(message)

    return _message_to_response(message)


@router.put(
    "/chat/threads/{thread_id}/mute",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def toggle_mute(
    thread_id: uuid.UUID,
    body: ToggleMuteRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Toggle the muted notification preference for the current user in a thread."""
    chat_service = ChatService(db)
    result = await chat_service.toggle_mute(
        thread_id=thread_id,
        user_id=current_user.user_id,
        muted=body.muted,
    )
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Membership not found — user is not a member of this thread",
        )
