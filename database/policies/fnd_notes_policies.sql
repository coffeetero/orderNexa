-- ============================================================
-- FND_NOTES — Row Level Security
-- Run after: fnd_notes.sql. References auth.jwt().
--
-- SELECT:
--   All users must belong to the note's tenant (allowed_tenant_ids).
--   CUSTOMER_USER may only read notes with visibility = 'shared'.
--   Non-customer users see all notes for their tenant.
--
-- INSERT / UPDATE:
--   Any authenticated user whose tenant is in allowed_tenant_ids.
--   Application layer is responsible for enforcing visibility rules on write.
--
-- DELETE:
--   Not permitted via RLS — use soft delete (deleted_at) from application layer.
-- ============================================================

ALTER TABLE fnd_notes ENABLE ROW LEVEL SECURITY;

-- Helper expression (repeated in each policy for clarity):
--   tenant_id must be in the caller's allowed_tenant_ids JWT array.
--   JWT path: app_metadata -> allowed_tenant_ids (JSONB array of BIGINT-as-text)

DROP POLICY IF EXISTS pol_fnd_notes_select ON fnd_notes;
CREATE POLICY pol_fnd_notes_select ON fnd_notes
    FOR SELECT
    USING (
        -- 1. Tenant gate: caller must have access to this tenant
        (tenant_id)::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb
                    -> 'app_metadata' -> 'allowed_tenant_ids')
            )
        ))
        AND
        -- 2. Visibility gate: customer users see shared notes only.
        --    IS DISTINCT FROM handles NULL user_type correctly (NULL != 'CUSTOMER_USER' = NULL, not TRUE).
        (
            (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb
                -> 'app_metadata' ->> 'user_type') IS DISTINCT FROM 'CUSTOMER_USER'
            OR visibility = 'shared'
        )
        AND deleted_at IS NULL
    );

DROP POLICY IF EXISTS pol_fnd_notes_insert ON fnd_notes;
CREATE POLICY pol_fnd_notes_insert ON fnd_notes
    FOR INSERT
    WITH CHECK (
        (tenant_id)::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb
                    -> 'app_metadata' -> 'allowed_tenant_ids')
            )
        ))
    );

DROP POLICY IF EXISTS pol_fnd_notes_update ON fnd_notes;
CREATE POLICY pol_fnd_notes_update ON fnd_notes
    FOR UPDATE
    USING (
        (tenant_id)::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb
                    -> 'app_metadata' -> 'allowed_tenant_ids')
            )
        ))
    )
    WITH CHECK (
        (tenant_id)::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb
                    -> 'app_metadata' -> 'allowed_tenant_ids')
            )
        ))
    );
