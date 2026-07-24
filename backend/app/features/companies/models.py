from sqlalchemy import ARRAY, JSON, Integer, String, text
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
    invoice_prefix: Mapped[str] = mapped_column(String, nullable=False, server_default="'INV'")
    invoice_sequence: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
