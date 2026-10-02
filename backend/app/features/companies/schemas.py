import uuid
from typing import Literal

from pydantic import BaseModel, EmailStr, Field

from app.core.base_schemas import BaseResponseSchema


class CompanyCreate(BaseModel):
    """Schema for creating a new company.

    All fields except name are optional — company can be updated later.
    id is optional — when provided by the client (e.g., during sync), it is
    used as the UUID primary key enabling idempotent creates via ON CONFLICT DO NOTHING.
    """

    id: uuid.UUID | None = None
    name: str = Field(min_length=1)
    address: str | None = None
    phone: str | None = None
    trade_types: list[str] | None = None
    logo_url: str | None = None
    business_number: str | None = None


class CompanyUpdate(BaseModel):
    """Schema for partial update of an existing company.

    All fields are optional — only provided fields are updated.
    """

    name: str | None = Field(default=None, min_length=1)
    address: str | None = None
    phone: str | None = None
    trade_types: list[str] | None = None
    logo_url: str | None = None
    business_number: str | None = None
    license_number: str | None = None

    # Who this company's mail is from. The address is used as Reply-To when the
    # instance relay carries the message, and as the sender once the company's
    # own mailbox is configured below.
    email_from_name: str | None = None
    email_from_address: EmailStr | None = None

    # The company's own mailbox. Write-only: smtp_password arrives in plaintext
    # and is stored encrypted, and no response ever returns it. Clearing the
    # mailbox is a separate endpoint rather than a null here, because the three
    # columns are constrained to travel together.
    smtp_host: str | None = None
    smtp_port: int | None = Field(default=None, ge=1, le=65535)
    smtp_use_tls: bool | None = None
    smtp_user: str | None = None
    smtp_password: str | None = Field(default=None, min_length=1)

    # A provider that sends over HTTPS, for hosts that block outgoing SMTP.
    # Write-only like the SMTP password: the key is stored encrypted and no
    # response returns it.
    email_api_provider: Literal["resend", "sendgrid", "postmark"] | None = None
    email_api_key: str | None = Field(default=None, min_length=1)


class CompanyResponse(BaseResponseSchema):
    """Schema for company API responses.

    Inherits id, version, created_at, updated_at, deleted_at from BaseResponseSchema.
    """

    name: str
    address: str | None
    phone: str | None
    trade_types: list[str] | None
    logo_url: str | None
    business_number: str | None
    license_number: str | None = None

    email_from_name: str | None = None
    email_from_address: str | None = None
    smtp_host: str | None = None
    smtp_port: int | None = None
    smtp_use_tls: bool = True
    smtp_user: str | None = None
    # Whether a mailbox is configured, rather than the credential itself —
    # the password is never returned, in any form.
    smtp_configured: bool = False
    email_api_provider: str | None = None
    # Whether a key is stored, never the key.
    email_api_configured: bool = False


class EmailTestResult(BaseModel):
    """What happened when a company's mail settings were exercised.

    A failure is reported here rather than raised: the caller asked a question
    about their configuration, and the provider's own refusal is the answer.
    """

    delivered: bool
    transport: str
    recipient: str
    detail: str


class EmailStatus(BaseModel):
    """What would actually happen if this company sent mail right now.

    The company's own mailbox is optional only when the server has a mail
    account of its own to fall back on. Without one it is the single thing
    standing between a company and being able to email a quote, and calling it
    optional would be false — so whether it is required is a fact about the
    server, reported here rather than guessed at in the UI.
    """

    mailbox_configured: bool
    api_configured: bool
    relay_available: bool
    # False when neither exists: a send would report success and reach nobody.
    can_send: bool
    # "company-smtp", "relay", or "dev-outbox".
    transport: str
    # The From a client would see, so the sender is never a guess.
    sender: str
    reply_to: str | None
