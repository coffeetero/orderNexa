-- ============================================================
-- FND_CUSTOMERS — Row Level Security
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: fnd_customers.sql (table + triggers).
-- Policy uses current_setting('request.jwt.claims') (no auth schema USAGE required).
-- ============================================================

ALTER TABLE fnd_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_customers_tenant ON fnd_customers;

CREATE POLICY pol_fnd_customers_tenant ON fnd_customers
    USING (
        -- 1. Use current_setting to grab the JWT claim without calling the auth schema function
        (tenant_id::text = ANY (
            ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
                )
            )
        ))
        AND (
            -- 2. Check restricted tenants
            NOT (tenant_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'
                    )
                )
            ))
            OR 
            -- 3. Check allowed customers
            (customer_id::text = ANY (
                ARRAY(
                    SELECT jsonb_array_elements_text(
                        NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids'
                    )
                )
            ))
        )
    );
