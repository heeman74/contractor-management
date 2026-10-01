"""Company service — business logic for company operations."""

import uuid

from fastapi import HTTPException, status
from sqlalchemy.dialects.postgresql import insert

from app.core.base_repository import BaseRepository
from app.core.base_service import BaseService
from app.core.secrets import encrypt_secret, encryption_available
from app.features.companies.models import Company
from app.features.companies.schemas import CompanyCreate, CompanyUpdate


class CompanyRepository(BaseRepository[Company]):
    """Repository for Company entities (non-tenant-scoped)."""

    model = Company


class CompanyService(BaseService[Company]):
    """Business logic for company CRUD operations."""

    repository_class = CompanyRepository

    async def create(self, data: CompanyCreate) -> Company:
        """Create a new company using idempotent INSERT ON CONFLICT DO NOTHING.

        If a client-provided UUID is given in data.id and a company with that
        UUID already exists, the existing record is returned silently (no 409).
        This enables safe retry deduplication during sync operations.

        Company creation has no tenant filter — it IS the tenant root.
        """
        return await self._create_idempotent(data)

    async def _create_idempotent(self, data: CompanyCreate) -> Company:
        """Idempotent company create using INSERT ON CONFLICT DO NOTHING."""
        values: dict = {
            "name": data.name,
            "address": data.address,
            "phone": data.phone,
            "business_number": data.business_number,
            "logo_url": data.logo_url,
            "trade_types": data.trade_types,
        }
        if data.id is not None:
            values["id"] = data.id

        stmt = insert(Company).values(**values).on_conflict_do_nothing(index_elements=["id"])
        result = await self.db.execute(stmt)

        # Determine which ID to fetch (inserted or pre-existing)
        if data.id is not None:
            company_id = data.id
        else:
            inserted_pk = result.inserted_primary_key
            if inserted_pk is not None:
                company_id = inserted_pk[0]
            else:
                raise RuntimeError("Failed to determine company ID after insert")

        return await self.db.get(Company, company_id)  # type: ignore[return-value]

    async def update_server_wins(self, data: CompanyCreate) -> Company:
        """Upsert a company using server-wins conflict resolution.

        If a company with data.id already exists, ALL fields are overwritten
        (server-wins — no version comparison). If it does not exist, it is
        created. This is used when the server is authoritative.
        """
        if data.id is None:
            raise ValueError("id is required for server-wins upsert")

        stmt = (
            insert(Company)
            .values(
                id=data.id,
                name=data.name,
                address=data.address,
                phone=data.phone,
                business_number=data.business_number,
                logo_url=data.logo_url,
                trade_types=data.trade_types,
            )
            .on_conflict_do_update(
                index_elements=["id"],
                set_={
                    "name": data.name,
                    "address": data.address,
                    "phone": data.phone,
                    "business_number": data.business_number,
                    "logo_url": data.logo_url,
                    "trade_types": data.trade_types,
                },
            )
        )
        await self.db.execute(stmt)
        return await self.db.get(Company, data.id)  # type: ignore[return-value]

    async def update(
        self,
        entity_id: uuid.UUID,
        data: CompanyUpdate,  # type: ignore[override]
    ) -> Company | None:
        """Partially update a company. Only non-None fields are updated."""
        update_data = data.model_dump(exclude_none=True)
        self._encrypt_smtp_password(update_data)
        return await self.repository.update(entity_id, update_data)

    @staticmethod
    def _encrypt_smtp_password(update_data: dict) -> None:
        """Turn an incoming plaintext password into the stored ciphertext.

        The column is named for what it holds, so the translation happens in one
        place and a plaintext write would have to be written deliberately.

        With no key configured the write is refused rather than performed in the
        clear — this is a customer's mailbox password, not ours.
        """
        password = update_data.pop("smtp_password", None)
        if password is None:
            return

        if not encryption_available():
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=(
                    "This server has no credential encryption key configured, so "
                    "mail passwords cannot be stored. Ask an administrator to set "
                    "CREDENTIALS_ENCRYPTION_KEY."
                ),
            )
        update_data["smtp_password_encrypted"] = encrypt_secret(password)

    async def clear_smtp(self, entity_id: uuid.UUID) -> Company | None:
        """Forget a company's own mailbox, falling back to the instance relay.

        A separate operation rather than nulls in an update: the three columns
        are constrained to travel together, so clearing them one at a time
        through a partial update would be rejected by the database.
        """
        return await self.repository.update(
            entity_id,
            {"smtp_host": None, "smtp_user": None, "smtp_password_encrypted": None},
        )
