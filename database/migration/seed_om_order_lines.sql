-- ============================================================
-- SEED om_order_lines FROM LEGACY ORDR_DETAIL
--
-- Source:  public.ordr_detail  (SQL Anywhere → PostgreSQL via dataPump.py)
-- Target:  public.om_order_lines
--
-- Synced ordr_detail layout (Alpine / ODBC):
--   ordr_no, item_id, od_qty_sold, od_qty_returned, od_item_cost, od_item_discount,
--   od_item_sliced, od_item_canopy_sliced, od_item_wrapped, od_item_special,
--   od_item_covered, item_desc, item_no
--
-- Only rows with od_qty_sold > 0 (NULL and 0 treated as non-positive).
--
-- Idempotent: deletes existing rows for the tenant, then inserts (order_line_id is surrogate PK).
--
-- Tenant: Alpine Bakery (same pattern as seed_om_orders.sql)
--
-- Prerequisite: newTables/om_order_lines.sql applied, om_orders and fnd_items populated,
--               public.ordr_detail present
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted    INT;
    v_deleted     INT;
    v_skipped     INT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    DELETE FROM om_order_lines WHERE tenant_id = v_tenant_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    IF v_deleted > 0 THEN
        RAISE NOTICE 'Removed % existing om_order_lines rows for tenant', v_deleted;
    END IF;

    SELECT COUNT(*) INTO v_skipped
    FROM ordr_detail d
    WHERE NOT EXISTS (
        SELECT 1
        FROM om_orders ordr
        WHERE ordr.tenant_id = v_tenant_id
          AND ordr.order_number = trim(d.ordr_no::BIGINT::TEXT)
    );

    IF v_skipped > 0 THEN
        RAISE NOTICE 'ordr_detail rows with no matching om_orders (skipped): %', v_skipped;
    END IF;

    INSERT INTO om_order_lines (
        order_id,
        item_id,
        item_description,
        quantity,
        unit_price,
        extended_amount,
        unit_discount,
        fulfilled_quantity,
        tenant_id
    )
    SELECT
        ordr.order_id,
        itm.item_id,
        NULLIF(trim(both from COALESCE(d.item_desc::TEXT, '')), '') as item_description,
        COALESCE(d.od_qty_sold, 0)::NUMERIC(14,4) as quantity,
        d.od_item_cost::NUMERIC(14,4) as unit_price,
        COALESCE(d.od_qty_sold, 0)::NUMERIC(14,4)
            * (d.od_item_cost::NUMERIC(14,4) - COALESCE(d.od_item_discount, 0)::NUMERIC(14,4)) as extended_amount,
        COALESCE(-d.od_item_discount, 0)::NUMERIC(14,4) as unit_discount,
        0::NUMERIC(14,4) as fulfilled_quantity,
        v_tenant_id
    FROM ordr_detail d
    INNER JOIN om_orders ordr
        ON ordr.tenant_id = v_tenant_id
       AND ordr.order_number = trim(d.ordr_no::BIGINT::TEXT)
    LEFT JOIN fnd_items itm
        ON itm.tenant_id = v_tenant_id
       AND itm.legacy_id = d.item_id::INT
    WHERE COALESCE(d.od_qty_sold, 0) > 0;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'om_order_lines: % rows inserted', v_inserted;
END $$;

SELECT COUNT(*) AS om_order_lines_row_count FROM om_order_lines;
