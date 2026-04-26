-- ============================================================
-- SEED om_order_shipments FROM LEGACY ordr_detail (summary)
--
-- Creates one shipment event per order line mirroring od_qty_sold as
-- "SOLD" at the order's delivery/production context. This is a pragmatic
-- stand-in when no separate ship table exists; replace with real shipment events later.
--
-- Prerequisite: om_orders + om_order_lines seeded; public.ordr + ordr_detail present.
-- Tenant: Alpine Bakery
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted    INT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    DELETE FROM om_order_shipments WHERE tenant_id = v_tenant_id;

    INSERT INTO om_order_shipments (
        tenant_id,
        order_id,
        order_line_id,
        production_date,
        production_window,
        shipment_date,
        shipment_number,
        quantity,
        status,
        delivery_type,
        delivery_reference,
        ship_from_location_id,
        ship_to_location_id,
        snapshot_data
    )
    SELECT
        v_tenant_id,
        ordr.order_id,
        ordrLn.order_line_id,
        COALESCE(ordr.delivery_date, ordr.order_date),
        ordr.delivery_window,
        COALESCE(
            ordr.delivery_date::TIMESTAMPTZ,
            ordr.order_date::TIMESTAMPTZ,
            now()
        ),
        1::BIGINT,
        COALESCE(d.od_qty_sold, 0)::NUMERIC(14,4),
        'OPEN',
        'SHIP',
        trim(both from d.ordr_no::bigint::text),
        NULL::BIGINT,
        NULL::BIGINT,
        jsonb_build_object(
            'seed', 'ordr_detail.od_qty_sold',
            'legacy_ordr_no', trim(both from d.ordr_no::bigint::text)
        )
    FROM ordr_detail d
    INNER JOIN om_orders ordr
        ON ordr.tenant_id = v_tenant_id
       AND ordr.order_number = trim(both from d.ordr_no::bigint::text)
    INNER JOIN om_order_lines ordrLn
        ON ordrLn.tenant_id = v_tenant_id
       AND ordrLn.order_id = ordr.order_id
    INNER JOIN fnd_items itm
        ON itm.tenant_id = v_tenant_id
       AND itm.legacy_id = d.item_id::INT
       AND itm.item_id = ordrLn.item_id
    WHERE COALESCE(d.od_qty_sold, 0) > 0;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'om_order_shipments: inserted % rows (joins order_line by order + item legacy_id)', v_inserted;
END $$;
