"""Provisioning CLI — create a company with an admin user, and add users with roles.

Why a script (not an API call): the first company + admin is a bootstrapping
problem. Every data endpoint requires an authenticated, RLS-scoped user, and the
`/auth/register` endpoint is rate-limited and public-facing. Provisioning talks to
the database directly, reusing the app's own auth logic.

TARGET DATABASE
  This uses `settings.database_url` — the same env-driven URL the app uses, with
  NO hardcoded default. So it provisions whatever DATABASE_URL points at:
    - dev:  DATABASE_URL=...localhost.../contractorhub
    - prod: export your production env (or DATABASE_URL=...) before running.
  Apply migrations to that database first: `alembic upgrade head`.

USAGE
  python -m scripts.provision create-company \
      --name "Acme Trades" --admin-email admin@acme.com \
      --admin-first Ada --admin-last Lovelace [--password ...] [--phone ...]

  python -m scripts.provision add-user \
      --company "Acme Trades" --email jo@acme.com --role contractor \
      --first Jo --last Bloggs [--password ...] [--phone ...]

  python -m scripts.provision list-companies

Passwords: pass --password for automation, or omit it to be prompted securely
(never echoed). Minimum 8 characters, matching the API's Field(min_length=8).
"""

import argparse
import asyncio
import os
import sys
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from getpass import getpass

# Allow running as a module from the backend directory.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings
from app.core.security import hash_password
from app.core.tenant import set_current_tenant_id
from app.features.auth.service import AuthService
from app.features.companies.models import Company
from app.features.users.models import User, UserRole

MIN_PASSWORD_LENGTH = 8
VALID_ROLES = (
    "owner",
    "admin",
    "project_manager",
    "gc",
    "foreman",
    "contractor",
    "worker",
    "client",
)


@asynccontextmanager
async def _db_session() -> AsyncIterator[AsyncSession]:
    """Yield a session bound to the configured (env-driven) database, disposing the
    engine on exit so short-lived script runs don't leak connections."""
    engine = create_async_engine(settings.database_url, echo=False)
    factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    try:
        async with factory() as session:
            yield session
    finally:
        await engine.dispose()


def _resolve_password(provided: str | None, label: str) -> str:
    """Return a validated password from the flag, or prompt for one securely."""
    password = provided
    if password is None:
        password = getpass(f"{label} password: ")
        confirm = getpass(f"{label} password (confirm): ")
        if password != confirm:
            sys.exit("Error: passwords do not match.")
    if len(password) < MIN_PASSWORD_LENGTH:
        sys.exit(f"Error: password must be at least {MIN_PASSWORD_LENGTH} characters.")
    return password


async def _set_tenant_context(session: AsyncSession, company_id: uuid.UUID) -> None:
    """Set the RLS tenant context so inserts into tenant-scoped tables are allowed.

    asyncpg does not support parameterized SET; company_id is a UUID we control
    (never user input), so string interpolation is safe here.
    """
    set_current_tenant_id(company_id)
    await session.execute(text(f"SET LOCAL app.current_company_id = '{company_id}'"))


async def _find_company(session: AsyncSession, identifier: str) -> Company | None:
    """Resolve a company by UUID or by exact name."""
    try:
        company_uuid = uuid.UUID(identifier)
        return await session.get(Company, company_uuid)
    except ValueError:
        result = await session.execute(select(Company).where(Company.name == identifier))
        return result.scalar_one_or_none()


async def create_company(args: argparse.Namespace) -> None:
    password = _resolve_password(args.password, "Admin")

    async with _db_session() as session:
        svc = AuthService(session)
        try:
            # Reuses the exact registration path: company + hashed-password admin
            # + admin role, all in one transaction.
            result = await svc.register(
                email=args.admin_email,
                password=password,
                company_name=args.name,
                first_name=args.admin_first,
                last_name=args.admin_last,
            )
        except ValueError as exc:
            await session.rollback()
            sys.exit(f"Error: {exc}")

        # register() does not set the admin's phone — apply it if provided.
        if args.phone:
            await session.execute(
                text("UPDATE users SET phone = :phone WHERE id = :uid"),
                {"phone": args.phone, "uid": str(result["user_id"])},
            )

        await session.commit()

    print("Created company + admin:")
    print(f"  company_id : {result['company_id']}")
    print(f"  admin_email: {args.admin_email}")
    print(f"  admin_id   : {result['user_id']}")
    print(f"  roles      : {result['roles']}")
    print("\nThe admin can now sign in with these credentials.")


async def add_user(args: argparse.Namespace) -> None:
    password = _resolve_password(args.password, "User")

    async with _db_session() as session:
        company = await _find_company(session, args.company)
        if company is None:
            sys.exit(f"Error: no company found matching '{args.company}'.")

        # Email is globally unique — check up front for a clear message.
        existing = await session.execute(select(User).where(User.email == args.email))
        if existing.scalars().first() is not None:
            sys.exit(f"Error: a user with email '{args.email}' already exists.")

        await _set_tenant_context(session, company.id)

        user = User(
            id=uuid.uuid4(),
            company_id=company.id,
            email=args.email,
            password_hash=hash_password(password),
            first_name=args.first,
            last_name=args.last,
            phone=args.phone,
        )
        session.add(user)
        await session.flush()

        session.add(
            UserRole(
                id=uuid.uuid4(),
                user_id=user.id,
                company_id=company.id,
                role=args.role,
            )
        )
        await session.commit()

    print("Added user:")
    print(f"  company    : {company.name} ({company.id})")
    print(f"  email      : {args.email}")
    print(f"  user_id    : {user.id}")
    print(f"  role       : {args.role}")
    print("\nThe user can now sign in with these credentials.")


async def set_password(args: argparse.Namespace) -> None:
    password = _resolve_password(args.password, "New")

    async with _db_session() as session:
        result = await session.execute(select(User).where(User.email == args.email))
        user = result.scalars().first()
        if user is None:
            sys.exit(f"Error: no user found with email '{args.email}'.")

        # Set the user's own company as tenant context so the RLS UPDATE passes.
        await _set_tenant_context(session, user.company_id)
        await session.execute(
            text("UPDATE users SET password_hash = :hash WHERE id = :uid"),
            {"hash": hash_password(password), "uid": str(user.id)},
        )
        await session.commit()

    print(f"Password updated for {args.email}. They can now sign in with it.")


async def list_companies(_args: argparse.Namespace) -> None:
    async with _db_session() as session:
        result = await session.execute(select(Company).order_by(Company.name))
        companies = result.scalars().all()

    if not companies:
        print("No companies exist yet. Create one with `create-company`.")
        return
    print(f"{'COMPANY ID':38}  NAME")
    for company in companies:
        print(f"{company.id!s:38}  {company.name}")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="provision",
        description="Provision companies and users (bootstrapping / admin utility).",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create-company", help="Create a company with an admin user.")
    create.add_argument("--name", required=True, help="Company name.")
    create.add_argument("--admin-email", required=True, help="Admin login email.")
    create.add_argument("--admin-first", help="Admin first name.")
    create.add_argument("--admin-last", help="Admin last name.")
    create.add_argument("--phone", help="Admin phone (optional).")
    create.add_argument("--password", help="Admin password. Omit to be prompted securely.")
    create.set_defaults(func=create_company)

    add = sub.add_parser("add-user", help="Add a user with a role to an existing company.")
    add.add_argument("--company", required=True, help="Target company: UUID or exact name.")
    add.add_argument("--email", required=True, help="User login email (globally unique).")
    add.add_argument("--role", required=True, choices=VALID_ROLES, help="Role in the company.")
    add.add_argument("--first", help="First name.")
    add.add_argument("--last", help="Last name.")
    add.add_argument("--phone", help="Phone (optional).")
    add.add_argument("--password", help="User password. Omit to be prompted securely.")
    add.set_defaults(func=add_user)

    setpw = sub.add_parser("set-password", help="Set or reset a user's login password by email.")
    setpw.add_argument("--email", required=True, help="The user's login email.")
    setpw.add_argument("--password", help="New password. Omit to be prompted securely.")
    setpw.set_defaults(func=set_password)

    listing = sub.add_parser("list-companies", help="List all companies with their IDs.")
    listing.set_defaults(func=list_companies)

    return parser


def main() -> None:
    args = _build_parser().parse_args()
    asyncio.run(args.func(args))


if __name__ == "__main__":
    main()
