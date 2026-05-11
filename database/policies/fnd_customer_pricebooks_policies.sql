-- ============================================================
-- FND_CUSTOMER_PRICEBOOKS — Row Level Security
-- Run after: fnd_customer_pricebooks.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_customer_pricebooks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_customer_pricebooks_tenant ON fnd_customer_pricebooks;
CREATE POLICY pol_fnd_customer_pricebooks_tenant ON fnd_customer_pricebooks
    FOR SELECT
    USING (
      (tenant_id)::text = ANY (ARRAY(
        SELECT jsonb_array_elements_text(
          ((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata') -> 'allowed_tenant_ids')
        )
      ))
      AND (
        NOT ((tenant_id)::text = ANY (ARRAY(
          SELECT jsonb_array_elements_text(
            ((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata') -> 'restricted_tenant_ids')
          )
        )))
        OR (customer_id)::text = ANY (ARRAY(
          SELECT jsonb_array_elements_text(
            ((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata') -> 'allowed_customer_ids')
          )
        ))
      )
    );
