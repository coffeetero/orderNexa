-- ============================================================
-- om_call_up_list_get
-- Call Up List (Order Entry side panel): the active customers with Call ticked on their standing order for the day of
-- the week of p_date (any production time). One row per customer: one call covers all of that day's times. Staff only.
-- Each row: customer_id, customer_number, customer_name, customer_type, parent_name, phone (the customer's PHONE contact,
--   else its parent's), assigned (clerk names from the ticked times; empty = anyone), called_at, called_by,
--   not_posted (a ticked time with standing order lines has no posted order yet),
--   orders: [{ order_id, order_number, production_code, department_event, amount }] (that day's orders for the customer:
--   the ones its standing orders were posted to, and those with its name as department/event), sorted by time.
-- Rows are sorted by customer number.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_call_up_list_get(p_tenant_id bigint, p_date date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_dow text;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can see the call up list';
    END IF;
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'A date is required';
    END IF;
    v_dow := (ARRAY['SUN','MON','TUE','WED','THU','FRI','SAT'])[EXTRACT(DOW FROM p_date)::int + 1];

    RETURN COALESCE((
        WITH flagged AS (
            SELECT c.customer_id, c.production_code, c.assigned_user_id
              FROM om_standing_order_calls c
              JOIN fnd_customers cu ON cu.customer_id = c.customer_id AND cu.tenant_id = c.tenant_id AND cu.is_active
             WHERE c.tenant_id = p_tenant_id AND c.production_dow = v_dow AND c.is_call
        ), cust AS (
            SELECT DISTINCT ON (cu.customer_id) cu.customer_id, cu.customer_number, cu.customer_name, cu.customer_type,
                   cu.customer_parent_id, p.customer_name AS parent_name,
                   CASE WHEN UPPER(TRIM(cu.customer_type)) = 'DEPARTMENT' AND cu.customer_parent_id IS NOT NULL
                        THEN cu.customer_parent_id ELSE cu.customer_id END AS order_customer_id,
                   COALESCE(NULLIF(UPPER(TRIM(cu.customer_name)), ''), 'ORDER') AS event
              FROM flagged f
              JOIN fnd_customers cu ON cu.customer_id = f.customer_id
              LEFT JOIN fnd_customers p ON p.customer_id = cu.customer_parent_id
        )
        SELECT jsonb_agg(jsonb_build_object(
                   'customer_id', x.customer_id,
                   'customer_number', COALESCE(x.customer_number, ''),
                   'customer_name', x.customer_name,
                   'customer_type', x.customer_type,
                   'parent_name', x.parent_name,
                   'phone', (SELECT cp.value
                               FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id
                              WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers'
                                AND k.entity_id IN (x.customer_id, x.customer_parent_id) AND cp.type = 'PHONE' AND cp.is_active
                              ORDER BY (k.entity_id = x.customer_id) DESC, cp.is_primary DESC, cp.sequence LIMIT 1),
                   'assigned', COALESCE((SELECT jsonb_agg(DISTINCT u.user_name) FROM flagged f JOIN fnd_users u ON u.user_id = f.assigned_user_id
                                          WHERE f.customer_id = x.customer_id), '[]'::jsonb),
                   'called_at', cc.called_at,
                   'called_by', (SELECT u.user_name FROM fnd_users u WHERE u.user_id = cc.called_by),
                   'not_posted', EXISTS (
                        SELECT 1 FROM flagged f
                         WHERE f.customer_id = x.customer_id
                           AND EXISTS (SELECT 1 FROM om_standing_orders so
                                        WHERE so.tenant_id = p_tenant_id AND so.customer_id = f.customer_id AND so.production_dow = v_dow
                                          AND so.production_code = f.production_code AND so.is_active)
                           AND NOT EXISTS (SELECT 1 FROM om_standing_order_postings lg
                                            WHERE lg.tenant_id = p_tenant_id AND lg.customer_id = f.customer_id
                                              AND lg.production_date = p_date AND lg.production_code = f.production_code)
                           AND NOT EXISTS (SELECT 1 FROM om_orders o
                                            WHERE o.tenant_id = p_tenant_id AND o.customer_id = x.order_customer_id
                                              AND o.production_date = p_date AND o.production_code = f.production_code
                                              AND o.department_event = x.event)),
                   'orders', COALESCE((
                        SELECT jsonb_agg(jsonb_build_object('order_id', o.order_id, 'order_number', o.order_number,
                                                            'production_code', o.production_code, 'department_event', o.department_event,
                                                            'amount', o.amount)
                                         ORDER BY o.production_code, o.order_number)
                          FROM om_orders o
                         WHERE o.tenant_id = p_tenant_id AND o.production_date = p_date
                           AND (o.order_id IN (SELECT lg.order_id FROM om_standing_order_postings lg
                                                WHERE lg.tenant_id = p_tenant_id AND lg.customer_id = x.customer_id AND lg.production_date = p_date)
                                OR (o.customer_id = x.order_customer_id AND o.department_event = x.event))), '[]'::jsonb))
               ORDER BY x.customer_number, x.customer_id)
          FROM cust x
          LEFT JOIN om_call_up_called cc ON cc.tenant_id = p_tenant_id AND cc.customer_id = x.customer_id AND cc.call_date = p_date
    ), '[]'::jsonb);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_call_up_list_get(bigint, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_call_up_list_get(bigint, date) TO authenticated, service_role, bps_dev;
