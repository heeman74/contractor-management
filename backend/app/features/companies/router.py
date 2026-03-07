"""Companies API router.

Endpoints:
  POST   /api/v1/companies/          — create company (tenant root)
  GET    /api/v1/companies/{id}      — get company by ID
  PATCH  /api/v1/companies/{id}      — partial update company

All endpoints require a valid JWT Bearer token.
"""

from app.core.base_router import CRUDRouter
from app.features.companies.schemas import (
    CompanyCreate,
    CompanyResponse,
    CompanyUpdate,
)
from app.features.companies.service import CompanyService


class CompanyRouter(CRUDRouter):
    """Company CRUD router — create, get by ID, partial update."""

    prefix = "/companies"
    tags = ["companies"]
    service_class = CompanyService
    create_schema = CompanyCreate
    update_schema = CompanyUpdate
    response_schema = CompanyResponse

    def _register_routes(self) -> None:
        """Company uses create + get + update (no list endpoint)."""
        self._register_create()
        self._register_get()
        self._register_update()


_company_router = CompanyRouter()
router = _company_router.router
