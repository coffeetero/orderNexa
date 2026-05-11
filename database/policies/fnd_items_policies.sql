-- ============================================================
-- FND_ITEMS — Row Level Security
-- Run after: fnd_items.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_items_tenant ON fnd_items;
CREATE POLICY pol_fnd_items_tenant ON fnd_items
    FOR SELECT
    USING (
      (tenant_id)::text = ANY (ARRAY(
        SELECT jsonb_array_elements_text(
          ((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata') -> 'allowed_tenant_ids')
        )
      ))
    );
