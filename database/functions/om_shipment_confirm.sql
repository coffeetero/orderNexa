-- ============================================================
-- om_shipment_confirm
-- Confirms a shipment: marks it SHIPPED or DELIVERED, records what actually went (per line, default = planned) and how
-- (method, carrier, tracking, route, the bakery's delivery cost), and rolls the shipped quantities up into
-- om_order_lines.fulfilled_quantity. From this point the invoice lines on the shipment count as receivable.
-- Staff only. A method that requires tracking needs a tracking reference. shipped_quantity cannot exceed the planned
-- quantity (extra goods are a new order). Can be repeated to correct the record or move SHIPPED -> DELIVERED.
-- p_payload: { shipment_status 'SHIPPED'|'DELIVERED', delivery_method_code, carrier, tracking_reference, route,
--              delivery_cost, lines: [{ shipment_line_id, shipped_quantity }] }
-- Returns { shipment_id, shipment_status, shortages: [{ shipment_line_id, item_name, planned, shipped, short }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_shipment_confirm(p_tenant_id bigint, p_shipment_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_ship      om_shipments%ROWTYPE;
    v_status    text := UPPER(COALESCE(NULLIF(TRIM(p_payload ->> 'shipment_status'), ''), 'SHIPPED'));
    v_method    text;
    v_tracking  text;
    v_track_req boolean := FALSE;
    v_line      jsonb;
    v_sl        om_shipment_lines%ROWTYPE;
    v_qty       numeric;
    v_actor     bigint := bps.fnd_nav_app_user_id();
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can confirm shipments';
    END IF;
    IF v_status NOT IN ('SHIPPED', 'DELIVERED') THEN
        RAISE EXCEPTION 'shipment_status must be SHIPPED or DELIVERED';
    END IF;
    SELECT * INTO v_ship FROM om_shipments WHERE tenant_id = p_tenant_id AND shipment_id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shipment % not found', p_shipment_id;
    END IF;
    IF v_ship.shipment_status = 'CANCELLED' THEN
        RAISE EXCEPTION 'Shipment % is cancelled', v_ship.shipment_number;
    END IF;

    v_method   := COALESCE(NULLIF(UPPER(TRIM(p_payload ->> 'delivery_method_code')), ''), v_ship.delivery_method_code);
    v_tracking := CASE WHEN p_payload ? 'tracking_reference' THEN NULLIF(TRIM(p_payload ->> 'tracking_reference'), '') ELSE v_ship.tracking_reference END;
    IF v_method IS NOT NULL THEN
        SELECT m.requires_tracking INTO v_track_req FROM om_delivery_methods m
         WHERE m.tenant_id = p_tenant_id AND m.delivery_method_code = v_method AND m.is_active;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Delivery method % is not available', v_method;
        END IF;
        IF v_track_req AND v_tracking IS NULL THEN
            RAISE EXCEPTION 'Delivery method % requires a tracking reference', v_method;
        END IF;
    END IF;

    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload -> 'lines', '[]'::jsonb)) LOOP
        SELECT * INTO v_sl FROM om_shipment_lines
         WHERE tenant_id = p_tenant_id AND shipment_id = p_shipment_id AND shipment_line_id = (v_line ->> 'shipment_line_id')::bigint;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Shipment line % does not belong to shipment %', v_line ->> 'shipment_line_id', v_ship.shipment_number;
        END IF;
        v_qty := (v_line ->> 'shipped_quantity')::numeric;
        IF v_qty IS NULL OR v_qty < 0 OR v_qty > v_sl.quantity THEN
            RAISE EXCEPTION 'Shipped quantity for line % must be between 0 and %', v_sl.shipment_line_id, v_sl.quantity;
        END IF;
        UPDATE om_shipment_lines SET shipped_quantity = v_qty WHERE shipment_line_id = v_sl.shipment_line_id;
    END LOOP;
    -- lines not mentioned default to the planned quantity
    UPDATE om_shipment_lines SET shipped_quantity = quantity WHERE shipment_id = p_shipment_id AND shipped_quantity IS NULL;

    UPDATE om_shipments SET
        shipment_status      = v_status,
        delivery_method_code = v_method,
        carrier              = CASE WHEN p_payload ? 'carrier' THEN NULLIF(TRIM(p_payload ->> 'carrier'), '') ELSE carrier END,
        tracking_reference   = v_tracking,
        route                = CASE WHEN p_payload ? 'route' THEN NULLIF(TRIM(p_payload ->> 'route'), '') ELSE route END,
        delivery_cost        = CASE WHEN p_payload ? 'delivery_cost' THEN NULLIF(TRIM(p_payload ->> 'delivery_cost'), '')::numeric ELSE delivery_cost END,
        shipped_at           = COALESCE(shipped_at, now()),
        shipped_by           = COALESCE(shipped_by, v_actor)
     WHERE shipment_id = p_shipment_id;

    UPDATE om_order_lines ol SET fulfilled_quantity = COALESCE((
            SELECT SUM(sl.shipped_quantity) FROM om_shipment_lines sl JOIN om_shipments s ON s.shipment_id = sl.shipment_id
             WHERE sl.order_line_id = ol.order_line_id AND s.shipment_status IN ('SHIPPED', 'DELIVERED')), 0)
     WHERE ol.order_line_id IN (SELECT order_line_id FROM om_shipment_lines WHERE shipment_id = p_shipment_id AND order_line_id IS NOT NULL);

    RETURN jsonb_build_object(
        'shipment_id', p_shipment_id, 'shipment_status', v_status,
        'shortages', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'shipment_line_id', sl.shipment_line_id,
                'item_name', COALESCE(NULLIF(TRIM(ol.item_description), ''), i.item_name),
                'planned', sl.quantity, 'shipped', sl.shipped_quantity, 'short', sl.quantity - sl.shipped_quantity))
              FROM om_shipment_lines sl
              LEFT JOIN om_order_lines ol ON ol.order_line_id = sl.order_line_id
              LEFT JOIN fnd_items i ON i.item_id = ol.item_id
             WHERE sl.shipment_id = p_shipment_id AND sl.shipped_quantity < sl.quantity), '[]'::jsonb));
END;
$function$;
