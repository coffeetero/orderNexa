-- ============================================================
-- om_report_labels_get
-- Packing label rows (one label per order line) for the selected customers and production dates. Staff only.
-- The customer is the order's customer (a site's orders sit under its parent); department_event holds the site or event.
-- Returns { labels: [{ production_date, production_code, delivery_date, customer_name, department_event, order_number,
--   po_number, item_number, item_name, quantity, unit_of_sale, prep_options }] } ordered by customer, event, order, line.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_labels_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_customer_ids bigint[])
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
    IF p_customer_ids IS NULL OR COALESCE(array_length(p_customer_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one customer';
    END IF;

    RETURN jsonb_build_object('labels', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'production_date',  o.production_date,
                   'production_code',  o.production_code,
                   'delivery_date',    r.delivery_date,
                   'customer_name',    COALESCE(o.customer_name, c.customer_name),
                   'department_event', o.department_event,
                   'order_number',     o.order_number,
                   'po_number',        o.po_number,
                   'item_number',      i.item_number,
                   'item_name',        COALESCE(NULLIF(TRIM(ol.item_description), ''), i.item_name),
                   'quantity',         ol.quantity,
                   'unit_of_sale',     i.unit_of_sale,
                   'prep_options',     COALESCE((SELECT string_agg(COALESCE(e ->> 'label', e #>> '{}'), ', ')
                                                   FROM jsonb_array_elements(COALESCE(ol.prep_options, '[]'::jsonb)) e), '')
               ) ORDER BY COALESCE(o.customer_name, c.customer_name), o.production_date, o.department_event, o.order_number, ol.order_line_id)
          FROM om_orders o
          JOIN om_order_lines ol ON ol.order_id = o.order_id AND ol.tenant_id = o.tenant_id
          LEFT JOIN fnd_customers c ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
          LEFT JOIN fnd_items i ON i.item_id = ol.item_id
          LEFT JOIN om_production_runs r ON r.production_run_id = o.production_run_id
         WHERE o.tenant_id = p_tenant_id AND o.production_date BETWEEN p_from AND p_to
           AND (v_code IS NULL OR o.production_code = v_code)
           AND o.customer_id = ANY (p_customer_ids) AND ol.quantity > 0
    ), '[]'::jsonb));
END;
$function$;
