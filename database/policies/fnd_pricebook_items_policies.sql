-- ============================================================
-- FND_PRICEBOOK_ITEMS — Row Level Security
-- Run after: fnd_pricebook_items.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_pricebook_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_pricebook_items_tenant ON fnd_pricebook_items;
CREATE POLICY pol_fnd_pricebook_items_tenant ON fnd_pricebook_items
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM fnd_customer_pricebooks fcp
        WHERE fcp.pricebook_id = fnd_pricebook_items.pricebook_id
        AND (fcp.tenant_id)::text = ANY (ARRAY(
          SELECT jsonb_array_elements_text(
            ((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata') -> 'allowed_tenant_ids')
          )
        ))
        AND (
          NOT ((fcp.tenant_id)::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
              ((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata') -> 'restricted_tenant_ids')
            )
          )))
          OR (fcp.customer_id)::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
              ((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata') -> 'allowed_customer_ids')
            )
          ))
        )
      )
    );
