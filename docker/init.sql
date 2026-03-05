-- PostgreSQL initialization script
-- Runs as postgres superuser on first container creation
-- Creates required extensions that the application user cannot install

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS btree_gist;
