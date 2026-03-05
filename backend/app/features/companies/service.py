"""Company service — business logic for company operations."""

import uuid

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.companies.models import Company
from app.features.companies.schemas import CompanyCreate, CompanyUpdate


async def create_company(db: AsyncSession, data: CompanyCreate) -> Company:
    """Create a new company using idempotent INSERT ON CONFLICT DO NOTHING.

    If a client-provided UUID is given in data.id and a company with that
    UUID already exists, the existing record is returned silently (no 409).
    This enables safe retry deduplication during sync operations.

    Company creation has no tenant filter — it IS the tenant root.
    """
    return await create_company_idempotent(db, data)


async def create_company_idempotent(
    db: AsyncSession, data: CompanyCreate
) -> Company:
    """Idempotent company create using INSERT ON CONFLICT DO NOTHING.

    When a client provides an id (UUID) and a company with that id already
    exists, the insert is silently skipped and the existing record returned.
    This is the correct behaviour for offline sync retry deduplication.
    """
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

    stmt = insert(Company).values(**values).on_conflict_do_nothing(
        index_elements=["id"]
    )
    result = await db.execute(stmt)

    # Determine which ID to fetch (inserted or pre-existing)
    if data.id is not None:
        company_id = data.id
    else:
        # For server-generated IDs, use the inserted primary key
        inserted_pk = result.inserted_primary_key
        if inserted_pk is not None:
            company_id = inserted_pk[0]
        else:
            # Should not happen for server-generated IDs, but guard anyway
            raise RuntimeError("Failed to determine company ID after insert")

    company = await db.get(Company, company_id)
    return company  # type: ignore[return-value]


async def update_company_server_wins(
    db: AsyncSession, data: CompanyCreate
) -> Company:
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
    await db.execute(stmt)
    company = await db.get(Company, data.id)
    return company  # type: ignore[return-value]


async def get_company(db: AsyncSession, company_id: uuid.UUID) -> Company | None:
    """Retrieve a company by ID. Returns None if not found."""
    return await db.get(Company, company_id)


async def update_company(
    db: AsyncSession, company_id: uuid.UUID, data: CompanyUpdate
) -> Company | None:
    """Partially update a company. Only non-None fields are updated.

    Returns the updated Company or None if not found.
    """
    company = await db.get(Company, company_id)
    if company is None:
        return None

    update_data = data.model_dump(exclude_none=True)
    for field, value in update_data.items():
        setattr(company, field, value)

    await db.flush()
    await db.refresh(company)
    return company
