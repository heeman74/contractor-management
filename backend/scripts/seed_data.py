"""Seed data script — creates demo companies, users, and roles for development.

Creates two demo companies to demonstrate multi-tenant isolation:
  1. Ace Plumbing & Electrical — admin, 2 contractors (plumber + electrician), 1 client
  2. BuildRight Construction — admin, 1 contractor

Phase 4 additions:
  - Job sites (service locations)
  - Jobs at every lifecycle stage: quote, scheduled, in_progress, complete, invoiced, cancelled
  - Client profiles with CRM fields
  - Client saved properties linking clients to job sites
  - Job requests in pending, accepted, and declined states
  - Ratings (admin_to_client and client_to_company directions)

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
from datetime import UTC, date, datetime, timedelta

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
# Seeding logic — Phase 1-3
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

        # Set RLS context for this company so user.company_id is correct.
        # asyncpg does not support parameterized SET commands — use string formatting.
        # This is safe because company.id is a UUID generated by PostgreSQL, never user input.
        await session.execute(
            text(f"SET LOCAL app.current_company_id = '{company.id}'"),
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


# ---------------------------------------------------------------------------
# Phase 4 seed helpers
# ---------------------------------------------------------------------------


async def _phase4_data_exists(session: AsyncSession, company_id) -> bool:
    """Check if Phase 4 seed data already exists for this company.

    Checks both jobs and job_sites — tests truncate jobs but not necessarily
    job_sites, and job_sites exist only after Phase 4 seeding.
    """
    jobs_result = await session.execute(
        text("SELECT COUNT(*) FROM jobs WHERE company_id = :cid"),
        {"cid": str(company_id)},
    )
    job_count = jobs_result.scalar_one()

    sites_result = await session.execute(
        text("SELECT COUNT(*) FROM job_sites WHERE company_id = :cid"),
        {"cid": str(company_id)},
    )
    site_count = sites_result.scalar_one()

    profiles_result = await session.execute(
        text("SELECT COUNT(*) FROM client_profiles WHERE company_id = :cid"),
        {"cid": str(company_id)},
    )
    profile_count = profiles_result.scalar_one()

    return (job_count + site_count + profile_count) > 0


async def _get_company_by_name(session: AsyncSession, name: str):
    """Return the Company object for a given name, or None."""
    from app.features.companies.models import Company

    result = await session.execute(select(Company).where(Company.name == name))
    return result.scalar_one_or_none()


async def _get_user_by_email(session: AsyncSession, email: str):
    """Return the User object for a given email, or None."""
    from app.features.users.models import User

    result = await session.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


def _make_status_history(*entries: tuple) -> list[dict]:
    """Build a status_history list from (status, days_ago) tuples.

    Each entry becomes: {"status": s, "timestamp": ISO-8601, "user_id": None}
    """
    history = []
    for status, days_ago in entries:
        ts = (datetime.now(UTC) - timedelta(days=days_ago)).isoformat()
        history.append({"status": status, "timestamp": ts, "user_id": None})
    return history


async def _seed_phase4_ace(session: AsyncSession, verbose: bool = True) -> None:
    """Seed Phase 4 demo data for Ace Plumbing & Electrical.

    Creates:
    - 2 job sites (service locations)
    - Client profile for Alex Thompson
    - Saved property linking Alex to a job site
    - 8 jobs at every lifecycle stage
    - 4 job requests (2 pending, 1 accepted, 1 declined)
    - 2 ratings on the completed/invoiced jobs
    """
    import json
    import uuid

    from app.features.jobs.models import ClientProfile, ClientProperty, Job, JobRequest, Rating
    from app.features.scheduling.models import JobSite

    ace = await _get_company_by_name(session, "Ace Plumbing & Electrical")
    if ace is None:
        if verbose:
            print("  [SKIP] Ace company not found — cannot seed Phase 4 data")
        return

    # Set RLS context BEFORE the idempotency check — without it, RLS hides the
    # existing rows from our SELECT COUNT queries, making the check always return False.
    # asyncpg does not support parameterized SET commands — use string formatting.
    # ace.id is a UUID from PostgreSQL, never user input — safe to format directly.
    await session.execute(
        text(f"SET LOCAL app.current_company_id = '{ace.id}'"),
    )

    if await _phase4_data_exists(session, ace.id):
        if verbose:
            print("  [SKIP] Ace Phase 4 data already exists — skipping")
        return

    # Retrieve seed users
    admin = await _get_user_by_email(session, "admin@ace.com")
    contractor_john = await _get_user_by_email(session, "john@ace.com")
    contractor_jane = await _get_user_by_email(session, "jane@ace.com")
    client_alex = await _get_user_by_email(session, "client@example.com")

    # ------------------------------------------------------------------
    # Job Sites
    # ------------------------------------------------------------------
    site_home = JobSite(
        company_id=ace.id,
        address="42 Maple Drive, Hawthorn VIC 3122",
        latitude="-37.823456",
        longitude="145.034567",
        name="Alex Thompson Home",
    )
    site_office = JobSite(
        company_id=ace.id,
        address="88 Collins Street, Melbourne VIC 3000",
        latitude="-37.813456",
        longitude="144.969234",
        name="CBD Office Block",
    )
    session.add_all([site_home, site_office])
    await session.flush()
    await session.refresh(site_home)
    await session.refresh(site_office)
    if verbose:
        print(f"    [OK] Created job sites: {site_home.name}, {site_office.name}")

    # ------------------------------------------------------------------
    # Client Profile for Alex Thompson
    # ------------------------------------------------------------------
    client_profile = ClientProfile(
        company_id=ace.id,
        user_id=client_alex.id,
        billing_address="42 Maple Drive, Hawthorn VIC 3122",
        tags=["residential", "repeat-customer"],
        admin_notes="Long-term client. Prefers morning appointments.",
        referral_source="word-of-mouth",
        preferred_contractor_id=contractor_john.id,
        preferred_contact_method="phone",
    )
    session.add(client_profile)
    await session.flush()
    if verbose:
        print(f"    [OK] Created client profile for {client_alex.email}")

    # ------------------------------------------------------------------
    # Saved property — Alex's home site
    # ------------------------------------------------------------------
    saved_property = ClientProperty(
        company_id=ace.id,
        client_id=client_alex.id,
        job_site_id=site_home.id,
        nickname="Home",
        is_default=True,
    )
    session.add(saved_property)
    await session.flush()
    if verbose:
        print("    [OK] Created saved property for Alex (Home)")

    # ------------------------------------------------------------------
    # Jobs at every lifecycle stage
    # ------------------------------------------------------------------
    today = date.today()

    # 1. Quote stage — new request for plumbing
    job_quote_1 = Job(
        company_id=ace.id,
        description="Replace burst kitchen water pipe — urgent repair needed",
        trade_type="plumber",
        status="quote",
        status_history=_make_status_history(("quote", 2)),
        priority="urgent",
        client_id=client_alex.id,
        contractor_id=contractor_john.id,
        notes="Client reports flooding under sink.",
    )

    # 2. Quote stage — electrical quote
    job_quote_2 = Job(
        company_id=ace.id,
        description="Install 3-phase power for new workshop",
        trade_type="electrician",
        status="quote",
        status_history=_make_status_history(("quote", 1)),
        priority="medium",
        client_id=client_alex.id,
        contractor_id=contractor_jane.id,
    )

    # 3. Scheduled
    job_scheduled = Job(
        company_id=ace.id,
        description="Annual hot water system inspection and service",
        trade_type="plumber",
        status="scheduled",
        status_history=_make_status_history(("quote", 7), ("scheduled", 5)),
        priority="low",
        client_id=client_alex.id,
        contractor_id=contractor_john.id,
        scheduled_completion_date=today + timedelta(days=3),
        estimated_duration_minutes=120,
    )

    # 4. Scheduled — electrical
    job_scheduled_2 = Job(
        company_id=ace.id,
        description="Install additional power outlets in home office",
        trade_type="electrician",
        status="scheduled",
        status_history=_make_status_history(("quote", 10), ("scheduled", 8)),
        priority="medium",
        client_id=client_alex.id,
        contractor_id=contractor_jane.id,
        scheduled_completion_date=today + timedelta(days=5),
        estimated_duration_minutes=90,
    )

    # 5. In progress
    job_in_progress = Job(
        company_id=ace.id,
        description="Replace all bathroom fixtures and re-pipe hot water",
        trade_type="plumber",
        status="in_progress",
        status_history=_make_status_history(
            ("quote", 14), ("scheduled", 12), ("in_progress", 1)
        ),
        priority="high",
        client_id=client_alex.id,
        contractor_id=contractor_john.id,
        estimated_duration_minutes=480,
    )

    # 6. Complete (eligible for ratings)
    job_complete = Job(
        company_id=ace.id,
        description="Fix faulty safety switches and update switchboard",
        trade_type="electrician",
        status="complete",
        status_history=_make_status_history(
            ("quote", 30),
            ("scheduled", 25),
            ("in_progress", 20),
            ("complete", 3),
        ),
        priority="high",
        client_id=client_alex.id,
        contractor_id=contractor_jane.id,
    )

    # 7. Invoiced
    job_invoiced = Job(
        company_id=ace.id,
        description="New hot water system installation — gas to electric conversion",
        trade_type="plumber",
        status="invoiced",
        status_history=_make_status_history(
            ("quote", 60),
            ("scheduled", 55),
            ("in_progress", 50),
            ("complete", 45),
            ("invoiced", 40),
        ),
        priority="medium",
        client_id=client_alex.id,
        contractor_id=contractor_john.id,
        purchase_order_number="PO-2025-001",
        external_reference="INV-ACE-10042",
    )

    # 8. Cancelled
    job_cancelled = Job(
        company_id=ace.id,
        description="Install ducted air conditioning system (cancelled — client relocated)",
        trade_type="electrician",
        status="cancelled",
        status_history=_make_status_history(
            ("quote", 20), ("scheduled", 18), ("cancelled", 15)
        ),
        priority="low",
        client_id=client_alex.id,
        contractor_id=contractor_jane.id,
        notes="Client relocated interstate. Refund processed.",
    )

    all_jobs = [
        job_quote_1, job_quote_2, job_scheduled, job_scheduled_2,
        job_in_progress, job_complete, job_invoiced, job_cancelled,
    ]
    session.add_all(all_jobs)
    await session.flush()
    for j in all_jobs:
        await session.refresh(j)
    if verbose:
        print(f"    [OK] Created {len(all_jobs)} jobs (all lifecycle stages)")

    # ------------------------------------------------------------------
    # Job Requests
    # ------------------------------------------------------------------

    # 1. Pending — anonymous web form submission
    req_pending_1 = JobRequest(
        company_id=ace.id,
        description="Leaking pipe under kitchen sink — water damage starting",
        trade_type="plumber",
        urgency="urgent",
        status="pending",
        submitted_name="Maria Santos",
        submitted_email="maria.santos@email.com",
        submitted_phone="+61 400 999 111",
    )

    # 2. Pending — in-app submission from authenticated client
    req_pending_2 = JobRequest(
        company_id=ace.id,
        description="Install ceiling fan in master bedroom",
        trade_type="electrician",
        urgency="normal",
        status="pending",
        client_id=client_alex.id,
    )

    # 3. Accepted — converted to a job (links to job_invoiced)
    req_accepted = JobRequest(
        company_id=ace.id,
        description="New hot water system installation — gas to electric conversion",
        trade_type="plumber",
        urgency="normal",
        status="accepted",
        client_id=client_alex.id,
        converted_job_id=job_invoiced.id,
    )

    # 4. Declined — outside service area
    req_declined = JobRequest(
        company_id=ace.id,
        description="Full electrical rewire for heritage property",
        trade_type="electrician",
        urgency="normal",
        status="declined",
        decline_reason="Outside service area",
        decline_message="We don't currently service your postcode. We recommend contacting a local electrician.",
        submitted_name="Tom Nguyen",
        submitted_email="tom.nguyen@email.com",
    )

    all_requests = [req_pending_1, req_pending_2, req_accepted, req_declined]
    session.add_all(all_requests)
    await session.flush()
    if verbose:
        print(
            f"    [OK] Created {len(all_requests)} job requests "
            "(2 pending, 1 accepted, 1 declined)"
        )

    # ------------------------------------------------------------------
    # Ratings on completed/invoiced jobs
    # ------------------------------------------------------------------

    # Admin rates client on the complete job
    rating_admin_to_client = Rating(
        company_id=ace.id,
        job_id=job_complete.id,
        rater_id=admin.id,
        ratee_id=client_alex.id,
        direction="admin_to_client",
        stars=5,
        review_text="Alex was an excellent client — clear communication and prompt payment.",
    )

    # Client rates company on the invoiced job
    rating_client_to_company = Rating(
        company_id=ace.id,
        job_id=job_invoiced.id,
        rater_id=client_alex.id,
        ratee_id=contractor_john.id,
        direction="client_to_company",
        stars=4,
        review_text="Great work overall. John was professional and tidy. Slight delay in start time.",
    )

    session.add_all([rating_admin_to_client, rating_client_to_company])
    await session.flush()
    if verbose:
        print("    [OK] Created 2 ratings (admin_to_client: 5 stars, client_to_company: 4 stars)")

    # Update client profile average rating (denormalized)
    # Average of ratings WHERE ratee_id = client_alex.id
    # Only rating_admin_to_client has ratee_id=client_alex: avg = 5.00
    client_profile.average_rating = "5.00"
    await session.flush()
    if verbose:
        print("    [OK] Updated Alex's average_rating to 5.00")
        print("  [OK] Ace Phase 4 data seeded successfully\n")


# ---------------------------------------------------------------------------
# Main seed function
# ---------------------------------------------------------------------------


async def seed_data(verbose: bool = True) -> None:
    """Main seed function — creates demo companies, users, and Phase 4 job data.

    Idempotent: checks existence before inserting. Safe to run multiple times.
    """
    engine = create_async_engine(DATABASE_URL, echo=False)
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    if verbose:
        print("ContractorHub Seed Data")
        print("=" * 50)
        print(f"Database: {DATABASE_URL.split('@')[-1]}\n")  # Hide credentials

    async with session_factory() as session:
        # Seed Ace Plumbing & Electrical (Phase 1-3)
        if verbose:
            print("Seeding: Ace Plumbing & Electrical")
        await _seed_company(
            session,
            ACE_COMPANY.copy(),
            [u.copy() for u in ACE_USERS],
            verbose=verbose,
        )

        # Seed BuildRight Construction (Phase 1-3)
        if verbose:
            print("Seeding: BuildRight Construction")
        await _seed_company(
            session,
            BUILDRIGHT_COMPANY.copy(),
            [u.copy() for u in BUILDRIGHT_USERS],
            verbose=verbose,
        )

        # Seed Phase 4 job lifecycle data for Ace
        if verbose:
            print("Seeding: Phase 4 job lifecycle data (Ace Plumbing & Electrical)")
        await _seed_phase4_ace(session, verbose=verbose)

        await session.commit()

    await engine.dispose()

    if verbose:
        print("=" * 50)
        print("Seed data complete!")
        print()
        print("Phase 4 demo data:")
        print("  - 8 jobs at every lifecycle stage (quote -> invoiced + cancelled)")
        print("  - 4 job requests (2 pending, 1 accepted, 1 declined)")
        print("  - Client profile with saved property and average rating")
        print("  - 2 ratings (admin_to_client: 5 stars, client_to_company: 4 stars)")
        print()
        print("To test multi-tenant isolation:")
        print("  curl -H 'X-Company-Id: <ace_id>' http://localhost:8000/api/v1/users/")
        print("  curl -H 'X-Company-Id: <buildright_id>' http://localhost:8000/api/v1/users/")
        print()
        print("Each company's data is only visible with their own X-Company-Id header.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(seed_data())
