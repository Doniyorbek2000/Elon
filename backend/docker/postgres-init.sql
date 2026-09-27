-- Extensions required by migrations, plus a separate database for e2e tests.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE DATABASE bozor_test OWNER bozor;
\connect bozor_test
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
