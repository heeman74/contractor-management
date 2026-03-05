"""Company service — business logic for company operations."""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.features.companies.models import Company
from app.features.companies.schemas import CompanyCreate, CompanyUpdate


async def create_company(db: AsyncSession, data: CompanyCreate) -> Company:
    """Create a new company (tenant root).

    Company creation has no tenant filter — it IS the tenant root.
    The created company's ID becomes the company_id for all child entities.
    """
    company = Company(
        name=data.name,
        address=data.address,
        phone=data.phone,
        business_number=data.business_number,
        logo_url=data.logo_url,
        trade_types=data.trade_types,
    )
    db.add(company)
    await db.flush()
    await db.refresh(company)
    return company


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
