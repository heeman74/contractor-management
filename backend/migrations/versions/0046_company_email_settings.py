"""per-company email sender and optional SMTP credentials

Revision ID: 0046_company_email_settings
Revises: 0045_admin_company_settings
Create Date: 2026-10-01

Quote email briefly went out through one instance-wide SMTP account, so every
company's quotes were addressed from the operator's mailbox. Putting the
company's address in From does not fix it: a provider will not accept a sender
it has not authenticated. The sender has to be resolved per company, which needs
somewhere to put it.

Two tiers, so no company is blocked while others are still setting up:

- email_from_name / email_from_address: who the mail is from. Usable with the
  instance relay, which sends with the company as the display name and
  Reply-To, so replies reach the contractor even when the envelope cannot
  claim their domain.
- smtp_*: the company's own mailbox. Mail then genuinely originates from them.
  The password is stored encrypted (see app/core/secrets.py) and is never
  returned by the API.

Nullable throughout: existing companies keep working, with no sender configured
and therefore no email, which is the state they are already in.
"""

import sqlalchemy as sa
from alembic import op

revision = "0046_company_email_settings"
down_revision = "0045_admin_company_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("companies", sa.Column("email_from_name", sa.String(), nullable=True))
    op.add_column("companies", sa.Column("email_from_address", sa.String(), nullable=True))
    op.add_column("companies", sa.Column("smtp_host", sa.String(), nullable=True))
    op.add_column("companies", sa.Column("smtp_port", sa.Integer(), nullable=True))
    op.add_column(
        "companies",
        sa.Column("smtp_use_tls", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column("companies", sa.Column("smtp_user", sa.String(), nullable=True))
    # Ciphertext, not a password. Named so that a plaintext write is obviously
    # wrong to anyone reading a query.
    op.add_column("companies", sa.Column("smtp_password_encrypted", sa.String(), nullable=True))

    # A host without the credentials to use it would fail at send time with
    # nothing to point at, so the three travel together or not at all.
    op.create_check_constraint(
        "ck_companies_smtp_complete",
        "companies",
        "(smtp_host IS NULL AND smtp_user IS NULL AND smtp_password_encrypted IS NULL)"
        " OR (smtp_host IS NOT NULL AND smtp_user IS NOT NULL"
        " AND smtp_password_encrypted IS NOT NULL)",
    )


def downgrade() -> None:
    op.drop_constraint("ck_companies_smtp_complete", "companies", type_="check")
    for column in (
        "smtp_password_encrypted",
        "smtp_user",
        "smtp_use_tls",
        "smtp_port",
        "smtp_host",
        "email_from_address",
        "email_from_name",
    ):
        op.drop_column("companies", column)
