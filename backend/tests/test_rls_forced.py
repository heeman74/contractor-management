"""Every RLS-enabled table must also FORCE RLS.

ENABLE ROW LEVEL SECURITY exempts the table owner from its own policies. The
application connects as the same role that runs migrations and therefore owns
every table, so an ENABLEd-but-not-FORCEd table silently serves rows from all
companies. This guards the invariant for tables added later.
"""

import pytest
from sqlalchemy import text

QUERY = text(
    """
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity
      AND NOT c.relforcerowsecurity
    ORDER BY c.relname
    """
)


@pytest.mark.asyncio
async def test_every_rls_table_is_forced(test_engine):
    async with test_engine.connect() as conn:
        result = await conn.execute(QUERY)
        unforced = [row[0] for row in result]

    assert unforced == [], (
        "These tables ENABLE row level security but do not FORCE it, so the "
        "owning role (which the app connects as) bypasses tenant isolation "
        f"entirely: {', '.join(unforced)}. Add "
        "'ALTER TABLE <t> FORCE ROW LEVEL SECURITY' in a migration."
    )
