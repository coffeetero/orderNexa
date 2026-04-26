-- ============================================================
-- Seed fnd_customer_pricebooks from legacy customer + fnd_pricebooks
--
-- Run after seed_fnd_pricebooks.sql and seed_fnd_customers.sql.
-- Inserts PRIMARY assignment when legacy cus_price_cd maps to a price book name;
-- skips LOCATION rows and blank price codes (same rules as former fnd_customers.pricebook_id).
--
-- effective_start_date / effective_end_date: open-ended from a fixed start for seed data.
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted    INTEGER;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    DELETE FROM fnd_customer_pricebooks WHERE tenant_id = v_tenant_id;

    INSERT INTO fnd_customer_pricebooks (
        customer_id,
        pricebook_id,
        assignment_type,
        effective_start_date,
        effective_end_date,
        is_active,
        tenant_id
    )
    SELECT
        cus.customer_id,
        prcBk.pricebook_id,
        'PRIMARY',
        DATE '2000-01-01',
        NULL,
        TRUE,
        cus.tenant_id
    FROM fnd_customers cus
    INNER JOIN customer c
        ON (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_id::text, '')), ''))::integer = cus.legacy_id
    INNER JOIN fnd_pricebooks prcBk
        ON prcBk.tenant_id = cus.tenant_id
       AND prcBk.pricebook_name = NULLIF(TRIM(BOTH FROM COALESCE(c.cus_price_cd::text, '')), '')
    WHERE cus.tenant_id = v_tenant_id
      AND NOT (c.cus_invc_rqrd = 'N' OR c.cus_invc_rqrd IS NULL)
      AND NULLIF(TRIM(BOTH FROM COALESCE(c.cus_price_cd::text, '')), '') IS NOT NULL;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'fnd_customer_pricebooks: inserted % PRIMARY rows for tenant %', v_inserted, v_tenant_id;
END $$;
