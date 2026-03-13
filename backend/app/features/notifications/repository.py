"""NotificationRepository — data access layer for device token management.

Inherits from BaseRepository[DeviceToken] (user-scoped, NOT tenant-scoped per
CLAUDE.md OOP rules). Provides token registration (upsert), lookup by user,
and deletion of invalid tokens.
"""

import uuid
from datetime import UTC, datetime

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert

from app.core.base_repository import BaseRepository
from app.features.notifications.models import DeviceToken


class NotificationRepository(BaseRepository[DeviceToken]):
    """Repository for FCM device token CRUD operations."""

    model = DeviceToken

    async def get_tokens_for_user(self, user_id: uuid.UUID) -> list[DeviceToken]:
        """Return all device tokens registered for a given user.

        Used by NotificationService to retrieve all targets for FCM dispatch.
        Multiple tokens per user are expected (different devices).
        """
        result = await self.db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id))
        return list(result.scalars().all())

    async def upsert_token(
        self,
        user_id: uuid.UUID,
        token: str,
        platform: str,
    ) -> DeviceToken:
        """Insert a device token or update last_used_at if already registered.

        ON CONFLICT (user_id, token): updates last_used_at to now() — handles
        the case where the same device re-registers (e.g., after app reinstall).

        Returns the resulting DeviceToken record.
        """
        now = datetime.now(UTC)
        stmt = (
            insert(DeviceToken)
            .values(
                user_id=user_id,
                token=token,
                platform=platform,
                created_at=now,
                last_used_at=now,
            )
            .on_conflict_do_update(
                index_elements=["user_id", "token"],
                set_={"last_used_at": now},
            )
            .returning(DeviceToken)
        )
        result = await self.db.execute(stmt)
        return result.scalars().one()

    async def delete_token(self, token: str) -> None:
        """Remove an invalid FCM token from the registry.

        Called by NotificationService when Firebase returns UnregisteredError,
        indicating the token is no longer valid (app uninstalled, re-registered).
        """
        await self.db.execute(delete(DeviceToken).where(DeviceToken.token == token))
