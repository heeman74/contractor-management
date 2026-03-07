-- PostgreSQL initialization script
-- Runs as postgres superuser on first container creation.
-- Creates the appuser role (non-superuser, no BYPASSRLS) so that
-- Row Level Security policies are enforced at the database level.

-- Install extensions that require superuser privileges
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Create the application role (non-superuser so RLS is enforced)
CREATE ROLE appuser WITH LOGIN PASSWORD 'apppassword' NOSUPERUSER NOBYPASSRLS;

-- Grant privileges on the default database (contractorhub)
-- The database is created by Docker's POSTGRES_DB env var as postgres superuser.
GRANT ALL PRIVILEGES ON DATABASE contractorhub TO appuser;

-- Grant schema-level privileges so appuser can create tables via Alembic migrations
GRANT ALL ON SCHEMA public TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO appuser;
