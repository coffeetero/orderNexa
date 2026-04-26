-- ============================================================
-- SEED BPS_ITEMS FROM LEGACY ITEM TABLE
--
-- Source:  public.item  (uploaded from SQL Anywhere)
-- Target:  public.bps_items
--
-- Prerequisite: seed_fnd_items.sql must have run first
-- (bps_items.item_id is a FK to fnd_items.item_id).
--
-- TRUNCATE bps_items, then INSERT from legacy (run after fnd_items are loaded).
--
-- Constraint handling:
--   The source data has 28 rows where a default (sliced/wrapped/covered)
--   is set Y but the corresponding capability is not.  We resolve this
--   by auto-promoting the capability: if default_X is TRUE, is_X is
--   forced TRUE regardless of the source value.  This is the most
--   faithful interpretation — the item clearly supports the operation
--   if it was defaulting to it.
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted   INT;
BEGIN

    -- --------------------------------------------------------
    -- 1. Resolve tenant
    -- --------------------------------------------------------
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    TRUNCATE TABLE bps_items;

    -- --------------------------------------------------------
    -- 2. Insert bps_items
    --    Join item → fnd_items via legacy_id to get the BIGINT item_id.
    --    COALESCE numeric fields to 0 (NOT NULL columns).
    --    Auto-promote capabilities when defaults are set.
    -- --------------------------------------------------------
    INSERT INTO bps_items (
        item_id,
        tenant_id,
        dough_type,
        shape,
        packing,
        machine_setting,
        sheeter_setting,
        weight_adjuster,
        scale_weight,
        scale_qty,
        is_sliceable,
        is_wrappable,
        is_coverable,
        default_sliced,
        default_wrapped,
        default_covered
    )
    SELECT
        itm.item_id,
        v_tenant_id,
        NULLIF(TRIM(i.item_dough),            '')  AS dough_type,
        NULLIF(TRIM(i.item_shape),            '')  AS shape,
        NULLIF(TRIM(i.item_packing),          '')  AS packing,
        NULLIF(TRIM(i.item_machine_setting),  '')  AS machine_setting,
        NULLIF(TRIM(i.item_sheeter),          '')  AS sheeter_setting,
        COALESCE(i.item_weight_adjuster,  0)        AS weight_adjuster,
        COALESCE(i.item_scale_wt,         0)        AS scale_weight,
        COALESCE(i.item_scale_qty,        0)        AS scale_qty,

        -- Capability flags — auto-promote if default is set
        (i.item_sliceable = 'Y' OR i.item_sliced  = 'Y')  AS is_sliceable,
        (i.item_wrappable = 'Y' OR i.item_wrapped = 'Y')  AS is_wrappable,
        (i.item_coverable = 'Y' OR i.item_covered = 'Y')  AS is_coverable,

        -- Preparation defaults
        (i.item_sliced  = 'Y')  AS default_sliced,
        (i.item_wrapped = 'Y')  AS default_wrapped,
        (i.item_covered = 'Y')  AS default_covered

    FROM item i
    JOIN fnd_items itm
      ON itm.tenant_id = v_tenant_id
     AND itm.legacy_id  = i.item_id::INT;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    RAISE NOTICE 'bps_items: % rows inserted', v_inserted;

END $$;


-- ============================================================
-- QA: spot-check key distributions
-- ============================================================

SELECT 'dough_type' AS field, dough_type AS value, COUNT(*) AS cnt
FROM bps_items WHERE dough_type IS NOT NULL
GROUP BY dough_type ORDER BY cnt DESC LIMIT 10;

SELECT 'shape' AS field, shape AS value, COUNT(*) AS cnt
FROM bps_items WHERE shape IS NOT NULL
GROUP BY shape ORDER BY cnt DESC LIMIT 10;

SELECT
    is_sliceable, default_sliced,
    is_wrappable, default_wrapped,
    is_coverable, default_covered,
    COUNT(*) AS cnt
FROM bps_items
GROUP BY 1,2,3,4,5,6
ORDER BY cnt DESC
LIMIT 10;
