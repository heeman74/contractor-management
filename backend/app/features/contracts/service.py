"""Business logic for generating contracts from quotes.

29-01 covers generation (merge terms -> render PDF -> persist). The e-signature lifecycle
(send / webhook / signed-doc storage) lands in 29-02.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path

import aiofiles
from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService, entity_or_404
from app.core.config import settings
from app.features.companies.models import Company
from app.features.contracts.models import Contract, ContractTemplate
from app.features.contracts.providers.base import SignatureProvider
from app.features.contracts.repository import ContractRepository, ContractTemplateRepository
from app.features.contracts.templates_default import (
    DEFAULT_CONTRACT_BODY,
    DEFAULT_TEMPLATE_NAME,
)
from app.features.contracts.tokens import make_contract_token
from app.features.jobs.models import Job
from app.features.notifications.service import NotificationService
from app.features.pdf.service import PdfService, pdf_service
from app.features.quotes.repository import QuoteRepository
from app.features.users.models import User

_CONTRACTS_DIR = Path("uploads") / "contracts"


class ContractService(TenantScopedService[Contract]):
    """Generates contracts from approved quotes and manages the terms template."""

    repository_class = ContractRepository

    # -- terms template ------------------------------------------------------

    async def _get_or_seed_template(self) -> ContractTemplate:
        """Return the company's default template, seeding it on first use."""
        repo = ContractTemplateRepository(self.db)
        template = await repo.get_default()
        if template is None:
            template = ContractTemplate(
                company_id=self._require_tenant_id(),
                name=DEFAULT_TEMPLATE_NAME,
                body=DEFAULT_CONTRACT_BODY,
                is_default=True,
            )
            self.db.add(template)
            await self.db.flush()
        return template

    async def get_template(self) -> ContractTemplate:
        return await self._get_or_seed_template()

    async def update_template(self, body: str, name: str | None = None) -> ContractTemplate:
        template = await self._get_or_seed_template()
        template.body = body
        if name is not None:
            template.name = name
        await self.db.flush()
        return template

    # -- generation ----------------------------------------------------------

    async def generate_from_quote(self, quote_id: uuid.UUID) -> Contract:
        """Create a contract from an APPROVED quote: merge terms, render + persist PDF."""
        company_id = self._require_tenant_id()
        quote = entity_or_404(
            await QuoteRepository(self.db).get_with_line_items(quote_id), "Quote not found"
        )
        if quote.status != "approved":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="A contract can only be generated from an approved quote.",
            )

        company = entity_or_404(await self.db.get(Company, quote.company_id), "Company not found")
        job = await self.db.get(Job, quote.job_id) if quote.job_id else None
        client = await self.db.get(User, job.client_id) if job and job.client_id else None
        client_name, client_address = pdf_service._client_display(client)

        subtotal, discount_amount, tax_amount, total = PdfService._compute_totals(
            line_items=quote.line_items,
            tax_rate=Decimal(str(quote.tax_rate)),
            discount_type=quote.discount_type,
            discount_value=Decimal(str(quote.discount_value)),
        )
        validity_statement = pdf_service.quote_validity_statement(quote)

        template = await self._get_or_seed_template()
        terms = self._merge(
            template.body,
            {
                "company_name": company.name or "",
                "company_address": company.address or "",
                "company_license_number": company.license_number or "________",
                "company_phone": company.phone or "",
                "client_name": client_name or "________",
                "client_address": client_address or "",
                "client_email": (getattr(client, "email", "") or ""),
                "project_description": (getattr(job, "description", "") or ""),
                "quote_number": str(quote.id),
                "quote_total": f"${total:.2f}",
                "today": datetime.now(UTC).date().strftime("%B %d, %Y"),
                "validity_statement": validity_statement,
                "payment_schedule": "As agreed in the payment schedule.",
            },
        )

        contract = Contract(
            company_id=company_id,
            quote_id=quote.id,
            job_id=quote.job_id,
            client_user_id=getattr(client, "id", None),
            template_id=template.id,
            status="draft",
            terms_snapshot=terms,
            validity_statement=validity_statement,
            signer_name=client_name,
            signer_email=getattr(client, "email", None),
        )
        self.db.add(contract)
        await self.db.flush()

        pdf_bytes = await pdf_service.generate_contract_pdf(
            {
                "company": company,
                "client_name": client_name,
                "client_address": client_address,
                "terms_html": terms,
                "validity_statement": validity_statement,
                "line_items": quote.line_items,
                "subtotal": subtotal,
                "discount_amount": discount_amount,
                "tax_amount": tax_amount,
                "total": total,
                "quote": quote,
            }
        )
        contract.unsigned_pdf_url = await self._persist_pdf(
            company_id, contract.id, "unsigned.pdf", pdf_bytes
        )
        await self.db.flush()
        # Load server-side defaults (created_at/updated_at/version) for serialization.
        await self.db.refresh(contract)
        return contract

    @staticmethod
    def _merge(body: str, fields: dict[str, str]) -> str:
        """Replace {{field}} placeholders with resolved values."""
        merged = body
        for key, value in fields.items():
            merged = merged.replace("{{" + key + "}}", str(value))
        return merged

    @staticmethod
    async def _persist_pdf(
        company_id: uuid.UUID, contract_id: uuid.UUID, filename: str, data: bytes
    ) -> str:
        """Write a contract PDF under uploads/contracts/... and return its /files URL."""
        directory = _CONTRACTS_DIR / str(company_id) / str(contract_id)
        directory.mkdir(parents=True, exist_ok=True)
        async with aiofiles.open(directory / filename, "wb") as handle:
            await handle.write(data)
        return f"/files/contracts/{company_id}/{contract_id}/{filename}"

    @staticmethod
    async def _read_pdf(url: str) -> bytes:
        """Read a persisted PDF back from its /files URL."""
        path = Path("uploads") / url.removeprefix("/files/")
        async with aiofiles.open(path, "rb") as handle:
            return await handle.read()

    # -- e-signature lifecycle (29-02) --------------------------------------

    async def send_for_signature(self, contract_id: uuid.UUID, provider: SignatureProvider) -> dict:
        """Create an embedded signature request and notify the client. Returns the
        signing URL + a public magic-link token."""
        contract = await self.get_or_404(contract_id, detail="Contract not found")
        if contract.status != "draft":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Contract has already been sent for signature.",
            )
        if not contract.signer_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Contract has no client signer email.",
            )
        if not contract.unsigned_pdf_url:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Contract has no generated document.",
            )

        pdf_bytes = await self._read_pdf(contract.unsigned_pdf_url)
        request = await provider.create_embedded_request(
            pdf_bytes=pdf_bytes,
            signer_name=contract.signer_name or contract.signer_email,
            signer_email=contract.signer_email,
            subject="Please sign your contract",
            metadata={
                "contract_id": str(contract.id),
                "company_id": str(contract.company_id),
            },
        )

        contract.provider = "dropbox_sign"
        contract.provider_request_id = request.request_id
        contract.provider_metadata = {"signature_id": request.signature_id}
        contract.status = "sent"
        contract.sent_at = datetime.now(UTC)
        await self.db.flush()

        token = make_contract_token(contract.id, contract.client_user_id, contract.company_id)
        magic_link = f"{settings.public_web_url}/sign/{token}"
        if contract.client_user_id:
            await NotificationService(self.db).send_contract_ready_notification(
                contract.client_user_id, contract.id, magic_link
            )

        await self.db.refresh(contract)
        return {
            "contract": contract,
            "sign_url": request.sign_url,
            "token": token,
            "magic_link": magic_link,
        }

    async def get_sign_url(self, contract_id: uuid.UUID, provider: SignatureProvider) -> str:
        """Return a fresh embedded signing URL and mark the contract viewed."""
        contract = await self.get_or_404(contract_id, detail="Contract not found")
        signature_id = (contract.provider_metadata or {}).get("signature_id")
        if not signature_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Contract has not been sent for signature.",
            )
        await self._record_view(contract)
        return await provider.get_sign_url(signature_id)

    async def get_public_view(self, contract_id: uuid.UUID, provider: SignatureProvider) -> dict:
        """Contract + fresh sign_url for the public /sign page (tenant context preset)."""
        contract = await self.get_or_404(contract_id, detail="Contract not found")
        await self._record_view(contract)
        signature_id = (contract.provider_metadata or {}).get("signature_id")
        sign_url = await provider.get_sign_url(signature_id) if signature_id else None
        return {"contract": contract, "sign_url": sign_url}

    async def mark_signed(self, request_id: str, provider: SignatureProvider) -> None:
        """Persist the signed PDF and flip status to signed (idempotent)."""
        contract = await self.repository.get_by_request_id(request_id)
        if contract is None or contract.status == "signed":
            return
        signed_bytes = await provider.get_signed_pdf(request_id)
        contract.signed_pdf_url = await self._persist_pdf(
            contract.company_id, contract.id, "signed.pdf", signed_bytes
        )
        contract.status = "signed"
        contract.signed_at = datetime.now(UTC)
        await self.db.flush()
        await NotificationService(self.db).send_contract_signed_notification(contract.id)

    async def record_declined(self, request_id: str) -> None:
        """Mark a contract declined from a provider webhook."""
        contract = await self.repository.get_by_request_id(request_id)
        if contract is not None and contract.status not in {"signed", "declined"}:
            contract.status = "declined"
            contract.declined_at = datetime.now(UTC)
            await self.db.flush()

    async def _record_view(self, contract: Contract) -> None:
        if contract.status == "sent":
            contract.status = "viewed"
            contract.viewed_at = datetime.now(UTC)
            await self.db.flush()
