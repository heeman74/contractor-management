"""Authenticated, tenant-scoped serving of uploaded files.

Replaces the unauthenticated StaticFiles mounts (`/uploads`, `/files`,
`/uploads/chat`) that previously exposed every job-note attachment, image, and
chat file to anyone with the URL, cross-tenant.

Every request now requires a valid token (Bearer from mobile, or the httpOnly
access_token cookie forwarded as Bearer by the web /files route handler) AND
passes a tenant/membership check keyed on the URL's path shape:

- /files/attachments/{note_id}/{name}   -> an Attachment row with this exact
      remote_url must exist in the caller's company (RLS-scoped query).
- /files/images/{company_id}/{name}     -> the {company_id} path segment must
      equal the caller's company.
- /files/job_requests/{request_id}/{n}  -> the JobRequest must exist in the
      caller's company (RLS-scoped).
- /uploads/chat/{message_id}/{name}     -> the ChatMessage must exist (RLS) AND
      the caller must be a member of its thread.

Path traversal is blocked by resolving the final path and confirming it stays
within the uploads base directory. Files are served with
the global SecurityHeadersMiddleware's `X-Content-Type-Options: nosniff`, so a
mislabeled upload can't be sniffed into active content on the app origin.
"""

from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.chat.models import ChatMessage
from app.features.chat.service import ChatService
from app.features.jobs.models import Attachment, JobRequest

serve_router = APIRouter(tags=["files"], include_in_schema=False)

_UPLOADS_DIR = Path("uploads").resolve()
_CHAT_UPLOADS_DIR = (_UPLOADS_DIR / "chat").resolve()


def _safe_resolve(base: Path, relative: str) -> Path:
    """Resolve `relative` under `base`, rejecting traversal outside the base dir."""
    candidate = (base / relative).resolve()
    if base not in candidate.parents and candidate != base:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")
    return candidate


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File not found")


def _parse_uuid(value: str) -> uuid.UUID:
    try:
        return uuid.UUID(value)
    except ValueError as e:
        raise _not_found() from e


@serve_router.get("/files/{file_path:path}")
async def serve_upload(
    file_path: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FileResponse:
    """Serve an uploaded file after authenticating and tenant-scoping the request."""
    parts = file_path.split("/")
    category = parts[0] if parts else ""

    if category == "images":
        # images/{company_id}/{filename} — the caller may only read their company's images.
        if len(parts) < 3 or parts[1] != str(current_user.company_id):
            raise _not_found()
    elif category == "attachments":
        # attachments/{note_id}/{filename} — an Attachment row with this exact
        # remote_url must exist in the caller's company (RLS scopes the query).
        result = await db.execute(
            select(Attachment.id).where(Attachment.remote_url == f"/files/{file_path}").limit(1)
        )
        if result.scalars().first() is None:
            raise _not_found()
    elif category == "job_requests":
        # job_requests/{request_id}/{filename} — the JobRequest must be in the caller's company.
        if len(parts) < 3:
            raise _not_found()
        if await db.get(JobRequest, _parse_uuid(parts[1])) is None:
            raise _not_found()
    else:
        raise _not_found()

    target = _safe_resolve(_UPLOADS_DIR, file_path)
    if not target.is_file():
        raise _not_found()
    return FileResponse(target)


@serve_router.get("/uploads/chat/{file_path:path}")
async def serve_chat_upload(
    file_path: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FileResponse:
    """Serve a chat attachment after authenticating and checking thread membership."""
    parts = file_path.split("/")
    if len(parts) < 2:
        raise _not_found()

    # uploads/chat/{message_id}/{filename} — the message must exist (RLS scopes to
    # company) and the caller must be a member of its thread.
    message = await db.get(ChatMessage, _parse_uuid(parts[0]))
    if message is None:
        raise _not_found()
    if not await ChatService(db).is_member(message.thread_id, current_user.user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="You are not a member of this thread"
        )

    target = _safe_resolve(_CHAT_UPLOADS_DIR, file_path)
    if not target.is_file():
        raise _not_found()
    return FileResponse(target)
