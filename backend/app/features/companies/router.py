"""Companies API router.

Endpoints:
  POST   /api/v1/companies/          — create company (tenant root)
  GET    /api/v1/companies/{id}      — get company by ID
  PATCH  /api/v1/companies/{id}      — partial update company
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.features.companies import service
from app.features.companies.schemas import (
    CompanyCreate,
    CompanyResponse,
    CompanyUpdate,
)

router = APIRouter(prefix="/companies", tags=["companies"])


@router.post("/", response_model=CompanyResponse, status_code=status.HTTP_201_CREATED)
async def create_company(
    data: CompanyCreate,
    db: AsyncSession = Depends(get_db),
) -> CompanyResponse:
    """Create a new company. No tenant filter — company IS the tenant root."""
    company = await service.create_company(db, data)
    return CompanyResponse.model_validate(company)


@router.get("/{company_id}", response_model=CompanyResponse)
async def get_company(
    company_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> CompanyResponse:
    """Retrieve a company by ID."""
    company = await service.get_company(db, company_id)
    if company is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Company not found",
        )
    return CompanyResponse.model_validate(company)


@router.patch("/{company_id}", response_model=CompanyResponse)
async def update_company(
    company_id: uuid.UUID,
    data: CompanyUpdate,
    db: AsyncSession = Depends(get_db),
) -> CompanyResponse:
    """Partially update a company profile."""
    company = await service.update_company(db, company_id, data)
    if company is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Company not found",
        )
    return CompanyResponse.model_validate(company)
