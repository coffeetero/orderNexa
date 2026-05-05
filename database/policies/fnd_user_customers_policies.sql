-- ============================================================
-- FND_USER_CUSTOMERS — Row Level Security
-- Run after: fnd_user_customers.sql. References auth.jwt().
-- ============================================================

ALTER TABLE fnd_user_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_customers_tenant ON fnd_user_customers;
CREATE POLICY pol_fnd_user_customers_tenant ON fnd_user_customers
    FOR ALL
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);
