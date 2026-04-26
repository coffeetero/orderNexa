-- ============================================================
-- SEED FND_ITEMS FROM LEGACY ITEM TABLE
--
-- Source:  public.item  (uploaded from SQL Anywhere)
-- Target:  public.fnd_items
--
-- Strategy:
--   1. TRUNCATE fnd_items CASCADE (also clears bps_items, fnd_item_bom, rows in
--      om_order_lines / fnd_pricebook_items that reference items — re-run those seeds if needed)
--   2. Stage normalised source rows into a temp table
--   3. Insert fnd_items (item_id from global fnd_entity_id_seq default)
--
-- unit_of_sale normalisation collapses 50+ legacy variations:
--   PCS    – pieces / each / unit
--   DOZ    – dozen (incl. multi-dozen like 2Doz, 5Dz)
--   LB     – pounds (incl. 1lb, 5Lb, 1/2 Lb)
--   TRAY   – tray (incl. sized variants 6 Tray, 8 Tray)
--   CS     – case
--   BAG    – bag / bags
--   SET    – set
--   SAMPLE – samples / sleeve
--   OTHER  – anything unrecognised (review after load)
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_staged     INT;
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

    TRUNCATE TABLE fnd_items CASCADE;

    -- --------------------------------------------------------
    -- 2. Stage normalised rows from legacy item
    -- --------------------------------------------------------
    CREATE TEMP TABLE tmp_items AS
    SELECT
        item_id::INT                                                        AS legacy_id,
        -- Deduplicate item_no: append -item_id suffix for duplicates, generate
        -- NOID-{item_id} for nulls so the unique constraint is never violated.
        CASE
            WHEN item_no IS NULL OR TRIM(item_no) = ''
                THEN 'NOID-' || item_id::TEXT
            WHEN COUNT(*) OVER (PARTITION BY item_no) > 1
                THEN item_no || '-' || item_id::TEXT
            ELSE item_no
        END                                                                 AS item_number,
        COALESCE(NULLIF(TRIM(item_desc), ''), 'Item #' || item_no)         AS item_name,
        item_ctgry                                                          AS category,
        item_weight                                                         AS item_weight,
        'LB'::TEXT                                                          AS weight_uom,
        box_id::INT                                                         AS legacy_box_id,
        qty_per_box                                                         AS box_qty_per_box,
        item_bxsz_volume                                                    AS box_capacity_volume,
        item_bxsz_weight                                                    AS box_capacity_weight,
        item_bxsz_optimal                                                   AS box_capacity_optimal,
        COALESCE(item_preorder_days::INT, 0)                                AS preorder_days,
        (item_sales_terms  = 'Y')                                           AS sales_terms_apply,
        (item_active       = 'Y')                                           AS is_active,
        CASE
            WHEN UPPER(TRIM(item_unit)) IN ('PCS','PCS.','PC','PC.','UNIT','UNITS','1')
                 OR LOWER(TRIM(item_unit)) IN ('pcs','pcs.','pc','pc.')         THEN 'PCS'
            WHEN UPPER(TRIM(item_unit)) IN ('DOZ','DOZ.','DZ','DZ.','DOZ')
                 OR item_unit ~* '^[0-9]+\s*doz'
                 OR item_unit ~* '^[0-9]+\s*dz'                                THEN 'DOZ'
            WHEN UPPER(TRIM(item_unit)) IN ('LB','LBS','LB.','1LB','1 LB')
                 OR item_unit ~* '^[0-9./\s]+\s*lb'                            THEN 'LB'
            WHEN UPPER(TRIM(item_unit)) IN ('TRAY','TRAY/24')
                 OR item_unit ~* '^[0-9]+\s*tray'                              THEN 'TRAY'
            WHEN UPPER(TRIM(item_unit)) IN ('CS','CASE')                        THEN 'CS'
            WHEN UPPER(TRIM(item_unit)) IN ('BAG','BAGS')                       THEN 'BAG'
            WHEN UPPER(TRIM(item_unit)) IN ('SET')                              THEN 'SET'
            WHEN UPPER(TRIM(item_unit)) IN ('BOX')                             THEN 'BOX'
            WHEN UPPER(TRIM(item_unit)) IN ('SAMPLES','SAMPLE')
                 OR item_unit ~* 'sleeve'                                       THEN 'SAMPLE'
            WHEN item_unit ~* '1/2\s*dz'
                 OR item_unit ~* '1/2\s*doz'                                   THEN 'DOZ'
            WHEN item_unit ~* '[0-9]+\s*units?'                                THEN 'PCS'
            WHEN TRIM(item_unit) = '' OR item_unit IS NULL                      THEN 'PCS'
            ELSE 'OTHER'
        END                                                                 AS unit_of_sale
    FROM item;

    GET DIAGNOSTICS v_staged = ROW_COUNT;
    RAISE NOTICE 'Staging: % rows from legacy item', v_staged;

    IF v_staged = 0 THEN
        RAISE NOTICE 'Nothing to insert — legacy item table is empty.';
        DROP TABLE tmp_items;
        RETURN;
    END IF;

    -- --------------------------------------------------------
    -- 3. Insert fnd_items
    -- --------------------------------------------------------
    INSERT INTO fnd_items (
        tenant_id,
        legacy_id,
        item_number,
        item_name,
        category,
        unit_of_sale,
        item_weight,
        weight_uom,
        legacy_box_id,
        box_qty_per_box,
        box_capacity_volume,
        box_capacity_weight,
        box_capacity_optimal,
        preorder_days,
        sales_terms_apply,
        is_active
    )
    SELECT
        v_tenant_id,
        t.legacy_id,
        t.item_number,
        t.item_name,
        t.category,
        t.unit_of_sale,
        t.item_weight,
        t.weight_uom,
        t.legacy_box_id,
        t.box_qty_per_box,
        t.box_capacity_volume,
        t.box_capacity_weight,
        t.box_capacity_optimal,
        t.preorder_days,
        t.sales_terms_apply,
        t.is_active
    FROM tmp_items t;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    RAISE NOTICE 'fnd_items : % rows inserted', v_inserted;
    RAISE NOTICE 'Summary   : % inserted  |  % rows in legacy item',
        v_inserted,
        (SELECT COUNT(*) FROM item);

    DROP TABLE tmp_items;

END $$;


-- ============================================================
-- QA: unit normalisation summary
-- ============================================================
SELECT
    unit_of_sale        AS normalised_unit,
    COUNT(*)            AS item_count
FROM fnd_items
GROUP BY unit_of_sale
ORDER BY item_count DESC;
