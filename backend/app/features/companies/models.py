from sqlalchemy import ARRAY, JSON, Boolean, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.base_models import BaseEntityModel


class Company(BaseEntityModel):
    """Company — the tenant root. No RLS applied to this table."""

    __tablename__ = "companies"

    name: Mapped[str] = mapped_column(String, nullable=False)
    address: Mapped[str | None] = mapped_column(String, nullable=True)
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    business_number: Mapped[str | None] = mapped_column(String, nullable=True)
    # CSLB contractor license number — legally required on California contracts.
    license_number: Mapped[str | None] = mapped_column(String, nullable=True)
    logo_url: Mapped[str | None] = mapped_column(String, nullable=True)
    # Trade types stored as PostgreSQL array of text
    trade_types: Mapped[list[str] | None] = mapped_column(ARRAY(String), nullable=True)
    # Scheduling configuration stored as JSONB; validated by SchedulingConfig Pydantic model.
    # Defaults to empty dict — SchedulingConfig fills in defaults on read.
    scheduling_config: Mapped[dict | None] = mapped_column(
        JSON, nullable=True, server_default=text("'{}'::jsonb")
    )
    # Phase 8: sequential invoice numbering — added via migration 0011 ALTER TABLE
    # invoice_prefix: tenant-customisable prefix (default 'INV')
    # invoice_sequence: counter incremented atomically per invoice creation (SELECT FOR UPDATE)
    # Who transactional mail is from. The address is used with the instance
    # relay as the display name and Reply-To; with the company's own SMTP below
    # it becomes the envelope sender too.
    email_from_name: Mapped[str | None] = mapped_column(String, nullable=True)
    email_from_address: Mapped[str | None] = mapped_column(String, nullable=True)

    # The company's own mailbox, so mail genuinely originates from them. Host,
    # user and password travel together — a CHECK enforces it, because a host
    # without credentials fails at send time with nothing to point at. The
    # password is Fernet ciphertext (app/core/secrets.py) and is never returned
    # by the API.
    smtp_host: Mapped[str | None] = mapped_column(String, nullable=True)
    smtp_port: Mapped[int | None] = mapped_column(Integer, nullable=True)
    smtp_use_tls: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    smtp_user: Mapped[str | None] = mapped_column(String, nullable=True)
    smtp_password_encrypted: Mapped[str | None] = mapped_column(String, nullable=True)

    @property
    def smtp_configured(self) -> bool:
        """Whether this company has its own mailbox to send from.

        Exposed to the API in place of the credential: a caller needs to know
        whether a mailbox is set, never what the password is.
        """
        return bool(self.smtp_host and self.smtp_user and self.smtp_password_encrypted)

    invoice_prefix: Mapped[str] = mapped_column(String, nullable=False, server_default="'INV'")
    invoice_sequence: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
