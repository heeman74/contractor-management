"""Create scheduling tables: bookings, contractor_weekly_schedule, contractor_date_overrides,
job_sites, travel_time_cache, contractor_schedule_locks.

Revision ID: 0007
Revises: 0006
Create Date: 2026-03-06

Changes:
- Create contractor_schedule_locks (per-contractor SELECT FOR UPDATE anchor row)
- Create contractor_weekly_schedule (weekly working-hours template)
- Create contractor_date_overrides (date-specific schedule overrides)
- Create job_sites (geocoded job locations)
- Create bookings with EXCLUDE USING GIST (conflict prevention safety net)
- Create travel_time_cache (ORS travel-time results, 30-day TTL)
- ALTER companies ADD COLUMN scheduling_config JSONB
- ALTER users ADD COLUMN home_address, home_latitude, home_longitude, timezone

CRITICAL NOTES:
- All table creation uses op.execute(text(...)) NOT op.create_table() — Alembic autogenerate
  has known bugs with ExcludeConstraint + TSTZRANGE (GitHub issues #1184, #1230, #958).
- btree_gist extension was already installed in migration 0001 (idempotent CREATE EXTENSION).
- set_updated_at() trigger function was created in migration 0002 — just CREATE TRIGGER here.
- GIST constraint includes WHERE (deleted_at IS NULL) — soft-deleted bookings do not block
  future bookings for the same time range.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. contractor_schedule_locks
    # Lightweight per-contractor anchor row for SELECT FOR UPDATE locking.
    # One row per contractor — never deleted. No version/timestamps needed
    # (it is a lock anchor, not a business entity).
    # RLS policy restricts reads to the contractor's company.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE contractor_schedule_locks (
            contractor_id UUID PRIMARY KEY REFERENCES users(id),
            company_id    UUID NOT NULL REFERENCES companies(id)
        )
    """)
    )
    op.execute(text("ALTER TABLE contractor_schedule_locks ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE contractor_schedule_locks FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON contractor_schedule_locks
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )

    # -------------------------------------------------------------------------
    # 2. contractor_weekly_schedule
    # Per-contractor working-hours template. Multiple blocks per day supported
    # (block_index allows modeling lunch breaks as two separate blocks).
    # Inherits TenantScopedModel structure: id, company_id, version, timestamps.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE contractor_weekly_schedule (
            id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id    UUID        NOT NULL REFERENCES companies(id),
            contractor_id UUID        NOT NULL REFERENCES users(id),
            day_of_week   INTEGER     NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
            block_index   INTEGER     NOT NULL DEFAULT 0,
            start_time    TIME        NOT NULL,
            end_time      TIME        NOT NULL,
            version       INTEGER     NOT NULL DEFAULT 1,
            created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at    TIMESTAMPTZ,
            CHECK (end_time > start_time),
            UNIQUE (contractor_id, day_of_week, block_index)
        )
    """)
    )
    op.execute(text("ALTER TABLE contractor_weekly_schedule ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE contractor_weekly_schedule FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON contractor_weekly_schedule
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_contractor_weekly_schedule_updated_at
        BEFORE UPDATE ON contractor_weekly_schedule
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # -------------------------------------------------------------------------
    # 3. contractor_date_overrides
    # Date-specific schedule overrides: either custom hours (multiple blocks)
    # or full-day unavailability (is_unavailable = true, times must be NULL).
    # CHECK constraint enforces the XOR between unavailable and time blocks.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE contractor_date_overrides (
            id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id      UUID        NOT NULL REFERENCES companies(id),
            contractor_id   UUID        NOT NULL REFERENCES users(id),
            override_date   DATE        NOT NULL,
            is_unavailable  BOOLEAN     NOT NULL DEFAULT false,
            block_index     INTEGER     NOT NULL DEFAULT 0,
            start_time      TIME,
            end_time        TIME,
            version         INTEGER     NOT NULL DEFAULT 1,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at      TIMESTAMPTZ,
            CHECK (
                (is_unavailable = true  AND start_time IS NULL     AND end_time IS NULL)
                OR
                (is_unavailable = false AND start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)
            ),
            UNIQUE (contractor_id, override_date, block_index)
        )
    """)
    )
    op.execute(text("ALTER TABLE contractor_date_overrides ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE contractor_date_overrides FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON contractor_date_overrides
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_contractor_date_overrides_updated_at
        BEFORE UPDATE ON contractor_date_overrides
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # -------------------------------------------------------------------------
    # 4. job_sites
    # Geocoded job locations. Lat/lng stored as NUMERIC(9,6) for precision.
    # Optional name for named sites (e.g., "Main Warehouse", "Client Office").
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE job_sites (
            id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id UUID           NOT NULL REFERENCES companies(id),
            address    TEXT           NOT NULL,
            latitude   NUMERIC(9,6)   NOT NULL,
            longitude  NUMERIC(9,6)   NOT NULL,
            name       TEXT,
            version    INTEGER        NOT NULL DEFAULT 1,
            created_at TIMESTAMPTZ    NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ    NOT NULL DEFAULT now(),
            deleted_at TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE job_sites ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE job_sites FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON job_sites
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_job_sites_updated_at
        BEFORE UPDATE ON job_sites
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # -------------------------------------------------------------------------
    # 5. bookings — THE CORE SCHEDULING TABLE
    #
    # EXCLUDE USING GIST prevents overlapping time ranges for the same contractor.
    # WHERE (deleted_at IS NULL) ensures soft-deleted bookings don't block
    # future bookings for the same slot.
    #
    # day_index: NULL for single-day bookings; 0-based index for multi-day.
    # parent_booking_id: links all records belonging to the same multi-day job.
    # job_id: references the jobs table (Phase 4). Plain UUID for now — FK will
    # be added in Phase 4 migration.
    #
    # IMPORTANT: Uses raw op.execute() — Alembic autogenerate is unreliable for
    # ExcludeConstraint + TSTZRANGE (see migration docstring).
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE bookings (
            id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id        UUID        NOT NULL REFERENCES companies(id),
            contractor_id     UUID        NOT NULL REFERENCES users(id),
            job_id            UUID        NOT NULL,
            job_site_id       UUID        REFERENCES job_sites(id),
            time_range        TSTZRANGE   NOT NULL,
            day_index         INTEGER,
            parent_booking_id UUID        REFERENCES bookings(id),
            notes             TEXT,
            version           INTEGER     NOT NULL DEFAULT 1,
            created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at        TIMESTAMPTZ,
            EXCLUDE USING GIST (
                contractor_id WITH =,
                time_range    WITH &&
            ) WHERE (deleted_at IS NULL)
        )
    """)
    )
    op.execute(text("ALTER TABLE bookings ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE bookings FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON bookings
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_bookings_updated_at
        BEFORE UPDATE ON bookings
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )
    # Index for availability queries (most common: find bookings by contractor)
    op.execute(text("CREATE INDEX idx_bookings_contractor_id ON bookings (contractor_id)"))
    # Index for job lookup (e.g., list all booking records for a multi-day job)
    op.execute(text("CREATE INDEX idx_bookings_job_id ON bookings (job_id)"))

    # -------------------------------------------------------------------------
    # 6. travel_time_cache
    # Caches OpenRouteService travel time results to conserve the 2000 req/day
    # free-tier quota. TTL logic enforced at application level (30-day cutoff).
    # UNIQUE constraint on coordinates enables fast cache hit detection.
    # No RLS, version, or deleted_at — this is a cache, not a business entity.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE travel_time_cache (
            id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id       UUID         NOT NULL REFERENCES companies(id),
            lat1             NUMERIC(9,6) NOT NULL,
            lng1             NUMERIC(9,6) NOT NULL,
            lat2             NUMERIC(9,6) NOT NULL,
            lng2             NUMERIC(9,6) NOT NULL,
            duration_seconds INTEGER      NOT NULL,
            fetched_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
            UNIQUE (company_id, lat1, lng1, lat2, lng2)
        )
    """)
    )
    op.execute(text("CREATE INDEX idx_travel_cache_company ON travel_time_cache (company_id)"))

    # -------------------------------------------------------------------------
    # 7. ALTER companies — add scheduling_config JSONB column
    # Stores company-wide scheduling defaults validated by SchedulingConfig Pydantic model.
    # Default is empty JSONB object; Pydantic fills in defaults on read.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        ALTER TABLE companies
        ADD COLUMN scheduling_config JSONB NOT NULL DEFAULT '{}'::jsonb
    """)
    )

    # -------------------------------------------------------------------------
    # 8. ALTER users — add contractor home location and timezone columns
    # home_latitude and home_longitude are the contractor's home base coordinates
    # used as the origin for travel time calculations to the first job of the day.
    # timezone is IANA timezone name (e.g., 'America/Vancouver').
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        ALTER TABLE users
        ADD COLUMN home_address   TEXT,
        ADD COLUMN home_latitude  NUMERIC(9,6),
        ADD COLUMN home_longitude NUMERIC(9,6),
        ADD COLUMN timezone       TEXT NOT NULL DEFAULT 'UTC'
    """)
    )


def downgrade() -> None:
    # -------------------------------------------------------------------------
    # Reverse in dependency order (children before parents):
    # bookings references job_sites, users, companies
    # contractor_date_overrides, contractor_weekly_schedule reference users, companies
    # contractor_schedule_locks references users, companies
    # travel_time_cache references companies
    # -------------------------------------------------------------------------

    # Remove columns added to existing tables first
    op.execute(
        text("""
        ALTER TABLE users
        DROP COLUMN IF EXISTS timezone,
        DROP COLUMN IF EXISTS home_longitude,
        DROP COLUMN IF EXISTS home_latitude,
        DROP COLUMN IF EXISTS home_address
    """)
    )
    op.execute(
        text("""
        ALTER TABLE companies
        DROP COLUMN IF EXISTS scheduling_config
    """)
    )

    # Drop triggers before dropping tables
    op.execute(text("DROP TRIGGER IF EXISTS set_bookings_updated_at ON bookings"))
    op.execute(text("DROP TRIGGER IF EXISTS set_job_sites_updated_at ON job_sites"))
    op.execute(
        text(
            "DROP TRIGGER IF EXISTS set_contractor_date_overrides_updated_at ON contractor_date_overrides"
        )
    )
    op.execute(
        text(
            "DROP TRIGGER IF EXISTS set_contractor_weekly_schedule_updated_at ON contractor_weekly_schedule"
        )
    )

    # Drop RLS policies before dropping tables
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON bookings"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON job_sites"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON contractor_date_overrides"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON contractor_weekly_schedule"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON contractor_schedule_locks"))

    # Drop tables in reverse dependency order
    op.execute(text("DROP TABLE IF EXISTS bookings"))
    op.execute(text("DROP TABLE IF EXISTS travel_time_cache"))
    op.execute(text("DROP TABLE IF EXISTS job_sites"))
    op.execute(text("DROP TABLE IF EXISTS contractor_date_overrides"))
    op.execute(text("DROP TABLE IF EXISTS contractor_weekly_schedule"))
    op.execute(text("DROP TABLE IF EXISTS contractor_schedule_locks"))
