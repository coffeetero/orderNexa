-- ============================================================
-- FND_CONTACTS — Row Level Security (Supabase / auth.jwt)
-- Target: Supabase (PostgreSQL 15+)
--
-- Run with search_path including your app schema, e.g. SET search_path = bps, public;
--
-- Requires USAGE on schema auth (references auth.jwt). Typical runs:
--   • Supabase Dashboard → SQL Editor (postgres / dashboard session)
-- Pooler / custom DB roles often get: permission denied for schema auth
--
-- Run after: fnd_contacts.sql
-- ============================================================

ALTER TABLE fnd_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_contacts_tenant ON fnd_contacts;
CREATE POLICY pol_fnd_contacts_tenant ON fnd_contacts
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
