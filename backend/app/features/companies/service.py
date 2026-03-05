"""Company service — business logic for company operations.

Phase 1: stub implementations. Full CRUD in later phases.
"""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.features.companies.models import Company
from app.features.companies.schemas import CompanyCreate


async def create_company(db: AsyncSession, data: CompanyCreate) -> Company:
    """Create a new company (tenant root)."""
    company = Company(
        name=data.name,
        address=data.address,
        phone=data.phone,
        business_number=data.business_number,
        logo_url=data.logo_url,
    )
    db.add(company)
    await db.flush()
    await db.refresh(company)
    return company


async def get_company(db: AsyncSession, company_id: uuid.UUID) -> Company | None:
    """Retrieve a company by ID."""
    return await db.get(Company, company_id)
