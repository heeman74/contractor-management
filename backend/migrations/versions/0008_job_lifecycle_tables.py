"""Create job lifecycle tables: jobs, client_profiles, client_properties, job_requests, ratings.

Revision ID: 0008
Revises: 0007
Create Date: 2026-03-09

Changes:
- Create jobs table with status machine, JSONB status_history, priority, RLS, GIN full-text search
- ALTER TABLE bookings ADD CONSTRAINT bookings_job_id_fkey (deferred from migration 0007)
- Create client_profiles (per-tenant client CRM record)
- Create client_properties (property/job-site association for clients)
- Create job_requests (inbound client requests, convertible to jobs)
- Create ratings (star ratings for completed jobs, direction-aware)

CRITICAL NOTES:
- All table creation uses op.execute(text(...)) NOT op.create_table() — consistent with
  migration 0007 pattern for complex DDL (GIN indexes, tsvector triggers, JSONB defaults).
- set_updated_at() trigger function was created in migration 0002 — just CREATE TRIGGER here.
- Full-text search via tsvector: separate trigger function created here to update
  search_vector on INSERT or UPDATE of description/notes.
- bookings.job_id FK was intentionally omitted from migration 0007 (jobs table did not exist yet).
  It is added here as a named constraint after creating the jobs table.
"""

from collections.abc import Sequence

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. jobs — core job lifecycle table
    #
    # status: 6-value state machine (quote -> scheduled -> in_progress -> complete
    #         -> invoiced | cancelled)
    # status_history: JSONB array — each entry records {status, timestamp, user_id, reason}
    # priority: low / medium / high / urgent
    # search_vector: tsvector populated by trigger on description + notes
    # version: used for optimistic locking (see JobTransitionRequest schema)
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE jobs (
            id                         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id                 UUID        NOT NULL REFERENCES companies(id),
            description                TEXT        NOT NULL,
            trade_type                 TEXT        NOT NULL,
            status                     TEXT        NOT NULL DEFAULT 'quote'
                                       CHECK (status IN ('quote','scheduled','in_progress','complete','invoiced','cancelled')),
            status_history             JSONB       NOT NULL DEFAULT '[]'::jsonb,
            priority                   TEXT        NOT NULL DEFAULT 'medium'
                                       CHECK (priority IN ('low','medium','high','urgent')),
            client_id                  UUID        REFERENCES users(id),
            contractor_id              UUID        REFERENCES users(id),
            purchase_order_number      TEXT,
            external_reference         TEXT,
            tags                       JSONB       NOT NULL DEFAULT '[]'::jsonb,
            notes                      TEXT,
            estimated_duration_minutes INTEGER,
            scheduled_completion_date  DATE,
            search_vector              TSVECTOR,
            version                    INTEGER     NOT NULL DEFAULT 1,
            created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at                 TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE jobs ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE jobs FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON jobs
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )

    # Indexes for jobs
    op.execute(text("CREATE INDEX idx_jobs_search_vector ON jobs USING GIN (search_vector)"))
    op.execute(
        text(
            "CREATE INDEX idx_jobs_company_status ON jobs (company_id, status) "
            "WHERE deleted_at IS NULL"
        )
    )
    op.execute(
        text("CREATE INDEX idx_jobs_client_id ON jobs (client_id) WHERE deleted_at IS NULL")
    )
    op.execute(
        text(
            "CREATE INDEX idx_jobs_contractor_id ON jobs (contractor_id) WHERE deleted_at IS NULL"
        )
    )

    # Trigger: updated_at
    op.execute(
        text("""
        CREATE TRIGGER set_jobs_updated_at
        BEFORE UPDATE ON jobs
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # Function + trigger: full-text search vector
    op.execute(
        text("""
        CREATE OR REPLACE FUNCTION update_jobs_search_vector()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.search_vector :=
                setweight(to_tsvector('english', coalesce(NEW.description, '')), 'A') ||
                setweight(to_tsvector('english', coalesce(NEW.notes, '')), 'B');
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER jobs_search_vector_update
        BEFORE INSERT OR UPDATE OF description, notes ON jobs
        FOR EACH ROW EXECUTE FUNCTION update_jobs_search_vector()
    """)
    )

    # -------------------------------------------------------------------------
    # 2. ALTER TABLE bookings — add FK constraint for job_id
    #
    # bookings.job_id was created as a plain UUID in migration 0007 with the
    # comment: "FK will be added in Phase 4 migration." This is that FK.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        ALTER TABLE bookings
        ADD CONSTRAINT bookings_job_id_fkey
        FOREIGN KEY (job_id) REFERENCES jobs(id)
    """)
    )

    # -------------------------------------------------------------------------
    # 3. client_profiles — CRM record linking a user to a tenant's client
    #
    # One record per user per company. user_id UNIQUE ensures a user cannot
    # have two client profiles in the same company.
    # average_rating: denormalized from ratings table, updated by application.
    # preferred_contractor_id: optional FK to users for contractor preference.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE client_profiles (
            id                       UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id               UUID           NOT NULL REFERENCES companies(id),
            user_id                  UUID           NOT NULL UNIQUE REFERENCES users(id),
            billing_address          TEXT,
            tags                     JSONB          NOT NULL DEFAULT '[]'::jsonb,
            admin_notes              TEXT,
            referral_source          TEXT,
            preferred_contractor_id  UUID           REFERENCES users(id),
            preferred_contact_method TEXT,
            average_rating           NUMERIC(3,2),
            version                  INTEGER        NOT NULL DEFAULT 1,
            created_at               TIMESTAMPTZ    NOT NULL DEFAULT now(),
            updated_at               TIMESTAMPTZ    NOT NULL DEFAULT now(),
            deleted_at               TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE client_profiles ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE client_profiles FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON client_profiles
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_client_profiles_updated_at
        BEFORE UPDATE ON client_profiles
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # -------------------------------------------------------------------------
    # 4. client_properties — associates a client (user) with a job site
    #
    # A client may have multiple properties (job sites). is_default marks the
    # primary property for that client. nickname is a human-readable label
    # (e.g., "Home", "Office", "Rental Unit").
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE client_properties (
            id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id   UUID        NOT NULL REFERENCES companies(id),
            client_id    UUID        NOT NULL REFERENCES users(id),
            job_site_id  UUID        NOT NULL REFERENCES job_sites(id),
            nickname     TEXT,
            is_default   BOOLEAN     NOT NULL DEFAULT false,
            version      INTEGER     NOT NULL DEFAULT 1,
            created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at   TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE client_properties ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE client_properties FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON client_properties
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_client_properties_updated_at
        BEFORE UPDATE ON client_properties
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # -------------------------------------------------------------------------
    # 5. job_requests — inbound requests from clients (portal or manual entry)
    #
    # A job_request can be:
    #   - submitted anonymously (client_id NULL, submitted_name/email/phone filled)
    #   - submitted by an authenticated client (client_id set)
    #
    # When accepted, converted_job_id is set to the resulting job.
    # status: pending -> accepted | declined | info_requested
    # urgency: normal | urgent (client-indicated priority)
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE job_requests (
            id                    UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id            UUID           NOT NULL REFERENCES companies(id),
            client_id             UUID           REFERENCES users(id),
            description           TEXT           NOT NULL,
            trade_type            TEXT,
            urgency               TEXT           NOT NULL DEFAULT 'normal'
                                  CHECK (urgency IN ('normal','urgent')),
            preferred_date_start  DATE,
            preferred_date_end    DATE,
            budget_min            NUMERIC(10,2),
            budget_max            NUMERIC(10,2),
            photos                JSONB          NOT NULL DEFAULT '[]'::jsonb,
            status                TEXT           NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','accepted','declined','info_requested')),
            decline_reason        TEXT,
            decline_message       TEXT,
            converted_job_id      UUID           REFERENCES jobs(id),
            submitted_name        TEXT,
            submitted_email       TEXT,
            submitted_phone       TEXT,
            version               INTEGER        NOT NULL DEFAULT 1,
            created_at            TIMESTAMPTZ    NOT NULL DEFAULT now(),
            updated_at            TIMESTAMPTZ    NOT NULL DEFAULT now(),
            deleted_at            TIMESTAMPTZ
        )
    """)
    )
    op.execute(text("ALTER TABLE job_requests ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE job_requests FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON job_requests
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_job_requests_updated_at
        BEFORE UPDATE ON job_requests
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )

    # -------------------------------------------------------------------------
    # 6. ratings — star ratings for completed jobs
    #
    # direction: admin_to_client (company rates the client) or
    #            client_to_company (client rates the company)
    # UNIQUE (job_id, direction): one rating per direction per job.
    # stars: 1-5 integer CHECK constraint enforced at DB level.
    # -------------------------------------------------------------------------
    op.execute(
        text("""
        CREATE TABLE ratings (
            id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
            company_id  UUID        NOT NULL REFERENCES companies(id),
            job_id      UUID        NOT NULL REFERENCES jobs(id),
            rater_id    UUID        NOT NULL REFERENCES users(id),
            ratee_id    UUID        NOT NULL REFERENCES users(id),
            direction   TEXT        NOT NULL
                        CHECK (direction IN ('admin_to_client','client_to_company')),
            stars       INTEGER     NOT NULL CHECK (stars BETWEEN 1 AND 5),
            review_text TEXT,
            version     INTEGER     NOT NULL DEFAULT 1,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            deleted_at  TIMESTAMPTZ,
            UNIQUE (job_id, direction)
        )
    """)
    )
    op.execute(text("ALTER TABLE ratings ENABLE ROW LEVEL SECURITY"))
    op.execute(text("ALTER TABLE ratings FORCE ROW LEVEL SECURITY"))
    op.execute(
        text("""
        CREATE POLICY tenant_isolation ON ratings
        USING (company_id = current_setting('app.current_company_id', true)::uuid)
    """)
    )
    op.execute(
        text("""
        CREATE TRIGGER set_ratings_updated_at
        BEFORE UPDATE ON ratings
        FOR EACH ROW EXECUTE FUNCTION set_updated_at()
    """)
    )


def downgrade() -> None:
    # -------------------------------------------------------------------------
    # Reverse in dependency order (children before parents):
    # ratings -> job_requests -> client_properties -> client_profiles
    # -> bookings FK -> jobs (plus search function)
    # -------------------------------------------------------------------------

    # Drop triggers before dropping tables
    op.execute(text("DROP TRIGGER IF EXISTS set_ratings_updated_at ON ratings"))
    op.execute(text("DROP TRIGGER IF EXISTS set_job_requests_updated_at ON job_requests"))
    op.execute(text("DROP TRIGGER IF EXISTS set_client_properties_updated_at ON client_properties"))
    op.execute(text("DROP TRIGGER IF EXISTS set_client_profiles_updated_at ON client_profiles"))
    op.execute(text("DROP TRIGGER IF EXISTS jobs_search_vector_update ON jobs"))
    op.execute(text("DROP TRIGGER IF EXISTS set_jobs_updated_at ON jobs"))

    # Drop RLS policies before dropping tables
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON ratings"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON job_requests"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON client_properties"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON client_profiles"))
    op.execute(text("DROP POLICY IF EXISTS tenant_isolation ON jobs"))

    # Drop tables in reverse dependency order
    op.execute(text("DROP TABLE IF EXISTS ratings"))
    op.execute(text("DROP TABLE IF EXISTS job_requests"))
    op.execute(text("DROP TABLE IF EXISTS client_properties"))
    op.execute(text("DROP TABLE IF EXISTS client_profiles"))

    # Remove bookings FK constraint before dropping jobs
    op.execute(
        text("""
        ALTER TABLE bookings
        DROP CONSTRAINT IF EXISTS bookings_job_id_fkey
    """)
    )

    op.execute(text("DROP TABLE IF EXISTS jobs"))

    # Drop the search vector function (created in upgrade for jobs)
    op.execute(text("DROP FUNCTION IF EXISTS update_jobs_search_vector()"))
