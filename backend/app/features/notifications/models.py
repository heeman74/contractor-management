"""DeviceToken SQLAlchemy model for FCM push notification device token storage.

DeviceToken is user-scoped (NOT tenant-scoped) — inherits directly from Base
rather than TenantScopedModel. Device tokens belong to individual users, not
to company tenants.

RLS is enforced at the DB level via user_isolation policy on device_tokens table
(created in migration 0010). The backend appuser bypasses RLS for admin ops.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class DeviceToken(Base):
    """FCM device registration token for push notification dispatch.

    Attributes:
        id:          UUID primary key (server-generated).
        user_id:     FK to users.id — token belongs to this user.
        token:       FCM registration token string.
        platform:    'android' or 'ios' — determines FCM message format.
        created_at:  When the token was first registered.
        last_used_at: Updated on each re-registration or successful send.
    """

    __tablename__ = "device_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    token: Mapped[str] = mapped_column(String, nullable=False)
    platform: Mapped[str] = mapped_column(String(10), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=text("now()"),
        nullable=False,
    )
    last_used_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=text("now()"),
        nullable=False,
    )
