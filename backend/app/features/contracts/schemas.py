"""Request/response schemas for contracts and contract-terms templates."""

from __future__ import annotations

import uuid

from pydantic import BaseModel

from app.core.base_schemas import TenantResponseSchema


class GenerateContractRequest(BaseModel):
    """Generate a contract from an approved quote."""

    quote_id: uuid.UUID


class ContractResponse(TenantResponseSchema):
    """Contract API response."""

    quote_id: uuid.UUID
    job_id: uuid.UUID | None
    client_user_id: uuid.UUID | None
    template_id: uuid.UUID | None
    status: str
    terms_snapshot: str
    validity_statement: str | None
    unsigned_pdf_url: str | None
    signed_pdf_url: str | None
    provider: str | None
    provider_request_id: str | None
    signer_name: str | None
    signer_email: str | None


class ContractTemplateResponse(TenantResponseSchema):
    """Contract-terms template API response."""

    name: str
    body: str
    is_default: bool


class ContractTemplateUpdate(BaseModel):
    """Edit the contract-terms template body (and optionally its name)."""

    body: str
    name: str | None = None


class SendContractResponse(BaseModel):
    """Result of sending a contract for signature."""

    contract: ContractResponse
    sign_url: str
    magic_link: str


class SignUrlResponse(BaseModel):
    """A fresh embedded signing URL."""

    sign_url: str


class PublicContractView(BaseModel):
    """Token-scoped, login-free contract view for the public /sign page."""

    contract_id: uuid.UUID
    status: str
    company_name: str
    signer_name: str | None
    terms_snapshot: str
    validity_statement: str | None
    signed_pdf_url: str | None
    sign_url: str | None
