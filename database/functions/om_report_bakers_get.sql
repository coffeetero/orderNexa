-- ============================================================
-- om_report_bakers_get
-- Baker's Report data: for each run with production date in [p_from, p_to] (one code when given), the item totals grouped
-- by item category, with the dough type, unit and order count; category and run totals; and changed_since_print
-- (an order or order line created or changed after the last Baker's Report print). Staff only; does not stamp prints
-- (see om_production_runs_mark_printed).
-- Returns { runs: [{ production_run_id, production_date, production_code, delivery_date, order_count, total_quantity,
--   last_printed_at, changed_since_print, categories: [{ category, total_quantity, items: [{ item_number, item_name,
--   dough_type, unit_of_sale, quantity, order_count }] }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_bakers_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_runs jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can run reports';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'production_run_id',   r.production_run_id,
               'production_date',     r.production_date,
               'production_code',     r.production_code,
               'delivery_date',       r.delivery_date,
               'order_count',         (SELECT COUNT(*) FROM om_orders o WHERE o.production_run_id = r.production_run_id),
               'total_quantity',      (SELECT COALESCE(SUM(ol.quantity), 0) FROM om_order_lines ol JOIN om_orders o ON o.order_id = ol.order_id WHERE o.production_run_id = r.production_run_id),
               'last_printed_at',     r.baker_sheet_printed_at,
               'changed_since_print', r.baker_sheet_printed_at IS NOT NULL AND (
                    EXISTS (SELECT 1 FROM om_orders o WHERE o.production_run_id = r.production_run_id AND o.updated_at > r.baker_sheet_printed_at)
                 OR EXISTS (SELECT 1 FROM om_order_lines ol JOIN om_orders o ON o.order_id = ol.order_id
                             WHERE o.production_run_id = r.production_run_id AND ol.updated_at > r.baker_sheet_printed_at)),
               'categories', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object('category', cat.category, 'total_quantity', cat.total, 'items', cat.items) ORDER BY cat.category)
                      FROM (
                        SELECT g.category, SUM(g.quantity) AS total,
                               jsonb_agg(jsonb_build_object('item_number', g.item_number, 'item_name', g.item_name, 'dough_type', g.dough_type,
                                                            'unit_of_sale', g.unit_of_sale, 'quantity', g.quantity, 'order_count', g.orders)
                                         ORDER BY g.dough_type NULLS LAST, g.item_name) AS items
                          FROM (
                            SELECT COALESCE(NULLIF(TRIM(i.category), ''), 'Uncategorised') AS category, i.item_number, COALESCE(i.item_name, MAX(ol.item_description)) AS item_name,
                                   i.dough_type, i.unit_of_sale, SUM(ol.quantity) AS quantity, COUNT(DISTINCT ol.order_id) AS orders
                              FROM om_order_lines ol
                              JOIN om_orders o ON o.order_id = ol.order_id AND o.tenant_id = ol.tenant_id
                              LEFT JOIN fnd_items i ON i.item_id = ol.item_id
                             WHERE o.production_run_id = r.production_run_id AND ol.quantity <> 0
                             GROUP BY i.item_id, i.category, i.item_number, i.item_name, i.dough_type, i.unit_of_sale
                          ) g
                         GROUP BY g.category
                      ) cat
               ), '[]'::jsonb)
           ) ORDER BY r.production_date, r.production_code), '[]'::jsonb)
      INTO v_runs
      FROM om_production_runs r
     WHERE r.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to
       AND (v_code IS NULL OR r.production_code = v_code);

    RETURN jsonb_build_object('runs', v_runs);
END;
$function$;
