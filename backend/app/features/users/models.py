import uuid
from decimal import Decimal

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel


class User(TenantScopedModel):
    """User — tenant-scoped (RLS enforced via company_id)."""

    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String, nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    first_name: Mapped[str | None] = mapped_column(String, nullable=True)
    last_name: Mapped[str | None] = mapped_column(String, nullable=True)
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    # Contractor scheduling fields (added in migration 0007)
    # home_address and coordinates are the contractor's home base used as the
    # origin for travel time calculations to the first job of the day.
    home_address: Mapped[str | None] = mapped_column(String, nullable=True)
    home_latitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)
    home_longitude: Mapped[Decimal | None] = mapped_column(Numeric(9, 6), nullable=True)
    # IANA timezone name (e.g., 'America/Vancouver') for weekly template interpretation.
    # All datetimes are stored in UTC; timezone is used only for display and local-time conversion.
    timezone: Mapped[str] = mapped_column(String, nullable=False, server_default="UTC")

    roles: Mapped[list["UserRole"]] = relationship(back_populates="user", lazy="raise")


class UserRole(TenantScopedModel):
    """UserRole — junction table for user roles within a company.

    A user can have multiple roles (e.g., admin in company A, contractor in company B).
    RLS enforced via company_id.
    """

    __tablename__ = "user_roles"

    __table_args__ = (
        CheckConstraint(
            "role IN ('admin', 'contractor', 'client')",
            name="valid_role",
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id"),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(String, nullable=False)

    user: Mapped["User"] = relationship(back_populates="roles", lazy="raise")
