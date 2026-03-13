"""Create business operations tables: quotes, invoices, and templates.

Revision ID: 0011
Revises: 0010
Create Date: 2026-03-13

Changes:
- Create quotes table with status machine and audit fields
- Create quote_line_items table (labor/material items)
- Create quote_templates table (reusable line item collections)
- Create invoices table linked to jobs and optional quotes
- Create invoice_line_items table
- ALTER TABLE companies ADD invoice_prefix + invoice_sequence columns
- Enable RLS on all 5 new tables with standard tenant isolation policy
- Add set_updated_at trigger to all 5 new tables

NOTES:
- All new tables use company_id FK for tenant isolation (same pattern as 0008/0009)
- RLS policies use app.current_company_id ContextVar set by TenantMiddleware
- Discount type: 'percent' reduces total by percent, 'fixed' reduces by flat amount
- quote.revision_number supports re-issue workflow (append-only revision trail)
- invoices UNIQUE(company_id, invoice_number) ensures sequential numbers per tenant
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # quotes — quote lifecycle with revision + status tracking
    #
    # status machine: draft -> sent -> viewed -> approved | declined | expired | revised
    # revision_number: increments on each re-issue (Quote v1, v2, …)
    # discount_type: 'percent' or 'fixed' — NULL means no discount
    # sent_at/viewed_at/approved_at/declined_at: audit timestamps
    # decline_reason: structured code; decline_detail: free text
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE quotes (
            id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id       UUID        NOT NULL REFERENCES companies(id),
            job_id           UUID        NOT NULL REFERENCES jobs(id),
            status           TEXT        NOT NULL DEFAULT 'draft'
                                         CHECK (status IN (
                                           'draft','sent','viewed',
                                           'approved','declined','expired','revised'
                                         )),
            revision_number  INTEGER     NOT NULL DEFAULT 1,
            tax_rate         NUMERIC(5,2) NOT NULL DEFAULT 0,
            discount_type    TEXT        CHECK (discount_type IN ('percent','fixed')),
            discount_value   NUMERIC(10,2) NOT NULL DEFAULT 0,
            expiry_date      DATE,
            sent_at          TIMESTAMPTZ,
            viewed_at        TIMESTAMPTZ,
            approved_at      TIMESTAMPTZ,
            declined_at      TIMESTAMPTZ,
            decline_reason   TEXT,
            decline_detail   TEXT,
            admin_notes      TEXT,
            version          INTEGER     NOT NULL DEFAULT 1,
            created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at       TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # quote_line_items — individual labor or material line items for a quote
    #
    # ON DELETE CASCADE: removing a quote removes its line items
    # item_type: 'labor' or 'material' for categorised reporting
    # sort_order: display ordering (client-controlled)
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE quote_line_items (
            id           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id   UUID          NOT NULL REFERENCES companies(id),
            quote_id     UUID          NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
            item_type    TEXT          NOT NULL CHECK (item_type IN ('labor','material')),
            description  TEXT          NOT NULL,
            quantity     NUMERIC(10,3) NOT NULL,
            unit         TEXT          NOT NULL,
            unit_price   NUMERIC(10,2) NOT NULL,
            sort_order   INTEGER       NOT NULL DEFAULT 0,
            version      INTEGER       NOT NULL DEFAULT 1,
            created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
            updated_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
            deleted_at   TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # quote_templates — reusable line item collections for fast quote creation
    #
    # line_items_json: JSON text array of line item definitions
    #   (parsed at service layer — avoids a join table for templates)
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE quote_templates (
            id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID         NOT NULL REFERENCES companies(id),
            name            TEXT         NOT NULL,
            description     TEXT,
            line_items_json TEXT         NOT NULL DEFAULT '[]',
            tax_rate        NUMERIC(5,2) NOT NULL DEFAULT 0,
            version         INTEGER      NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # invoices — billing documents linked to jobs and optionally to quotes
    #
    # invoice_number: human-readable sequential number (e.g. INV-0001)
    #   UNIQUE per company — generated at service layer using invoice_sequence
    # quote_id: optional — invoices may be created directly without a prior quote
    # status: 'unpaid' | 'partially_paid' | 'paid'
    # issued_at: when invoice was first issued (required)
    # finalized_at: when payment status reaches 'paid'
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE invoices (
            id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID          NOT NULL REFERENCES companies(id),
            job_id          UUID          NOT NULL REFERENCES jobs(id),
            quote_id        UUID          REFERENCES quotes(id),
            invoice_number  TEXT          NOT NULL,
            status          TEXT          NOT NULL DEFAULT 'unpaid'
                                           CHECK (status IN (
                                             'unpaid','partially_paid','paid'
                                           )),
            tax_rate        NUMERIC(5,2)  NOT NULL DEFAULT 0,
            discount_type   TEXT          CHECK (discount_type IN ('percent','fixed')),
            discount_value  NUMERIC(10,2) NOT NULL DEFAULT 0,
            due_date        DATE,
            issued_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
            finalized_at    TIMESTAMPTZ,
            version         INTEGER       NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ,
            UNIQUE (company_id, invoice_number)
        )
        """)
    )

    # -------------------------------------------------------------------------
    # invoice_line_items — individual line items for an invoice
    #
    # ON DELETE CASCADE: removing an invoice removes its line items
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE invoice_line_items (
            id           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id   UUID          NOT NULL REFERENCES companies(id),
            invoice_id   UUID          NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
            item_type    TEXT          NOT NULL CHECK (item_type IN ('labor','material')),
            description  TEXT          NOT NULL,
            quantity     NUMERIC(10,3) NOT NULL,
            unit         TEXT          NOT NULL,
            unit_price   NUMERIC(10,2) NOT NULL,
            sort_order   INTEGER       NOT NULL DEFAULT 0,
            version      INTEGER       NOT NULL DEFAULT 1,
            created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
            updated_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
            deleted_at   TIMESTAMPTZ
        )
        """)
    )

    # -------------------------------------------------------------------------
    # ALTER TABLE companies — add invoice prefix + sequence for auto-numbering
    #
    # invoice_prefix: tenant-customisable prefix (default 'INV')
    # invoice_sequence: counter incremented atomically per invoice creation
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        ALTER TABLE companies
            ADD COLUMN IF NOT EXISTS invoice_prefix   TEXT    NOT NULL DEFAULT 'INV',
            ADD COLUMN IF NOT EXISTS invoice_sequence INTEGER NOT NULL DEFAULT 0
        """)
    )

    # -------------------------------------------------------------------------
    # Indexes for efficient FK lookups
    # -------------------------------------------------------------------------
    op.execute(text("CREATE INDEX idx_quotes_company_id ON quotes (company_id)"))
    op.execute(text("CREATE INDEX idx_quotes_job_id ON quotes (job_id)"))
    op.execute(text("CREATE INDEX idx_quote_line_items_quote_id ON quote_line_items (quote_id)"))
    op.execute(text("CREATE INDEX idx_quote_templates_company_id ON quote_templates (company_id)"))
    op.execute(text("CREATE INDEX idx_invoices_company_id ON invoices (company_id)"))
    op.execute(text("CREATE INDEX idx_invoices_job_id ON invoices (job_id)"))
    op.execute(
        text("CREATE INDEX idx_invoice_line_items_invoice_id ON invoice_line_items (invoice_id)")
    )

    # -------------------------------------------------------------------------
    # Row Level Security — standard tenant isolation (same pattern as 0008/0009)
    #
    # app.current_company_id is set by TenantMiddleware (tenant.py receive_after_begin)
    # The appuser DB role has BYPASSRLS privilege — no policy needed for backend ops
    # -------------------------------------------------------------------------
    for table in [
        "quotes",
        "quote_line_items",
        "quote_templates",
        "invoices",
        "invoice_line_items",
    ]:
        op.execute(text(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY"))
        op.execute(
            text(f"""
            CREATE POLICY tenant_isolation ON {table}
                USING (
                    company_id = NULLIF(current_setting('app.current_company_id', TRUE), '')::UUID
                )
            """)
        )
        op.execute(text(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY"))

    # -------------------------------------------------------------------------
    # set_updated_at triggers — auto-update updated_at on every row mutation
    # set_updated_at() function was created in migration 0002 — just create triggers
    # -------------------------------------------------------------------------
    for table in [
        "quotes",
        "quote_line_items",
        "quote_templates",
        "invoices",
        "invoice_line_items",
    ]:
        op.execute(
            text(f"""
            CREATE TRIGGER set_updated_at
                BEFORE UPDATE ON {table}
                FOR EACH ROW EXECUTE FUNCTION set_updated_at()
            """)
        )


def downgrade() -> None:
    # Drop triggers first, then tables (CASCADE handles line items via FK)
    for table in [
        "quotes",
        "quote_line_items",
        "quote_templates",
        "invoices",
        "invoice_line_items",
    ]:
        op.execute(text(f"DROP TRIGGER IF EXISTS set_updated_at ON {table}"))

    op.execute(text("DROP TABLE IF EXISTS invoice_line_items"))
    op.execute(text("DROP TABLE IF EXISTS invoices"))
    op.execute(text("DROP TABLE IF EXISTS quote_templates"))
    op.execute(text("DROP TABLE IF EXISTS quote_line_items"))
    op.execute(text("DROP TABLE IF EXISTS quotes"))

    op.execute(
        text("""
        ALTER TABLE companies
            DROP COLUMN IF EXISTS invoice_prefix,
            DROP COLUMN IF EXISTS invoice_sequence
        """)
    )
