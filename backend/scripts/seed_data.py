"""Seed data script — creates demo companies, users, and roles for development.

Creates two demo companies to demonstrate multi-tenant isolation:
  1. Ace Plumbing & Electrical — admin, 2 contractors (plumber + electrician), 1 client
  2. BuildRight Construction — admin, 1 contractor

Both companies use the X-Company-Id tenant isolation pattern — data from one company
is never visible when querying with the other company's ID.

Usage:
  python -m scripts.seed_data
  docker compose exec backend python -m scripts.seed_data

The script is IDEMPOTENT — it checks if seed data exists before inserting.
Running it multiple times is safe. If a company with the seed name already exists,
the entire seed for that company is skipped.
"""

import asyncio
import os
import sys

# Allow running as a module from the backend directory
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

# ---------------------------------------------------------------------------
# Database connection
# ---------------------------------------------------------------------------

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub",
)

# ---------------------------------------------------------------------------
# Seed company definitions
# ---------------------------------------------------------------------------

ACE_COMPANY = {
    "name": "Ace Plumbing & Electrical",
    "address": "123 Trades Street, Melbourne VIC 3000",
    "phone": "+61 3 9000 0001",
    "business_number": "ACN 123 456 789",
    "trade_types": ["plumber", "electrician"],
}

ACE_USERS = [
    {
        "email": "admin@ace.com",
        "first_name": "Sarah",
        "last_name": "Mitchell",
        "phone": "+61 400 001 001",
        "role": "admin",
    },
    {
        "email": "john@ace.com",
        "first_name": "John",
        "last_name": "Cooper",
        "phone": "+61 400 001 002",
        "role": "contractor",
    },
    {
        "email": "jane@ace.com",
        "first_name": "Jane",
        "last_name": "Walsh",
        "phone": "+61 400 001 003",
        "role": "contractor",
    },
    {
        "email": "client@example.com",
        "first_name": "Alex",
        "last_name": "Thompson",
        "phone": "+61 400 001 004",
        "role": "client",
    },
]

BUILDRIGHT_COMPANY = {
    "name": "BuildRight Construction",
    "address": "456 Builder Lane, Sydney NSW 2000",
    "phone": "+61 2 9000 0002",
    "business_number": "ACN 987 654 321",
    "trade_types": ["builder", "concreter"],
}

BUILDRIGHT_USERS = [
    {
        "email": "admin@buildright.com",
        "first_name": "Marcus",
        "last_name": "Rivera",
        "phone": "+61 400 002 001",
        "role": "admin",
    },
    {
        "email": "contractor@buildright.com",
        "first_name": "Priya",
        "last_name": "Sharma",
        "phone": "+61 400 002 002",
        "role": "contractor",
    },
]

# ---------------------------------------------------------------------------
# Seeding logic
# ---------------------------------------------------------------------------


async def _company_exists(session: AsyncSession, name: str) -> bool:
    """Check if a company with the given name already exists."""
    # Import here to avoid circular import at module level
    from app.features.companies.models import Company

    result = await session.execute(select(Company).where(Company.name == name))
    return result.scalar_one_or_none() is not None


async def _seed_company(
    session: AsyncSession,
    company_data: dict,
    users: list[dict],
    verbose: bool = True,
) -> None:
    """Seed a single company with its users and roles.

    Uses raw SQL inserts to bypass RLS (seeding is a privileged operation).
    """
    from app.features.companies.models import Company
    from app.features.users.models import User, UserRole

    company_name = company_data["name"]

    # Check idempotency
    if await _company_exists(session, company_name):
        if verbose:
            print(f"  [SKIP] {company_name} already exists — skipping")
        return

    # Create company
    company = Company(**company_data)
    session.add(company)
    await session.flush()  # Get the auto-generated UUID
    await session.refresh(company)

    if verbose:
        print(f"  [OK] Created company: {company.name} (id={company.id})")

    # Create users and assign roles
    for user_data in users:
        role = user_data.pop("role")  # Remove role from user data

        # Set RLS context for this company so user.company_id is correct
        await session.execute(
            text("SET LOCAL app.current_company_id = :cid"),
            {"cid": str(company.id)},
        )

        user = User(company_id=company.id, **user_data)
        session.add(user)
        await session.flush()
        await session.refresh(user)

        user_role = UserRole(
            user_id=user.id,
            company_id=company.id,
            role=role,
        )
        session.add(user_role)
        await session.flush()

        user_data["role"] = role  # Restore for reporting
        if verbose:
            print(f"    [OK] Created user: {user.email} (role={role})")

    if verbose:
        print(f"  [OK] {company_name} seeded successfully\n")


async def seed_data(verbose: bool = True) -> None:
    """Main seed function — creates demo companies and users.

    Idempotent: checks existence before inserting. Safe to run multiple times.
    """
    engine = create_async_engine(DATABASE_URL, echo=False)
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    if verbose:
        print("ContractorHub Seed Data")
        print("=" * 50)
        print(f"Database: {DATABASE_URL.split('@')[-1]}\n")  # Hide credentials

    async with session_factory() as session:
        # Seed Ace Plumbing & Electrical
        if verbose:
            print("Seeding: Ace Plumbing & Electrical")
        await _seed_company(
            session,
            ACE_COMPANY.copy(),
            [u.copy() for u in ACE_USERS],
            verbose=verbose,
        )

        # Seed BuildRight Construction
        if verbose:
            print("Seeding: BuildRight Construction")
        await _seed_company(
            session,
            BUILDRIGHT_COMPANY.copy(),
            [u.copy() for u in BUILDRIGHT_USERS],
            verbose=verbose,
        )

        await session.commit()

    await engine.dispose()

    if verbose:
        print("=" * 50)
        print("Seed data complete!")
        print()
        print("To test multi-tenant isolation:")
        print("  curl -H 'X-Company-Id: <ace_id>' http://localhost:8000/api/v1/users/")
        print("  curl -H 'X-Company-Id: <buildright_id>' http://localhost:8000/api/v1/users/")
        print()
        print("Each company's users are only visible with their own X-Company-Id header.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(seed_data())
