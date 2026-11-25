-- ============================================================
-- om_orders_manage_get (Orders > Manage Orders)
-- One page of orders for production dates, with the summary strip and group subtotals, all worked out here:
--   p_period   yesterday | today | tomorrow | this_week | next_week (Mon-Sun) | custom (p_from..p_to); the company's own dates
--   p_shift    a production code (AM, PM, ...) or NULL for all shifts
--   p_status   OPEN | IN_PRODUCTION | SHIPPED | INVOICED or NULL; status is the furthest stage the order reached (same rule as
--              the Dashboard): a line on an issued invoice > shipped > on a production run > open
--   p_search   order number, customer or department / event (contains, any case)
--   p_group    shift | customer | status | none: rows come grouped, and "groups" has each group's orders, lines and amount
--              over ALL matching orders (not just this page)
--   p_sort     order | customer | lines | amount, with p_desc; applied inside each group
-- The summary (orders per status, amount) ignores p_status, so its figures can be clicked to filter.
-- Returns { from, to, today, shifts: [{value, label}], summary: {all, open, in_production, shipped, invoiced, amount},
--           total, groups: [{key, label, orders, lines, amount}], rows: [{order_id, order_number, customer_name,
--           department_event, production_date, shift, shift_label, lines, amount, status}] }
-- SECURITY INVOKER: row security limits it to the caller's company and customers. No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_orders_manage_get(
  p_tenant_id bigint, p_period text DEFAULT 'today', p_from date DEFAULT NULL, p_to date DEFAULT NULL,
  p_shift text DEFAULT NULL, p_status text DEFAULT NULL, p_search text DEFAULT NULL,
  p_group text DEFAULT 'shift', p_sort text DEFAULT 'order', p_desc boolean DEFAULT true,
  p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_today  date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
  v_monday date;
  v_from   date;
  v_to     date;
  v_search text := NULLIF(btrim(p_search), '');
  v_group  text := lower(COALESCE(p_group, 'shift'));
  v_sort   text := lower(COALESCE(p_sort, 'order'));
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 500);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_result jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  v_monday := v_today - (extract(isodow FROM v_today)::int - 1);
  CASE lower(COALESCE(p_period, 'today'))
    WHEN 'yesterday' THEN v_from := v_today - 1; v_to := v_today - 1;
    WHEN 'tomorrow'  THEN v_from := v_today + 1; v_to := v_today + 1;
    WHEN 'this_week' THEN v_from := v_monday;     v_to := v_monday + 6;
    WHEN 'next_week' THEN v_from := v_monday + 7; v_to := v_monday + 13;
    WHEN 'custom'    THEN v_from := COALESCE(p_from, v_today); v_to := COALESCE(p_to, p_from, v_today);
    ELSE                  v_from := v_today;      v_to := v_today;
  END CASE;
  IF v_to < v_from THEN v_to := v_from; END IF;
  IF v_to - v_from > 366 THEN RAISE EXCEPTION 'Choose a range of one year or less'; END IF;

  WITH shifts AS (
    SELECT v.value, COALESCE(NULLIF(v.label, ''), v.value) AS label, v.display_order
      FROM bps.fnd_valuesets s JOIN bps.fnd_valueset_values v ON v.valueset_id = s.valueset_id AND v.tenant_id = s.tenant_id
     WHERE s.tenant_id = p_tenant_id AND upper(s.valueset_code) = 'PRODUCTIONCODE' AND NOT COALESCE(v.is_disabled, false)
  ), base AS (
    SELECT o.order_id, o.order_number, o.customer_name, o.department_event, o.production_date, o.production_code, o.amount,
           (SELECT count(*) FROM bps.om_order_lines l WHERE l.tenant_id = p_tenant_id AND l.order_id = o.order_id) AS lines,
           CASE WHEN EXISTS (SELECT 1 FROM bps.ar_transaction_lines tl
                               JOIN bps.ar_transactions t ON t.tenant_id = tl.tenant_id AND t.ar_transaction_id = tl.ar_transaction_id
                              WHERE tl.tenant_id = p_tenant_id AND tl.order_id = o.order_id
                                AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED') THEN 'INVOICED'
                WHEN o.shipped_at IS NOT NULL THEN 'SHIPPED'
                WHEN o.production_run_id IS NOT NULL THEN 'IN_PRODUCTION'
                ELSE 'OPEN' END AS status
      FROM bps.om_orders o
     WHERE o.tenant_id = p_tenant_id AND o.production_date BETWEEN v_from AND v_to
       AND (p_shift IS NULL OR o.production_code = p_shift)
       AND (v_search IS NULL OR o.order_number ILIKE '%' || v_search || '%' OR o.customer_name ILIKE '%' || v_search || '%'
            OR o.department_event ILIKE '%' || v_search || '%')
  ), filtered AS (
    SELECT b.*, COALESCE(sh.label, b.production_code) AS shift_label, COALESCE(sh.display_order, 9999) AS shift_order,
           array_position(ARRAY['OPEN', 'IN_PRODUCTION', 'SHIPPED', 'INVOICED'], b.status) AS status_order,
           CASE v_group WHEN 'shift' THEN b.production_code WHEN 'customer' THEN b.customer_name WHEN 'status' THEN b.status END AS group_key
      FROM base b LEFT JOIN shifts sh ON sh.value = b.production_code
     WHERE p_status IS NULL OR b.status = upper(p_status)
  ), groups AS (
    SELECT f.group_key, min(CASE v_group WHEN 'shift' THEN f.shift_label WHEN 'status' THEN initcap(replace(f.status, '_', ' ')) ELSE f.customer_name END) AS label,
           min(CASE v_group WHEN 'shift' THEN f.shift_order WHEN 'status' THEN f.status_order ELSE 0 END) AS sort_order,
           count(*) AS orders, sum(f.lines) AS lines, COALESCE(sum(f.amount), 0) AS amount
      FROM filtered f WHERE v_group IN ('shift', 'customer', 'status') GROUP BY f.group_key
  ), page AS (
    SELECT f.*, row_number() OVER (ORDER BY
             CASE v_group WHEN 'shift' THEN f.shift_order WHEN 'status' THEN f.status_order ELSE 0 END,
             CASE WHEN v_group = 'customer' THEN f.customer_name END,
             CASE WHEN p_desc THEN CASE v_sort WHEN 'customer' THEN f.customer_name END END DESC,
             CASE WHEN NOT p_desc THEN CASE v_sort WHEN 'customer' THEN f.customer_name END END,
             CASE WHEN p_desc THEN CASE v_sort WHEN 'lines' THEN f.lines WHEN 'amount' THEN f.amount END END DESC NULLS LAST,
             CASE WHEN NOT p_desc THEN CASE v_sort WHEN 'lines' THEN f.lines WHEN 'amount' THEN f.amount END END NULLS LAST,
             -- order numbers in number order (shorter numbers first), then the order number itself
             CASE WHEN p_desc THEN length(f.order_number) END DESC, CASE WHEN p_desc THEN f.order_number END DESC,
             CASE WHEN NOT p_desc THEN length(f.order_number) END, CASE WHEN NOT p_desc THEN f.order_number END) AS rn
      FROM filtered f
  )
  SELECT jsonb_build_object(
    'from', v_from, 'to', v_to, 'today', v_today,
    'shifts', COALESCE((SELECT jsonb_agg(jsonb_build_object('value', s.value, 'label', s.label) ORDER BY s.display_order) FROM shifts s), '[]'::jsonb),
    'summary', (SELECT jsonb_build_object('all', count(*), 'open', count(*) FILTER (WHERE status = 'OPEN'),
                  'in_production', count(*) FILTER (WHERE status = 'IN_PRODUCTION'), 'shipped', count(*) FILTER (WHERE status = 'SHIPPED'),
                  'invoiced', count(*) FILTER (WHERE status = 'INVOICED'), 'amount', COALESCE(sum(amount), 0)) FROM base),
    'total', (SELECT count(*) FROM filtered),
    'groups', COALESCE((SELECT jsonb_agg(jsonb_build_object('key', g.group_key, 'label', g.label, 'orders', g.orders, 'lines', g.lines, 'amount', g.amount)
                                ORDER BY g.sort_order, g.label) FROM groups g), '[]'::jsonb),
    'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object('order_id', p.order_id, 'order_number', p.order_number, 'customer_name', p.customer_name,
                        'department_event', p.department_event, 'production_date', p.production_date, 'shift', p.production_code,
                        'shift_label', p.shift_label, 'lines', p.lines, 'amount', p.amount, 'status', p.status, 'group_key', p.group_key) ORDER BY p.rn)
                      FROM page p WHERE p.rn > v_offset AND p.rn <= v_offset + v_limit), '[]'::jsonb))
    INTO v_result;
  RETURN v_result;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_orders_manage_get(bigint, text, date, date, text, text, text, text, text, boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_orders_manage_get(bigint, text, date, date, text, text, text, text, text, boolean, integer, integer) TO authenticated, service_role, bps_dev;
