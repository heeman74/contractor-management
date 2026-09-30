"""grant company.settings.manage to existing admin roles

Revision ID: 0045_admin_company_settings
Revises: 0044_quote_client
Create Date: 2026-09-30

The key governing company details was reserved for `owner`. No code path ever
assigns that role — registration and the provisioning script both create an
admin — so the permission was held by nobody and the company profile could not
be edited by anyone who actually existed.

The default matrix now gives it to admin, but defaults only apply to a role with
no stored row, and every company is seeded with a full set at creation. So
existing companies need the key added to the row they already have.

Rows that already carry it are left alone, and no other role is touched:
company.billing.manage stays with the owner, since it concerns the subscription
rather than the business.
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0045_admin_company_settings"
down_revision: str | None = "0044_quote_client"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_KEY = "company.settings.manage"


def upgrade() -> None:
    # Per company, with the tenant context set each time. company_role_permissions
    # enforces row level security through a policy that reads
    # current_setting('app.current_company_id') WITHOUT the missing_ok argument,
    # so a plain UPDATE during a migration fails outright rather than matching
    # nothing. Companies carry no such policy, which is what makes them safe to
    # iterate here.
    op.execute(
        f"""
        DO $$
        DECLARE target record;
        BEGIN
            FOR target IN SELECT id FROM companies LOOP
                PERFORM set_config('app.current_company_id', target.id::text, true);
                UPDATE company_role_permissions
                SET permissions = permissions || '["{_KEY}"]'::jsonb
                WHERE role = 'admin'
                  AND company_id = target.id
                  AND NOT (permissions @> '["{_KEY}"]'::jsonb)
                  AND NOT (permissions @> '["*"]'::jsonb);
            END LOOP;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute(
        f"""
        DO $$
        DECLARE target record;
        BEGIN
            FOR target IN SELECT id FROM companies LOOP
                PERFORM set_config('app.current_company_id', target.id::text, true);
                UPDATE company_role_permissions
                SET permissions = permissions - '{_KEY}'
                WHERE role = 'admin' AND company_id = target.id;
            END LOOP;
        END $$;
        """
    )
