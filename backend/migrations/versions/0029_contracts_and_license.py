"""Contracts, contract-terms templates, and Company.license_number

Revision ID: 0029_contracts_and_license
Revises: 0028_project_assignment_roles
Create Date: 2026-07-24

Changes:
- ALTER companies ADD license_number (CSLB contractor license #, nullable)
- CREATE contract_templates — company-editable terms template, RLS-scoped, seeded
  with a California-structured default per existing company (before RLS is enabled)
- CREATE contracts — quote-derived contract tracked through the e-signature lifecycle,
  RLS-scoped

Follows the additive backfill-before-RLS pattern from 0027.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

from app.features.contracts.templates_default import (
    DEFAULT_CONTRACT_BODY,
    DEFAULT_TEMPLATE_NAME,
)

revision: str = "0029_contracts_and_license"
down_revision: str | None = "0028_project_assignment_roles"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_STATUS_CHECK = "status IN ('draft', 'sent', 'viewed', 'signed', 'declined', 'voided')"


def upgrade() -> None:
    op.execute("ALTER TABLE companies ADD COLUMN license_number TEXT")

    # -- contract_templates -------------------------------------------------
    op.execute("""
        CREATE TABLE contract_templates (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            name        TEXT NOT NULL,
            body        TEXT NOT NULL,
            is_default  BOOLEAN NOT NULL DEFAULT TRUE,
            version     INTEGER NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ
        )
    """)
    op.execute("CREATE INDEX ix_contract_templates_company ON contract_templates (company_id)")

    # Seed one default template per existing company while RLS is still off.
    op.execute(
        text(
            "INSERT INTO contract_templates (company_id, name, body) "
            "SELECT id, :name, :body FROM companies"
        ).bindparams(name=DEFAULT_TEMPLATE_NAME, body=DEFAULT_CONTRACT_BODY)
    )

    op.execute("ALTER TABLE contract_templates ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE contract_templates FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_contract_templates
        ON contract_templates
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)

    # -- contracts ----------------------------------------------------------
    op.execute(f"""
        CREATE TABLE contracts (
            id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id           UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            quote_id             UUID NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
            job_id               UUID,
            client_user_id       UUID,
            template_id          UUID,
            status               TEXT NOT NULL DEFAULT 'draft' CHECK ({_STATUS_CHECK}),
            terms_snapshot       TEXT NOT NULL,
            validity_statement   TEXT,
            unsigned_pdf_url     TEXT,
            signed_pdf_url       TEXT,
            provider             TEXT,
            provider_request_id  TEXT,
            provider_metadata    JSONB NOT NULL DEFAULT '{{}}'::jsonb,
            signer_name          TEXT,
            signer_email         TEXT,
            sent_at              TIMESTAMPTZ,
            viewed_at            TIMESTAMPTZ,
            signed_at            TIMESTAMPTZ,
            declined_at          TIMESTAMPTZ,
            version              INTEGER NOT NULL DEFAULT 1,
            created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at           TIMESTAMPTZ
        )
    """)
    op.execute("CREATE INDEX ix_contracts_company_quote ON contracts (company_id, quote_id)")
    op.execute("CREATE INDEX ix_contracts_company_status ON contracts (company_id, status)")
    op.execute("CREATE INDEX ix_contracts_provider_request ON contracts (provider_request_id)")

    op.execute("ALTER TABLE contracts ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE contracts FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_contracts
        ON contracts
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS contracts CASCADE")
    op.execute("DROP TABLE IF EXISTS contract_templates CASCADE")
    op.execute("ALTER TABLE companies DROP COLUMN IF EXISTS license_number")
