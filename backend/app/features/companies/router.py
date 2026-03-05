"""Companies API router.

Phase 1: stub endpoints. Full CRUD with auth in later phases.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.features.companies import service
from app.features.companies.schemas import CompanyCreate, CompanyResponse

router = APIRouter(prefix="/companies", tags=["companies"])


@router.post("/", response_model=CompanyResponse, status_code=status.HTTP_201_CREATED)
async def create_company(
    data: CompanyCreate,
    db: AsyncSession = Depends(get_db),
) -> CompanyResponse:
    """Create a new company. Phase 1: no auth required."""
    company = await service.create_company(db, data)
    return CompanyResponse.model_validate(company)


@router.get("/{company_id}", response_model=CompanyResponse)
async def get_company(
    company_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> CompanyResponse:
    """Retrieve a company by ID. Phase 1: no auth required."""
    company = await service.get_company(db, company_id)
    if company is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Company not found",
        )
    return CompanyResponse.model_validate(company)
