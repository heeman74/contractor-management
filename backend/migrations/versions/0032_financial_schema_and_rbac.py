"""financial_schema_and_rbac: 5 finance tables + RLS + category seed + PM backfill

Revision ID: 0032_financial_schema_and_rbac
Revises: 0031_job_manager
Create Date: 2026-07-25

Changes:
- CREATE TABLE cost_categories, cost_entries, labor_rates, budgets,
  budget_category_breakdowns — five tenant-scoped tables for FINSEC-01 (see
  app/features/finance/models.py for the matching ORM models).
- Seed the 4 protected system cost categories (labor, materials, subcontractor,
  other) for every existing company BEFORE enabling RLS — mirrors 0027's
  backfill-before-ENABLE approach so the table-owning appuser role (NOSUPERUSER
  NOBYPASSRLS) can insert without tenant context.
- ENABLE + FORCE RLS with a tenant_isolation_<table> policy on each of the five
  tables, matching 0025/0027, plus GRANT SELECT/INSERT/UPDATE/DELETE TO appuser
  so the runtime role can operate under RLS (matches 0023/0024 grants).
- Backfill every existing company's project_manager row in
  company_role_permissions with the three finance.* keys added in migration
  0031's sibling plan (30-01). company_role_permissions has had FORCE RLS since
  0027 and appuser is NOBYPASSRLS, so a bare cross-tenant UPDATE is filtered out
  — loop per company with SET LOCAL app.current_company_id before each UPDATE.
  Only project_manager is touched; admin/owner/gc/foreman/contractor/worker/
  client rows are untouched. The jsonb `@>` guard makes the backfill idempotent.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0032_financial_schema_and_rbac"
down_revision: str | None = "0031_job_manager"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_FINANCE_PERMISSION_KEYS = '\'["finance.view","finance.manage","finance.rates.manage"]\'::jsonb'

_TENANT_SCOPED_COLUMNS = """
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    version     INTEGER NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
"""

_FINANCE_TABLES = (
    "budget_category_breakdowns",
    "budgets",
    "cost_entries",
    "labor_rates",
    "cost_categories",
)


def upgrade() -> None:
    # -------------------------------------------------------------------
    # 1. CREATE TABLE cost_categories
    # -------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE cost_categories (
            {_TENANT_SCOPED_COLUMNS},
            name        TEXT NOT NULL,
            is_system   BOOLEAN NOT NULL DEFAULT false,
            CONSTRAINT uq_cost_categories_company_name UNIQUE (company_id, name)
        )
    """)

    # -------------------------------------------------------------------
    # 2. CREATE TABLE cost_entries
    # -------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE cost_entries (
            {_TENANT_SCOPED_COLUMNS},
            job_id          UUID REFERENCES jobs(id) ON DELETE CASCADE,
            trade_scope_id  UUID REFERENCES trade_scopes(id) ON DELETE CASCADE,
            category_id     UUID NOT NULL REFERENCES cost_categories(id),
            amount          NUMERIC(10, 2) NOT NULL,
            incurred_date   DATE NOT NULL,
            vendor          TEXT,
            note            TEXT
        )
    """)
    op.execute("CREATE INDEX ix_cost_entries_company_id ON cost_entries (company_id)")
    op.execute("CREATE INDEX ix_cost_entries_job_id ON cost_entries (job_id)")
    op.execute("CREATE INDEX ix_cost_entries_trade_scope_id ON cost_entries (trade_scope_id)")

    # -------------------------------------------------------------------
    # 3. CREATE TABLE labor_rates
    # -------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE labor_rates (
            {_TENANT_SCOPED_COLUMNS},
            user_id         UUID NOT NULL,
            hourly_cost     NUMERIC(10, 2) NOT NULL,
            effective_from  DATE NOT NULL
        )
    """)
    op.execute("""
        CREATE INDEX ix_labor_rates_company_user_effective
        ON labor_rates (company_id, user_id, effective_from)
    """)

    # -------------------------------------------------------------------
    # 4. CREATE TABLE budgets
    # -------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE budgets (
            {_TENANT_SCOPED_COLUMNS},
            project_id      UUID REFERENCES projects(id) ON DELETE CASCADE,
            trade_scope_id  UUID REFERENCES trade_scopes(id) ON DELETE CASCADE,
            total           NUMERIC(10, 2) NOT NULL
        )
    """)
    op.execute("CREATE INDEX ix_budgets_company_id ON budgets (company_id)")
    op.execute("CREATE INDEX ix_budgets_project_id ON budgets (project_id)")
    op.execute("CREATE INDEX ix_budgets_trade_scope_id ON budgets (trade_scope_id)")

    # -------------------------------------------------------------------
    # 5. CREATE TABLE budget_category_breakdowns
    # -------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE budget_category_breakdowns (
            {_TENANT_SCOPED_COLUMNS},
            budget_id       UUID NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
            category_id     UUID NOT NULL REFERENCES cost_categories(id),
            amount          NUMERIC(10, 2) NOT NULL
        )
    """)
    op.execute("""
        CREATE INDEX ix_budget_category_breakdowns_budget_id
        ON budget_category_breakdowns (budget_id)
    """)

    # -------------------------------------------------------------------
    # 6. Seed the 4 protected system cost categories per company, BEFORE
    #    enabling RLS (plain INSERT, mirrors 0027's pre-RLS backfill).
    # -------------------------------------------------------------------
    op.execute("""
        INSERT INTO cost_categories (company_id, name, is_system)
        SELECT c.id, v.name, true
        FROM companies c
        CROSS JOIN (VALUES ('labor'),('materials'),('subcontractor'),('other')) AS v(name)
        ON CONFLICT (company_id, name) DO NOTHING
    """)

    # -------------------------------------------------------------------
    # 7. RLS: ENABLE + FORCE + tenant_isolation policy + appuser grant,
    #    for each of the five tables. Mirrors the three-statement RLS block
    #    from 0025/0027 plus the appuser grant from 0023/0024.
    # -------------------------------------------------------------------
    op.execute("ALTER TABLE cost_categories ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE cost_categories FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_cost_categories
        ON cost_categories
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON cost_categories TO appuser")

    op.execute("ALTER TABLE cost_entries ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE cost_entries FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_cost_entries
        ON cost_entries
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON cost_entries TO appuser")

    op.execute("ALTER TABLE labor_rates ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE labor_rates FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_labor_rates
        ON labor_rates
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON labor_rates TO appuser")

    op.execute("ALTER TABLE budgets ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE budgets FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_budgets
        ON budgets
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON budgets TO appuser")

    op.execute("ALTER TABLE budget_category_breakdowns ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE budget_category_breakdowns FORCE ROW LEVEL SECURITY")
    op.execute("""
        CREATE POLICY tenant_isolation_budget_category_breakdowns
        ON budget_category_breakdowns
        USING (company_id = current_setting('app.current_company_id')::uuid)
    """)
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON budget_category_breakdowns TO appuser")

    # -------------------------------------------------------------------
    # 8. Backfill existing companies' project_manager rows with the three
    #    finance.* keys. company_role_permissions has FORCE RLS (since 0027)
    #    and appuser is NOBYPASSRLS, so loop per-company with tenant context.
    # -------------------------------------------------------------------
    conn = op.get_bind()
    company_ids = conn.exec_driver_sql("SELECT id FROM companies").scalars().all()
    for company_id in company_ids:
        conn.exec_driver_sql(f"SET LOCAL app.current_company_id = '{company_id}'")
        conn.exec_driver_sql(
            "UPDATE company_role_permissions "
            f"SET permissions = permissions || {_FINANCE_PERMISSION_KEYS}, "
            "updated_at = now() "
            "WHERE role = 'project_manager' "
            "AND NOT (permissions @> '[\"finance.view\"]'::jsonb)"
        )


def downgrade() -> None:
    # Reverse the project_manager finance-key backfill (best effort).
    conn = op.get_bind()
    company_ids = conn.exec_driver_sql("SELECT id FROM companies").scalars().all()
    for company_id in company_ids:
        conn.exec_driver_sql(f"SET LOCAL app.current_company_id = '{company_id}'")
        conn.exec_driver_sql(
            "UPDATE company_role_permissions "
            "SET permissions = (permissions - 'finance.view' - 'finance.manage' "
            "- 'finance.rates.manage'), "
            "updated_at = now() "
            "WHERE role = 'project_manager'"
        )

    # Drop the five tables in FK-safe order.
    for table in _FINANCE_TABLES:
        op.execute(f"DROP TABLE IF EXISTS {table} CASCADE")
