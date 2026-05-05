-- ============================================================
-- FND_AUDIT_LOG — Row Level Security
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: fnd_audit_log.sql (table + fn_audit_log).
-- References auth.jwt() — requires USAGE on schema auth (e.g. SQL Editor / postgres).
-- ============================================================

ALTER TABLE fnd_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_audit_log_tenant_read ON fnd_audit_log;

CREATE POLICY pol_fnd_audit_log_tenant_read ON fnd_audit_log
    FOR SELECT
    USING (
        tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    auth.jwt() -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        )
    );
