-- ============================================================
-- SEED OM_STANDING_ORDERS FROM LEGACY SORDR TABLE
--
-- Source:  bps.sordr  (pumped from SQL Anywhere)
-- Target:  bps.om_standing_orders
--
-- Mapping:
--   cus_id        → customer_id   (via fnd_customers.legacy_id)
--   item_id       → item_id       (via fnd_items.legacy_id)
--   so_prdctn_pd  → production_day
--   so_prdctn_cd  → production_code
--   so_qty_sold   → quantity      (0 is valid — reminder lines)
--
-- prep_options: left empty ('[]') — legacy relied on item-level prep.
-- Tenants should review and set per-standing-order prep as needed.
--
-- Scope: only active customers that exist in fnd_customers.
-- Unmatched or inactive customers are silently skipped.
-- Re-run after additional customers are seeded.
--
-- Prerequisites: seed_fnd_customers.sql, seed_fnd_items.sql
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted  INT;
    v_skipped   INT;
BEGIN

    SELECT tenant_id INTO v_tenant_id
    FROM bps.fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    -- Count what will be skipped for visibility
    SELECT COUNT(*) INTO v_skipped
    FROM bps.sordr s
    LEFT JOIN bps.fnd_customers fc
           ON fc.legacy_id = s.cus_id::INT
          AND fc.tenant_id = v_tenant_id
          AND fc.is_active = TRUE
    WHERE fc.customer_id IS NULL;

    RAISE NOTICE 'Skipping % sordr rows (customer not in fnd_customers or inactive)', v_skipped;

    TRUNCATE TABLE bps.om_standing_orders;

    INSERT INTO bps.om_standing_orders (
        tenant_id,
        customer_id,
        production_day,
        production_code,
        item_id,
        quantity,
        prep_options,
        is_active
    )
    SELECT
        v_tenant_id,
        fc.customer_id,
        s.so_prdctn_pd,
        s.so_prdctn_cd,
        fi.item_id,
        COALESCE(s.so_qty_sold, 0),
        '[]'::JSONB,
        TRUE
    FROM bps.sordr s
    JOIN bps.fnd_customers fc
      ON fc.legacy_id = s.cus_id::INT
     AND fc.tenant_id = v_tenant_id
     AND fc.is_active = TRUE
    JOIN bps.fnd_items fi
      ON fi.legacy_id = s.item_id::INT
     AND fi.tenant_id = v_tenant_id;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'om_standing_orders: % rows inserted', v_inserted;

END $$;
