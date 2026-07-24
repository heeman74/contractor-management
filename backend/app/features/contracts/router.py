"""Contracts API router — generation, e-signature, webhook, and public token access.

POST /api/v1/contracts                       — generate from an approved quote (contracts.manage)
GET  /api/v1/contracts                       — list (contracts.manage)
GET  /api/v1/contracts/{id}                  — detail (auth)
POST /api/v1/contracts/{id}/send             — send for signature (contracts.manage)
GET  /api/v1/contracts/{id}/sign-url         — embedded signing URL (auth: signer/admin)
GET  /api/v1/contracts/{id}/signed.pdf       — download signed PDF (admin or signer)
POST /api/v1/contracts/webhook/dropbox-sign  — provider webhook (public, HMAC-verified)
GET  /api/v1/contract-template               — read terms template (contracts.manage)
PUT  /api/v1/contract-template               — edit terms template (contracts.manage)
GET  /api/v1/public/contracts/{token}        — token-scoped public view + sign_url (no login)
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import PlainTextResponse, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import (
    CurrentUser,
    effective_permissions,
    get_current_user,
    require_permission,
)
from app.core.tenant import set_current_tenant_id
from app.features.companies.models import Company
from app.features.contracts.providers import get_signature_provider
from app.features.contracts.providers.base import SignatureProvider
from app.features.contracts.schemas import (
    ContractResponse,
    ContractTemplateResponse,
    ContractTemplateUpdate,
    GenerateContractRequest,
    PublicContractView,
    SendContractResponse,
    SignUrlResponse,
)
from app.features.contracts.service import ContractService
from app.features.contracts.tokens import parse_contract_token

router = APIRouter(prefix="/contracts", tags=["contracts"])

_SIGNED_EVENTS = {"signature_request_all_signed", "signature_request_signed"}
_DECLINED_EVENTS = {"signature_request_declined"}
# Dropbox Sign expects this exact body to acknowledge a webhook callback.
_WEBHOOK_ACK = "Hello API Event Received"


@router.post("", response_model=ContractResponse, status_code=status.HTTP_201_CREATED)
async def generate_contract(
    body: GenerateContractRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[None, Depends(require_permission("contracts.manage"))],
) -> ContractResponse:
    """Generate a contract from an approved quote."""
    contract = await ContractService(db).generate_from_quote(body.quote_id)
    return ContractResponse.model_validate(contract)


@router.get("", response_model=list[ContractResponse])
async def list_contracts(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[None, Depends(require_permission("contracts.manage"))],
) -> list[ContractResponse]:
    """List contracts for the tenant."""
    contracts = await ContractService(db).list()
    return [ContractResponse.model_validate(c) for c in contracts]


# Provider webhook — declared before /{contract_id} to avoid path capture.
@router.post("/webhook/dropbox-sign")
async def dropbox_sign_webhook(
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    provider: Annotated[SignatureProvider, Depends(get_signature_provider)],
) -> PlainTextResponse:
    """Provider webhook (public, HMAC-verified). Persists the signed PDF on completion."""
    raw = await request.body()
    event = provider.verify_and_parse_webhook(dict(request.headers), raw)
    if event is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid webhook signature"
        )

    company_id = event.metadata.get("company_id")
    if company_id:
        # Resolve the (RLS-forced) contract without a login via the request metadata.
        set_current_tenant_id(uuid.UUID(company_id))
        service = ContractService(db)
        if event.event_type in _SIGNED_EVENTS:
            await service.mark_signed(event.request_id, provider)
        elif event.event_type in _DECLINED_EVENTS:
            await service.record_declined(event.request_id)

    return PlainTextResponse(_WEBHOOK_ACK)


@router.get("/{contract_id}", response_model=ContractResponse)
async def get_contract(
    contract_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
) -> ContractResponse:
    """Fetch a contract by id (tenant-scoped)."""
    contract = await ContractService(db).get_or_404(contract_id, detail="Contract not found")
    return ContractResponse.model_validate(contract)


@router.post("/{contract_id}/send", response_model=SendContractResponse)
async def send_contract(
    contract_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    provider: Annotated[SignatureProvider, Depends(get_signature_provider)],
    _: Annotated[None, Depends(require_permission("contracts.manage"))],
) -> SendContractResponse:
    """Create an embedded signature request and notify the client."""
    result = await ContractService(db).send_for_signature(contract_id, provider)
    return SendContractResponse(
        contract=ContractResponse.model_validate(result["contract"]),
        sign_url=result["sign_url"],
        magic_link=result["magic_link"],
    )


@router.get("/{contract_id}/sign-url", response_model=SignUrlResponse)
async def contract_sign_url(
    contract_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
    provider: Annotated[SignatureProvider, Depends(get_signature_provider)],
) -> SignUrlResponse:
    """Return a fresh embedded signing URL for the mobile/in-app ceremony."""
    url = await ContractService(db).get_sign_url(contract_id, provider)
    return SignUrlResponse(sign_url=url)


@router.get("/{contract_id}/signed.pdf")
async def download_signed_pdf(
    contract_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    current_user: Annotated[CurrentUser, Depends(get_current_user)],
) -> Response:
    """Download the signed PDF (admin/manager or the signer client)."""
    service = ContractService(db)
    contract = await service.get_or_404(contract_id, detail="Contract not found")
    if contract.signed_pdf_url is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Contract is not signed yet."
        )
    permissions = await effective_permissions(current_user, db)
    is_signer = contract.client_user_id == current_user.user_id
    if "contracts.manage" not in permissions and not is_signer:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not allowed to download this contract.",
        )
    data = await ContractService._read_pdf(contract.signed_pdf_url)
    return Response(
        content=data,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="contract-{contract_id}.pdf"'},
    )


# --- Contract terms template (contracts.manage) ----------------------------

templates_router = APIRouter(prefix="/contract-template", tags=["contracts"])


@templates_router.get("", response_model=ContractTemplateResponse)
async def get_contract_template(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[None, Depends(require_permission("contracts.manage"))],
) -> ContractTemplateResponse:
    """Read the company's contract-terms template (seeded on first use)."""
    template = await ContractService(db).get_template()
    return ContractTemplateResponse.model_validate(template)


@templates_router.put("", response_model=ContractTemplateResponse)
async def update_contract_template(
    body: ContractTemplateUpdate,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[None, Depends(require_permission("contracts.manage"))],
) -> ContractTemplateResponse:
    """Edit the contract-terms template body/name."""
    template = await ContractService(db).update_template(body.body, body.name)
    return ContractTemplateResponse.model_validate(template)


# --- Public, token-scoped access (no login) --------------------------------

public_router = APIRouter(tags=["contracts-public"])


@public_router.get("/public/contracts/{token}", response_model=PublicContractView)
async def public_contract_view(
    token: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    provider: Annotated[SignatureProvider, Depends(get_signature_provider)],
) -> PublicContractView:
    """Token-scoped contract view + fresh sign_url for the public /sign page."""
    payload = parse_contract_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired link."
        )
    set_current_tenant_id(uuid.UUID(payload["company_id"]))
    service = ContractService(db)
    result = await service.get_public_view(uuid.UUID(payload["contract_id"]), provider)
    contract = result["contract"]
    company = await db.get(Company, contract.company_id)
    return PublicContractView(
        contract_id=contract.id,
        status=contract.status,
        company_name=company.name if company else "",
        signer_name=contract.signer_name,
        terms_snapshot=contract.terms_snapshot,
        validity_statement=contract.validity_statement,
        signed_pdf_url=contract.signed_pdf_url,
        sign_url=result["sign_url"],
    )
