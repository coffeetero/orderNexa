-- ============================================================
-- om_shipments_get
-- Shipments of runs with production date in [p_from, p_to] (one code and/or one status when given) for the delivery
-- confirmation page, with their lines and the invoice numbers they carry. Staff only.
-- Returns [{ shipment_id, shipment_number, production_date, production_code, delivery_date, customer_name, customer_number,
--   delivery_method_code, delivery_method_name, requires_tracking, carrier, tracking_reference, route, delivery_cost,
--   shipment_status, shipped_at, invoice_numbers, lines: [{ shipment_line_id, order_number, department_event, item_name,
--   quantity, shipped_quantity }] }]
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_shipments_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text DEFAULT NULL, p_status text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code   text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_status text := NULLIF(UPPER(TRIM(p_status)), '');
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can see shipments';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'shipment_id',          s.shipment_id,
                   'shipment_number',      s.shipment_number,
                   'production_date',      r.production_date,
                   'production_code',      r.production_code,
                   'delivery_date',        s.delivery_date,
                   'customer_name',        c.customer_name,
                   'customer_number',      c.customer_number,
                   'delivery_method_code', s.delivery_method_code,
                   'delivery_method_name', m.delivery_method_name,
                   'requires_tracking',    COALESCE(m.requires_tracking, FALSE),
                   'carrier',              s.carrier,
                   'tracking_reference',   s.tracking_reference,
                   'route',                s.route,
                   'delivery_cost',        s.delivery_cost,
                   'shipment_status',      s.shipment_status,
                   'shipped_at',           s.shipped_at,
                   'invoice_numbers',      COALESCE((SELECT jsonb_agg(DISTINCT t.document_number)
                                                       FROM om_shipment_lines sl
                                                       JOIN ar_transaction_lines al ON al.shipment_line_id = sl.shipment_line_id
                                                       JOIN ar_transactions t ON t.ar_transaction_id = al.ar_transaction_id AND t.status <> 'CANCELLED'
                                                      WHERE sl.shipment_id = s.shipment_id AND t.document_number IS NOT NULL), '[]'::jsonb),
                   'lines',                COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                                           'shipment_line_id', sl.shipment_line_id, 'order_number', o.order_number,
                                                           'department_event', o.department_event,
                                                           'item_name', COALESCE(NULLIF(TRIM(ol.item_description), ''), i.item_name),
                                                           'quantity', sl.quantity, 'shipped_quantity', sl.shipped_quantity)
                                                           ORDER BY o.department_event, o.order_number, sl.shipment_line_id)
                                                       FROM om_shipment_lines sl
                                                       JOIN om_orders o ON o.order_id = sl.order_id
                                                       LEFT JOIN om_order_lines ol ON ol.order_line_id = sl.order_line_id
                                                       LEFT JOIN fnd_items i ON i.item_id = ol.item_id
                                                      WHERE sl.shipment_id = s.shipment_id), '[]'::jsonb)
               ) ORDER BY s.delivery_date, c.customer_name, s.shipment_number)
          FROM om_shipments s
          JOIN om_production_runs r ON r.production_run_id = s.production_run_id
          JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id AND c.tenant_id = s.tenant_id
          LEFT JOIN om_delivery_methods m ON m.tenant_id = s.tenant_id AND m.delivery_method_code = s.delivery_method_code
         WHERE s.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to
           AND (v_code IS NULL OR r.production_code = v_code)
           AND (v_status IS NULL OR s.shipment_status = v_status)
    ), '[]'::jsonb);
END;
$function$;
