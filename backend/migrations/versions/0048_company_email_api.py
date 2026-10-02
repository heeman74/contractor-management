"""per-company HTTPS email provider, for hosts that block outgoing SMTP

Revision ID: 0048_company_email_api
Revises: 0047_refresh_token_revoked_at
Create Date: 2026-10-02

Measured on the deployed instance: smtp.gmail.com times out on both 587 and 465,
with no answer at all. The platform discards outbound mail traffic, so no port,
provider or credential makes SMTP work from there — only a provider whose API is
an ordinary HTTPS request, which the same host allows everywhere else in the app.

The key is a customer's credential like the SMTP password beside it, so it is
stored encrypted and never returned. Both columns are nullable: a company that
sends over SMTP, or not at all, is unaffected.
"""

import sqlalchemy as sa
from alembic import op

revision = "0048_company_email_api"
down_revision = "0047_refresh_token_revoked_at"
branch_labels = None
depends_on = None

_PROVIDERS = ("resend", "sendgrid", "postmark")


def upgrade() -> None:
    op.add_column("companies", sa.Column("email_api_provider", sa.String(), nullable=True))
    op.add_column("companies", sa.Column("email_api_key_encrypted", sa.String(), nullable=True))

    # A provider with no key cannot send, and a key with no provider has nowhere
    # to go — neither half is useful alone, and a half-configured mailbox fails
    # at send time with nothing to point at.
    op.create_check_constraint(
        "ck_companies_email_api_complete",
        "companies",
        "(email_api_provider IS NULL AND email_api_key_encrypted IS NULL)"
        " OR (email_api_provider IS NOT NULL AND email_api_key_encrypted IS NOT NULL)",
    )
    op.create_check_constraint(
        "ck_companies_email_api_provider_known",
        "companies",
        "email_api_provider IS NULL OR email_api_provider IN "
        f"({', '.join(repr(name) for name in _PROVIDERS)})",
    )


def downgrade() -> None:
    op.drop_constraint("ck_companies_email_api_provider_known", "companies", type_="check")
    op.drop_constraint("ck_companies_email_api_complete", "companies", type_="check")
    op.drop_column("companies", "email_api_key_encrypted")
    op.drop_column("companies", "email_api_provider")
