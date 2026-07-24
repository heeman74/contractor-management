"""Files feature router — file upload endpoint for job note attachments.

Endpoints:
  POST /files/upload  — Upload a file attachment linked to a job note (auth required).

File storage:
  Files are saved to: uploads/attachments/{note_id}/{uuid}{ext}
  The remote_url stored in the Attachment record is: /files/attachments/{note_id}/{filename}
  This path is served by the StaticFiles mount in main.py:
    app.mount("/files", StaticFiles(directory="uploads"), name="files")

Design notes:
- Uses aiofiles for async writes (same pattern as job request photo uploads in jobs/router.py).
- Creates uploads/attachments/{note_id}/ directory on first upload to that note.
- Returns 201 with AttachmentResponse on success.
- Raises 404 if note_id refers to a non-existent note.
- attachment_type must be 'photo', 'pdf', or 'drawing' — validated at Pydantic level.
"""

from __future__ import annotations

import uuid
from pathlib import Path
from typing import Annotated

import aiofiles
from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import entity_or_404
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.features.files.schemas import ImageUploadResponse
from app.features.jobs.models import Attachment, JobNote
from app.features.jobs.schemas import AttachmentResponse

router = APIRouter(tags=["files"])

_ALLOWED_ATTACHMENT_TYPES = frozenset({"photo", "pdf", "drawing"})
_ALLOWED_IMAGE_TYPES = frozenset(
    {"image/jpeg", "image/png", "image/heic", "image/heif", "image/webp"}
)
_MAX_UPLOAD_BYTES = 25 * 1024 * 1024


@router.post(
    "/files/upload",
    status_code=status.HTTP_201_CREATED,
    response_model=AttachmentResponse,
)
async def upload_attachment(
    file: UploadFile,
    note_id: Annotated[uuid.UUID, Form(description="ID of the job note this file belongs to")],
    attachment_type: Annotated[str, Form(description="Type: 'photo', 'pdf', or 'drawing'")],
    caption: Annotated[str | None, Form()] = None,
    sort_order: Annotated[int, Form()] = 0,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> AttachmentResponse:
    """Upload a file and create an Attachment DB record linked to a job note.

    Saves the file to uploads/attachments/{note_id}/{uuid}{ext}.
    Returns 201 + AttachmentResponse with remote_url set.

    Raises:
    - 400 if attachment_type is invalid (not photo/pdf/drawing)
    - 400 if no file is provided (filename empty)
    - 404 if note_id does not exist
    """
    # Validate attachment_type
    if attachment_type not in _ALLOWED_ATTACHMENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Invalid attachment_type '{attachment_type}'. "
                f"Must be one of: {', '.join(sorted(_ALLOWED_ATTACHMENT_TYPES))}"
            ),
        )

    # Validate file has a name
    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No file provided.",
        )

    # Verify the note exists (RLS scopes to current tenant automatically)
    result = await db.execute(
        select(JobNote).where(JobNote.id == note_id).where(JobNote.deleted_at.is_(None))
    )
    entity_or_404(result.scalars().first(), f"Job note {note_id} not found")

    # Build destination path: uploads/attachments/{note_id}/{uuid}{ext}
    original_suffix = Path(file.filename).suffix.lower() or ".bin"
    unique_filename = f"{uuid.uuid4()}{original_suffix}"
    upload_dir = Path("uploads") / "attachments" / str(note_id)
    upload_dir.mkdir(parents=True, exist_ok=True)
    dest_path = upload_dir / unique_filename

    # Read and validate file size (max 25 MB for attachments)
    content = await file.read()
    if len(content) > 25 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large. Maximum size is 25 MB.",
        )

    # Write file content async
    async with aiofiles.open(dest_path, "wb") as f:
        await f.write(content)

    # remote_url: path served by StaticFiles mount at /files/
    # main.py: app.mount("/files", StaticFiles(directory="uploads"), name="files")
    # So /files/attachments/{note_id}/{filename} resolves correctly.
    remote_url = f"/files/attachments/{note_id}/{unique_filename}"

    # Create Attachment DB record
    attachment = Attachment(
        company_id=current_user.company_id,
        note_id=note_id,
        attachment_type=attachment_type,
        remote_url=remote_url,
        caption=caption,
        sort_order=sort_order,
    )
    db.add(attachment)
    await db.flush()
    await db.refresh(attachment)

    return AttachmentResponse.model_validate(attachment)


@router.post(
    "/files/images",
    status_code=status.HTTP_201_CREATED,
    response_model=ImageUploadResponse,
)
async def upload_image(
    file: UploadFile,
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    _: Annotated[None, Depends(require_permission("photos.upload"))],
) -> ImageUploadResponse:
    """Upload a standalone image and return a servable URL.

    Unlike /files/upload this creates no DB record and needs no parent entity —
    it exists so surfaces that store bare photo URLs (e.g. foreman status updates,
    whose `photos` is a list of strings) have an upload path. Saved to
    uploads/images/{company_id}/{uuid}{ext}, served by the /files StaticFiles mount.

    Raises 400 (missing file / non-image type) or 413 (over 25 MB).
    """
    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No file provided.",
        )
    if file.content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported image type '{file.content_type}'. Must be JPEG, PNG, HEIC, or WebP.",
        )

    content = await file.read()
    if len(content) > _MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large. Maximum size is 25 MB.",
        )

    suffix = Path(file.filename).suffix.lower() or ".jpg"
    unique_filename = f"{uuid.uuid4()}{suffix}"
    upload_dir = Path("uploads") / "images" / str(current_user.company_id)
    upload_dir.mkdir(parents=True, exist_ok=True)

    async with aiofiles.open(upload_dir / unique_filename, "wb") as f:
        await f.write(content)

    remote_url = f"/files/images/{current_user.company_id}/{unique_filename}"
    return ImageUploadResponse(remote_url=remote_url)
