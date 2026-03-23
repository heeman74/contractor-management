"""Repositories for AI conversation, message, and token usage models."""

import uuid

from sqlalchemy import func, select

from app.core.base_repository import BaseRepository
from app.features.ai.models import AIConversation, AIMessage, AITokenUsage


class AIConversationRepository(BaseRepository[AIConversation]):
    """Repository for AIConversation entities."""

    model = AIConversation

    async def get_active_for_project(
        self, project_id: uuid.UUID, conv_type: str
    ) -> AIConversation | None:
        """Return the most recent active conversation for a project + type."""
        result = await self.db.execute(
            select(self.model)
            .where(
                self.model.project_id == project_id,
                self.model.conv_type == conv_type,
                self.model.status == "active",
                self.model.deleted_at.is_(None),
            )
            .order_by(self.model.created_at.desc())
            .limit(1)
        )
        return result.scalars().first()

    async def get_active_for_scope(self, scope_id: uuid.UUID) -> AIConversation | None:
        """Return the active interview conversation for a trade scope."""
        result = await self.db.execute(
            select(self.model)
            .where(
                self.model.scope_id == scope_id,
                self.model.conv_type == "interview",
                self.model.status == "active",
                self.model.deleted_at.is_(None),
            )
            .limit(1)
        )
        return result.scalars().first()


class AIMessageRepository(BaseRepository[AIMessage]):
    """Repository for AIMessage entities."""

    model = AIMessage

    async def list_by_conversation(self, conversation_id: uuid.UUID) -> list[AIMessage]:
        """Return all messages for a conversation ordered by sequence_num ASC."""
        result = await self.db.execute(
            select(self.model)
            .where(self.model.conversation_id == conversation_id)
            .order_by(self.model.sequence_num.asc())
        )
        return list(result.scalars().all())

    async def get_next_sequence(self, conversation_id: uuid.UUID) -> int:
        """Return the next sequence number for a conversation (0-indexed)."""
        result = await self.db.execute(
            select(func.max(self.model.sequence_num)).where(
                self.model.conversation_id == conversation_id
            )
        )
        max_seq = result.scalar()
        return 0 if max_seq is None else max_seq + 1


class AITokenUsageRepository(BaseRepository[AITokenUsage]):
    """Repository for AITokenUsage entities."""

    model = AITokenUsage
