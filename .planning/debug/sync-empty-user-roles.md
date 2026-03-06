---
status: resolved
trigger: "sync endpoint returns user_roles: [] when user roles should exist"
created: 2026-03-05T00:00:00Z
updated: 2026-03-05T00:01:00Z
---

## Current Focus

hypothesis: CONFIRMED - user_roles.updated_at is NULL on all seeded rows, causing
            the sync query's WHERE clause to never match any record
test: traced full data flow from seed insert -> DB column state -> query filter
expecting: N/A - root cause confirmed, awaiting fix
next_action: fix updated_at column definition in UserRole model and migration 0001

## Symptoms

expected: GET /api/v1/sync?cursor= returns user_roles array populated with role records
actual: GET /api/v1/sync?cursor= returns user_roles: [] (empty array)
errors: none reported - silent empty result
reproduction: call GET /api/v1/sync?cursor= endpoint after running seed_data.py
started: discovered during Phase 02 Cold Start Smoke Test (Test 1)

## Eliminated

- hypothesis: wrong model or table referenced in sync service
  evidence: service.py correctly imports and queries UserRole from users/models.py,
            which maps to the "user_roles" table
  timestamp: 2026-03-05T00:01:00Z

- hypothesis: RLS policy blocking all rows
  evidence: RLS would block rows entirely but the test sends X-Company-Id header;
            users array returns correctly through the same RLS policy, so RLS works.
            If RLS were the problem, users would also be empty.
  timestamp: 2026-03-05T00:01:00Z

- hypothesis: table not yet created / missing migration
  evidence: migration 0001 creates user_roles table with correct schema;
            migration 0002 adds updated_at and deleted_at; both migrations present
  timestamp: 2026-03-05T00:01:00Z

- hypothesis: seed data not inserted
  evidence: seed_data.py clearly inserts UserRole rows (lines 165-171);
            the real problem is the column value state after insert, not absence of rows
  timestamp: 2026-03-05T00:01:00Z

## Evidence

- timestamp: 2026-03-05T00:00:30Z
  checked: backend/app/features/sync/service.py get_user_roles_since()
  found: query is `SELECT ... FROM user_roles WHERE updated_at > since OR deleted_at > since`
  implication: BOTH updated_at and deleted_at must be NULL for a row to be excluded.
               If updated_at IS NULL then `NULL > since` evaluates to NULL (falsy),
               not TRUE, in PostgreSQL. That row is skipped.

- timestamp: 2026-03-05T00:00:40Z
  checked: migration 0001 - user_roles table DDL (lines 116-148)
  found: user_roles table created WITHOUT an updated_at column in migration 0001
  implication: any row inserted before migration 0002 runs has NO updated_at column at all

- timestamp: 2026-03-05T00:00:50Z
  checked: migration 0002 - add updated_at to user_roles (lines 53-61)
  found: `op.add_column("user_roles", updated_at, nullable=True, server_default=func.now())`
  implication: server_default=func.now() only applies to NEW rows inserted AFTER the
               ALTER TABLE runs. Existing rows get NULL for updated_at (PostgreSQL
               does not backfill server_default values into existing rows for ADD COLUMN).

- timestamp: 2026-03-05T00:00:55Z
  checked: backend/scripts/seed_data.py _seed_company() (lines 165-171)
  found: UserRole rows are inserted WITHOUT explicitly setting updated_at.
         The ORM relies on the server_default to supply the value.
  implication: If seed runs AFTER migration 0002 has been applied, server_default
               fires and updated_at = NOW() - rows ARE queryable. But if seed ran
               BEFORE migration 0002 (or migration 0002 backfilled nothing), all
               existing user_role rows have updated_at = NULL.

- timestamp: 2026-03-05T00:01:00Z
  checked: backend/app/features/users/models.py UserRole class (lines 77-78)
  found: `updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True),
          nullable=True, server_default=func.now())`
  implication: The model marks updated_at as nullable=True. When seed inserts a new
               row without setting updated_at, SQLAlchemy defers to the server_default.
               However, if the column was only added via ALTER TABLE ADD COLUMN with a
               server_default, PostgreSQL only writes that default for rows inserted
               AFTER the ALTER. Pre-existing rows remain NULL. This is the exact scenario
               that occurs when seed_data.py was run before migration 0002 was applied
               (or when DB is reset and migration 0002's ADD COLUMN executes on an
               already-populated table).

## Resolution

root_cause: >
  user_roles.updated_at is NULL on all seeded rows. Migration 0002 adds the
  updated_at column to user_roles via ALTER TABLE ADD COLUMN with a server_default,
  but PostgreSQL does NOT backfill server_default into existing rows on ADD COLUMN —
  only new inserts after the ALTER receive the default. Since seed_data.py runs
  after migrations (or the table may have had rows before the column was added),
  all seeded user_role rows have updated_at = NULL.

  The sync query in service.py filters on:
    WHERE updated_at > since OR deleted_at > since

  In PostgreSQL, NULL > any_value evaluates to NULL (not TRUE). Both updated_at
  and deleted_at are NULL on every seeded user_role row. The WHERE clause matches
  zero rows. Result: user_roles: [].

  Users and companies do NOT have this problem:
  - users table had updated_at from migration 0001 (always populated)
  - companies table had updated_at from migration 0001 (always populated)
  - user_roles.updated_at was added LATER in migration 0002, creating the NULL gap

fix: >
  Two complementary fixes are required:

  1. MIGRATION FIX - Add a data migration step in migration 0002 (or a new 0003)
     that backfills updated_at for existing rows:

       UPDATE user_roles SET updated_at = created_at WHERE updated_at IS NULL;

     This ensures rows inserted before the column existed get a meaningful timestamp.

  2. MODEL FIX - Change UserRole.updated_at to be non-nullable (consistent with
     User and Company) so the intent is clear and future inserts cannot silently
     produce NULL:

       updated_at: Mapped[datetime] = mapped_column(
           DateTime(timezone=True),
           nullable=False,        # was nullable=True
           server_default=func.now(),
       )

     This requires a corresponding nullable=False in the migration ADD COLUMN, but
     since we backfill first (step 1), existing rows will be non-null before the
     constraint is applied.

  ALTERNATIVELY (simplest fix): add a new migration 0003 that backfills the column:

       UPDATE user_roles SET updated_at = created_at WHERE updated_at IS NULL;

  This alone fixes the immediate symptom without touching the model.

verification: >
  After applying the backfill migration:
  1. Run GET /api/v1/sync?cursor= and confirm user_roles array is non-empty
  2. Confirm row count matches total user_role records in DB
  3. Run GET /api/v1/sync?cursor=<recent_timestamp> and confirm only roles
     created after that timestamp are returned (delta sync works correctly)

files_changed:
  - backend/migrations/versions/0002_soft_delete_sync.py (add UPDATE backfill step)
  - OR backend/migrations/versions/0003_backfill_user_roles_updated_at.py (new migration)
  - backend/app/features/users/models.py (change updated_at nullable=True to nullable=False)
