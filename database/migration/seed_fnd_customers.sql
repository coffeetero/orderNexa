-- ============================================================
-- Seed fnd_customers from legacy customer table
--
-- BEFORE RUNNING:
--   Requires tenant "Alpine Bakery" in fnd_tenants (tenant_id resolved at runtime).
--   fnd_pricebooks rows are needed before seed_fnd_customer_pricebooks.sql (match by pricebook_name).
--   Primary price book assignments: see seed_fnd_customer_pricebooks.sql (cus_price_cd → PRIMARY;
--   NULL for LOCATION customer_type or blank code).
--   Adjust the tenant_name filter if you use a different tenant.
--
-- TRUNCATE fnd_customers CASCADE removes every customer row (all tenants) and
-- dependent om_orders / om_order_lines; then reloads Alpine Bakery from legacy public.customer.
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted     INTEGER;
    v_updated      INTEGER;
BEGIN

    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    TRUNCATE TABLE fnd_customers CASCADE;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;
    RAISE NOTICE 'Price books per customer: run seed_fnd_customer_pricebooks.sql after this seed.';
    RAISE NOTICE '>>> Step 1: Inserting customers (parent links deferred)...';

    -- --------------------------------------------------------
    -- STEP 1: Insert all rows with customer_parent_id = NULL.
    --
    -- Legacy keys are normalized to INT (trim text, cast) so parent resolution
    -- matches step 2 and self-referencing ACCOUNT detection is not broken by
    -- text formatting (e.g. '123' vs '0123').
    --
    -- customer_type derivation from legacy data:
    --   LOCATION : cus_invc_rqrd = 'N'  — delivery point, not invoiced directly
    --   ACCOUNT  : cus_invc_rqrd = 'Y'  + self-referencing (cus_id = cus_parent_id)
    --   SITE     : cus_invc_rqrd = 'Y'  + has a real parent
    -- --------------------------------------------------------
    INSERT INTO fnd_customers (
        tenant_id,
        legacy_id,
        customer_parent_id,             -- resolved in step 2
        customer_name,
        customer_number,
        customer_type,
        invoice_copy_count,
        is_standing_order,
        is_signature_required,
        is_active,
        is_label_required,
        is_invoice_required,
        is_cost_on_invoice,             -- no source column; defaulting to FALSE
        is_cost_on_bill_of_lading,
        is_returns_allowed
    )
    SELECT
        v_tenant_id,

        (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_id::text, '')), ''))::integer,

        NULL,

        -- Ensure a non-empty name
        COALESCE(NULLIF(TRIM(c.cus_name), ''), '(unnamed)'),

        NULLIF(TRIM(c.cus_key), ''),

        CASE
            WHEN c.cus_invc_rqrd = 'N' OR c.cus_invc_rqrd IS NULL THEN 'LOCATION'
            WHEN (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_id::text, '')), ''))::integer
                 IS NOT DISTINCT FROM (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_parent_id::text, '')), ''))::integer
                 AND NULLIF(TRIM(BOTH FROM COALESCE(c.cus_parent_id::text, '')), '') IS NOT NULL
            THEN 'ACCOUNT'
            ELSE 'SITE'
        END,

        -- Guard against 0 or negative values
        GREATEST(COALESCE(c.cus_invc_copies::integer, 1), 1),

        COALESCE(c.cus_standing_ordr  = 'Y', FALSE),
        COALESCE(c.cus_signature_rqrd = 'Y', FALSE),
        COALESCE(c.cus_active         = 'Y', FALSE),
        COALESCE(c.cus_lbl_rqrd       = 'Y', FALSE),
        COALESCE(c.cus_invc_rqrd      = 'Y', FALSE),

        FALSE,

        COALESCE(c.cus_cost_onbl = 'Y', FALSE),

        -- NULL in source means returns are allowed (matches fnd_customers default TRUE)
        COALESCE(c.cus_returns_allowed = 'Y', TRUE)

    FROM customer c;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE '    Inserted: % rows', v_inserted;


    -- --------------------------------------------------------
    -- STEP 2: Resolve customer_parent_id via legacy_id lookup.
    --
    -- ACCOUNT rows are self-referencing in the legacy data
    -- (cus_id = cus_parent_id).  We skip those — an ACCOUNT
    -- has no parent in the new schema.
    -- --------------------------------------------------------
    RAISE NOTICE '>>> Step 2: Resolving customer_parent_id links...';

    -- Join on normalized legacy ids (trim + int). Use IS DISTINCT FROM so NULL parents
    -- are not compared with != (which would exclude valid rows incorrectly).
    UPDATE fnd_customers  child
    SET    customer_parent_id = parent.customer_id
    FROM   customer       c
    JOIN   fnd_customers  parent
           ON  parent.legacy_id = (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_parent_id::text, '')), ''))::integer
           AND parent.tenant_id = v_tenant_id
    WHERE  child.legacy_id  = (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_id::text, '')), ''))::integer
      AND  child.tenant_id  = v_tenant_id
      AND  (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_parent_id::text, '')), '')) IS NOT NULL
      AND  (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_id::text, '')), ''))::integer
           IS DISTINCT FROM (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_parent_id::text, '')), ''))::integer;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RAISE NOTICE '    Parent links resolved: % rows', v_updated;


    -- --------------------------------------------------------
    -- STEP 3: Summary
    -- --------------------------------------------------------
    RAISE NOTICE '>>> Done. Breakdown by customer_type:';
    RAISE NOTICE '    ACCOUNT  : %', (
        SELECT COUNT(*) FROM fnd_customers
        WHERE tenant_id = v_tenant_id AND customer_type = 'ACCOUNT'
    );
    RAISE NOTICE '    SITE     : %', (
        SELECT COUNT(*) FROM fnd_customers
        WHERE tenant_id = v_tenant_id AND customer_type = 'SITE'
    );
    RAISE NOTICE '    LOCATION : %', (
        SELECT COUNT(*) FROM fnd_customers
        WHERE tenant_id = v_tenant_id AND customer_type = 'LOCATION'
    );
    RAISE NOTICE '    TOTAL    : %', (
        SELECT COUNT(*) FROM fnd_customers
        WHERE tenant_id = v_tenant_id
    );
    RAISE NOTICE '    Unresolved parents (should be 0): %', (
        SELECT COUNT(*)
        FROM   fnd_customers cus
        JOIN   customer c
               ON (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_id::text, '')), ''))::integer = cus.legacy_id
        WHERE  cus.tenant_id          = v_tenant_id
          AND  cus.customer_parent_id IS NULL
          AND  NULLIF(TRIM(BOTH FROM COALESCE(c.cus_parent_id::text, '')), '') IS NOT NULL
          AND  (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_id::text, '')), ''))::integer
               IS DISTINCT FROM (NULLIF(TRIM(BOTH FROM COALESCE(c.cus_parent_id::text, '')), ''))::integer
    );

END $$;
