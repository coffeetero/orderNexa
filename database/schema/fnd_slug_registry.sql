-- ============================================================
-- FND_SLUG_REGISTRY  –  Reserved / issued slugs (optional lookup)
-- Target: Supabase (PostgreSQL 15+)
--
-- Run with search_path including your app schema, e.g. SET search_path = bps, public;
-- No FKs; safe after fnd_entity_id_seq.sql (none required). Typical position: after fnd_tenants.sql.
--
-- Shape matches live catalog (information_schema on your app schema).
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_slug_registry (
    slug         TEXT,
    entity_type  TEXT
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE fnd_slug_registry OWNER TO bps_owner;

COMMENT ON TABLE fnd_slug_registry IS
    'Optional slug registry keyed by slug and entity classification.';
