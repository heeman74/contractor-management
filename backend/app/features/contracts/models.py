"""ORM models for contracts and editable contract-terms templates.

- ContractTemplate — company-editable terms template (seeded with a CA-structured default).
- Contract         — a contract generated from an approved quote, tracked through the
                     e-signature lifecycle, with the merged terms frozen at generation.

All CLAUDE.md rules apply: TenantScopedModel base, lazy="raise" relationships.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base_models import TenantScopedModel

_STATUS_CHECK = "status IN ('draft', 'sent', 'viewed', 'signed', 'declined', 'voided')"


class ContractTemplate(TenantScopedModel):
    """Company-editable contract-terms template with merge-field placeholders."""

    __tablename__ = "contract_templates"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")


class Contract(TenantScopedModel):
    """A contract generated from an approved quote and taken through e-signature.

    terms_snapshot freezes the merged terms at generation, so later template edits never
    mutate a contract that has already been sent.
    """

    __tablename__ = "contracts"

    __table_args__ = (CheckConstraint(_STATUS_CHECK, name="contracts_status_check"),)

    quote_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("quotes.id", ondelete="CASCADE"),
        nullable=False,
    )
    job_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    client_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    template_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)

    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="draft")
    terms_snapshot: Mapped[str] = mapped_column(Text, nullable=False)
    validity_statement: Mapped[str | None] = mapped_column(Text, nullable=True)

    unsigned_pdf_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    signed_pdf_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    provider: Mapped[str | None] = mapped_column(Text, nullable=True)
    provider_request_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    provider_metadata: Mapped[dict] = mapped_column(
        JSONB, nullable=False, server_default="'{}'::jsonb"
    )

    signer_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    signer_email: Mapped[str | None] = mapped_column(Text, nullable=True)

    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    viewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    signed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    declined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
