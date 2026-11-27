-- ============================================================
-- om_report_delivery_get
-- Route Delivery Report: the driver's sheet. Own-fleet shipments (delivery method is_own_fleet, or none set) for runs
-- with production date in [p_from, p_to] (one code when given), grouped by delivery date and route, one stop per ship-to
-- customer with its address, the invoice numbers carried and the items. Staff only; does not stamp prints.
-- Order: delivery date, route sort order (routes stamped by Process run from Routes Maintenance; shipments without a
-- stamped route last, by their route text), stop number, customer name.
-- Returns { stops: [{ delivery_date, route, route_code, route_name, stop_no, shipment_number, customer_name, customer_number,
--   address, delivery_method, invoice_numbers, items: [{ item_name, quantity }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_delivery_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can run reports';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;

    RETURN jsonb_build_object('stops', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'delivery_date',   s.delivery_date,
                   'route',           s.route,
                   'route_code',      rt.route_code,
                   'route_name',      COALESCE(rt.route_name, s.route),
                   'stop_no',         s.route_stop_no,
                   'shipment_number', s.shipment_number,
                   'customer_name',   c.customer_name,
                   'customer_number', c.customer_number,
                   'address',         bps.om_customer_ship_address(s.tenant_id, s.ship_to_customer_id),
                   'delivery_method', COALESCE(m.delivery_method_name, s.delivery_method_code),
                   'invoice_numbers', COALESCE((SELECT jsonb_agg(DISTINCT t.document_number)
                                                  FROM om_shipment_lines sl
                                                  JOIN ar_transaction_lines al ON al.shipment_line_id = sl.shipment_line_id
                                                  JOIN ar_transactions t ON t.ar_transaction_id = al.ar_transaction_id AND t.status <> 'CANCELLED'
                                                 WHERE sl.shipment_id = s.shipment_id AND t.document_number IS NOT NULL), '[]'::jsonb),
                   'items',           COALESCE((SELECT jsonb_agg(jsonb_build_object('item_name', x.item_name, 'quantity', x.quantity) ORDER BY x.item_name)
                                                  FROM (SELECT COALESCE(i.item_name, MAX(ol.item_description)) AS item_name, SUM(sl.quantity) AS quantity
                                                          FROM om_shipment_lines sl
                                                          JOIN om_order_lines ol ON ol.order_line_id = sl.order_line_id
                                                          LEFT JOIN fnd_items i ON i.item_id = ol.item_id
                                                         WHERE sl.shipment_id = s.shipment_id
                                                         GROUP BY i.item_id, i.item_name) x), '[]'::jsonb)
               ) ORDER BY s.delivery_date, (rt.route_id IS NULL), rt.sort_order, upper(rt.route_code), COALESCE(s.route, ''),
                          s.route_stop_no NULLS LAST, c.customer_name)
          FROM om_shipments s
          JOIN om_production_runs r ON r.production_run_id = s.production_run_id
          JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id AND c.tenant_id = s.tenant_id
          LEFT JOIN om_delivery_methods m ON m.tenant_id = s.tenant_id AND m.delivery_method_code = s.delivery_method_code
          LEFT JOIN om_routes rt ON rt.route_id = s.route_id
         WHERE s.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to
           AND (v_code IS NULL OR r.production_code = v_code)
           AND s.shipment_status <> 'CANCELLED'
           AND (s.delivery_method_code IS NULL OR COALESCE(m.is_own_fleet, FALSE))
    ), '[]'::jsonb));
END;
$function$;
