"""ChecklistRepository — data access layer for DailyChecklist entities."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.base_repository import TenantScopedRepository
from app.features.checklists.models import DailyChecklist


class ChecklistRepository(TenantScopedRepository[DailyChecklist]):
    """Repository for DailyChecklist CRUD and upsert operations."""

    model = DailyChecklist

    async def get_today_for_contractor(
        self,
        contractor_id: uuid.UUID,
        checklist_date: date,
    ) -> list[DailyChecklist]:
        """Return all checklists for a contractor on a given date.

        Returns multiple records when a contractor has tasks across multiple
        trade scopes on the same day.
        """
        stmt = (
            select(DailyChecklist)
            .where(
                DailyChecklist.contractor_id == contractor_id,
                DailyChecklist.checklist_date == checklist_date,
                DailyChecklist.deleted_at.is_(None),
            )
            .order_by(DailyChecklist.created_at)
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def upsert_checklist(
        self,
        company_id: uuid.UUID,
        contractor_id: uuid.UUID,
        project_id: uuid.UUID,
        trade_scope_id: uuid.UUID,
        checklist_date: date,
        checklist_json: dict,
        summary_text: str,
    ) -> DailyChecklist:
        """INSERT checklist or UPDATE on duplicate (contractor + scope + date).

        Uses PostgreSQL ON CONFLICT DO UPDATE for idempotent regeneration.
        Returns the upserted record with all server-generated fields.
        """
        stmt = (
            pg_insert(DailyChecklist)
            .values(
                company_id=company_id,
                contractor_id=contractor_id,
                project_id=project_id,
                trade_scope_id=trade_scope_id,
                checklist_date=checklist_date,
                checklist_json=checklist_json,
                summary_text=summary_text,
                is_pushed=False,
            )
            .on_conflict_do_update(
                index_elements=["company_id", "contractor_id", "trade_scope_id", "checklist_date"],
                index_where=text("deleted_at IS NULL"),
                set_={
                    "checklist_json": checklist_json,
                    "summary_text": summary_text,
                    "is_pushed": False,
                },
            )
            .returning(DailyChecklist)
        )
        result = await self.db.execute(stmt)
        await self.db.flush()
        return result.scalars().first()  # type: ignore[return-value]

    async def mark_pushed(self, checklist_id: uuid.UUID) -> None:
        """Mark a checklist as pushed after FCM dispatch."""
        entity = await self.db.get(DailyChecklist, checklist_id)
        if entity is not None:
            entity.is_pushed = True  # type: ignore[assignment]
            await self.db.flush()
