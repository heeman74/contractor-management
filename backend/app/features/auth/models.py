"""Refresh token model for token rotation and family revocation."""

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class RefreshToken(Base):
    """Refresh token — stored as SHA-256 hash for secure comparison.

    Supports rotation with family revocation (OWASP pattern):
    - Each login creates a new token family (family_id).
    - Each refresh rotates the token: old is revoked, new is issued.
    - If a revoked token is reused, the entire family is revoked (theft detection).

    Note: does NOT use TimestampMixin because refresh_tokens only has
    created_at — no updated_at or deleted_at columns in the DB schema.
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    token_hash: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    family_id: Mapped[str] = mapped_column(String, nullable=False, index=True)
    revoked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
