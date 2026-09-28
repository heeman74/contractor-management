"""No column default may be a doubly-quoted string literal.

server_default="'medium'" renders as '''medium''' because SQLAlchemy quotes a
plain string itself. The stored default then carries literal apostrophes,
violates the column's CHECK constraint, and every INSERT that omits the column
fails. Four columns shipped this way; this keeps the fifth from doing so.
"""

import pytest
from sqlalchemy import text

QUERY = text(
    """
    SELECT table_name, column_name, column_default
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_default LIKE '%''''%'
    ORDER BY table_name, column_name
    """
)


@pytest.mark.asyncio
async def test_no_overquoted_column_defaults(test_engine):
    async with test_engine.connect() as conn:
        result = await conn.execute(QUERY)
        offenders = [f"{t}.{c} = {d}" for t, c, d in result]

    assert offenders == [], (
        "These column defaults are quoted twice, so the stored default "
        "includes literal apostrophes and will violate any CHECK constraint "
        f'on the column: {"; ".join(offenders)}. Use server_default="medium", '
        "not server_default=\"'medium'\"."
    )
