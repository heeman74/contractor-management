"""Companies API router.

Endpoints:
  POST   /api/v1/companies/              — create company (tenant root)
  GET    /api/v1/companies/{id}          — get company by ID
  PATCH  /api/v1/companies/{id}          — partial update company
  POST   /api/v1/companies/{id}/email/test — send a test message as this company
  DELETE /api/v1/companies/{id}/email/smtp — forget the company's own mailbox

All endpoints require a valid JWT Bearer token.
"""

import uuid

from fastapi import Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_router import CRUDRouter
from app.core.database import get_db
from app.core.email import TRANSPORT_API, TRANSPORT_COMPANY, EmailService
from app.core.secrets import SecretDecryptionError
from app.core.security import CurrentUser, get_current_user, require_permission
from app.features.companies.models import Company
from app.features.companies.schemas import (
    CompanyCreate,
    CompanyResponse,
    CompanyUpdate,
    EmailStatus,
    EmailTestResult,
)
from app.features.companies.service import CompanyService
from app.features.users.models import User


class CompanyRouter(CRUDRouter):
    """Company CRUD router — create, get by ID, partial update."""

    prefix = "/companies"
    tags = ["companies"]
    service_class = CompanyService
    create_schema = CompanyCreate
    update_schema = CompanyUpdate
    response_schema = CompanyResponse
    # Company details appear on every quote, invoice and contract a client
    # sees. Without this the endpoint took any authenticated caller, so a
    # worker could rename the company or change the licence number on it.
    update_permission = "company.settings.manage"

    def _register_routes(self) -> None:
        """Company uses create + get + update (no list endpoint).

        Get and update are registered here rather than taken from the base
        class. The generic handlers fetch by id and rely on row level security
        to keep a caller inside their own tenant — and this table has none, by
        design: it IS the tenant root. So they let any authenticated caller read
        and rewrite any company whose id they had, across tenants. Proven
        against a running server: an admin of one company renamed another's and
        the owner saw the new name.
        """
        self._register_create()
        self._register_own_get()
        self._register_own_update()
        self._register_email_routes()

    def _register_own_get(self) -> None:
        self.router.add_api_route(
            "/{company_id}",
            get_own_company,
            methods=["GET"],
            response_model=CompanyResponse,
            summary="Get your own company",
        )

    def _register_own_update(self) -> None:
        self.router.add_api_route(
            "/{company_id}",
            update_own_company,
            methods=["PATCH"],
            response_model=CompanyResponse,
            summary="Update your own company",
        )

    def _register_email_routes(self) -> None:
        self.router.add_api_route(
            "/{company_id}/email/test",
            send_test_email,
            methods=["POST"],
            response_model=EmailTestResult,
            summary="Send a test message using this company's mail settings",
        )
        self.router.add_api_route(
            "/{company_id}/email/status",
            get_email_status,
            methods=["GET"],
            response_model=EmailStatus,
            summary="What would happen if this company sent mail now",
        )
        self.router.add_api_route(
            "/{company_id}/email/api",
            clear_company_email_api,
            methods=["DELETE"],
            response_model=CompanyResponse,
            summary="Stop sending through an HTTPS provider",
        )
        self.router.add_api_route(
            "/{company_id}/email/smtp",
            clear_company_smtp,
            methods=["DELETE"],
            response_model=CompanyResponse,
            summary="Forget this company's own mailbox",
        )


async def _own_company(
    company_id: uuid.UUID, current_user: CurrentUser, db: AsyncSession
) -> Company:
    """The caller's own company, or 404.

    This table carries no row level security — it is the tenant root — so
    belonging has to be checked here. Another tenant's company reads as absent
    rather than forbidden: whether a given id exists is not theirs to learn.
    """
    if company_id != current_user.company_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Company not found")
    company = await db.get(Company, company_id)
    if company is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Company not found")
    return company


async def _company_for_settings(
    company_id: uuid.UUID, current_user: CurrentUser, db: AsyncSession
) -> Company:
    """The caller's own company, for an operation that changes its settings."""
    company = await _own_company(company_id, current_user, db)
    await require_permission("company.settings.manage")(current_user, db)
    return company


async def get_own_company(
    company_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CompanyResponse:
    """Read your own company. Any member may; another tenant's is not found."""
    company = await _own_company(company_id, current_user, db)
    return CompanyResponse.model_validate(company)


async def update_own_company(
    company_id: uuid.UUID,
    data: CompanyUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CompanyResponse:
    """Update your own company. Requires company.settings.manage."""
    await _company_for_settings(company_id, current_user, db)
    company = await CompanyService(db).update(company_id, data)
    if company is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Company not found")
    return CompanyResponse.model_validate(company)


async def send_test_email(
    company_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> EmailTestResult:
    """Send a test message with this company's settings, to the caller.

    Exists so a company finds out their mail settings are wrong while setting
    them, rather than when a quote fails to reach a client. The recipient is
    always the caller's own address — never one supplied in the request, which
    would make this an open relay for sending mail as a company.
    """
    company = await _company_for_settings(company_id, current_user, db)

    user = await db.get(User, current_user.user_id)
    if user is None or not user.email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Your account has no email address to send a test to.",
        )

    try:
        service = EmailService.for_company(company)
    except SecretDecryptionError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    if not service.delivers:
        return EmailTestResult(
            delivered=False,
            transport=service.transport_label,
            recipient=user.email,
            detail=(
                "No mail server is configured, for this company or for the "
                "server, so nothing was sent."
            ),
        )

    try:
        await service.send(
            to=user.email,
            subject=f"{company.name} — mail settings test",
            text_body=(
                "This is a test of your ContractorHub mail settings.\n\n"
                "If you received it, quotes sent to your clients will reach them "
                "the same way."
            ),
            html_body=(
                "<p>This is a test of your ContractorHub mail settings.</p>"
                "<p>If you received it, quotes sent to your clients will reach "
                "them the same way.</p>"
            ),
        )
    except Exception as exc:
        # Reported rather than raised: the operator asked a question about their
        # configuration, and the provider's own words are the answer.
        return EmailTestResult(
            delivered=False,
            transport=service.transport_label,
            recipient=user.email,
            detail=f"{type(exc).__name__}: {exc}",
        )

    if service.transport_label == TRANSPORT_API:
        sending_as = "this company's email provider"
    elif service.transport_label == TRANSPORT_COMPANY:
        sending_as = "this company's own mailbox"
    else:
        sending_as = "the server's mail account, with your address as the reply-to"
    return EmailTestResult(
        delivered=True,
        transport=service.transport_label,
        recipient=user.email,
        # Accepted, not arrived. The mail server taking a message is the last
        # thing this app can observe: what happens after — spam filtering, a
        # later bounce, a provider refusing an unverified sender — leaves no
        # trace here. Claiming delivery on the strength of an acceptance is the
        # same overstatement as treating a 200 on send as proof a client was
        # emailed, which is what started all of this.
        detail=(
            f"Accepted for delivery via {sending_as}. If it does not arrive "
            "within a few minutes, check the spam folder, and the sending "
            "account's own inbox for a bounce message."
        ),
    )


async def get_email_status(
    company_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> EmailStatus:
    """Report the sender and transport this company's mail would use.

    Lets the settings screen say whether its own mailbox is optional or the only
    way this company can send anything, instead of claiming optional and being
    wrong on a server with no mail account.
    """
    company = await _company_for_settings(company_id, current_user, db)

    try:
        service = EmailService.for_company(company)
    except SecretDecryptionError:
        # The stored credential is unreadable, so the mailbox cannot carry mail
        # even though it is configured. Report the relay that would be used
        # instead, and let the test send explain the credential.
        service = EmailService()
        return EmailStatus(
            mailbox_configured=company.smtp_configured,
            api_configured=company.email_api_configured,
            relay_available=service.delivers,
            can_send=service.delivers,
            transport=service.transport_label,
            sender=service.sender_header,
            reply_to=company.email_from_address,
        )

    relay_available = EmailService().delivers
    return EmailStatus(
        mailbox_configured=company.smtp_configured,
        api_configured=company.email_api_configured,
        relay_available=relay_available,
        can_send=service.delivers,
        transport=service.transport_label,
        sender=service.sender_header,
        reply_to=service.reply_to,
    )


async def clear_company_email_api(
    company_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CompanyResponse:
    """Forget the HTTPS provider, reverting to SMTP or the server's account."""
    await _company_for_settings(company_id, current_user, db)
    company = await CompanyService(db).clear_email_api(company_id)
    return CompanyResponse.model_validate(company)


async def clear_company_smtp(
    company_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CompanyResponse:
    """Forget this company's mailbox, reverting to the server's mail account."""
    await _company_for_settings(company_id, current_user, db)
    company = await CompanyService(db).clear_smtp(company_id)
    return CompanyResponse.model_validate(company)


_company_router = CompanyRouter()
router = _company_router.router
