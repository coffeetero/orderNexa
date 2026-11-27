-- ============================================================
-- om_standing_orders_post
-- Posts standing orders for every production date from p_date_from to p_date_to (each date uses its own day of the
-- week), for the given production codes and, optionally, only the given standing-order customers. Staff only.
--
-- Per standing-order customer + date + code (the "slot"):
--   - Its order: the order this slot was posted to before (om_standing_order_postings.order_id, so a renamed
--     department/event is still found), else the order with the customer's name as department/event (a DEPARTMENT's
--     order is stored under its parent, as in om_orders_save).
--   - No order yet and never posted -> a new order with every standing order line (0 quantities included: they are
--     reminders for the clerk), priced from the customer's pricebook for that date (om_items_get_v2). Status POSTED.
--   - Order exists -> only standing order items not already on it are added; lines already on the order are never
--     changed (a quantity set to 0 by the clerk stays 0). Status ADDED, or UP_TO_DATE when nothing was missing.
--   - Order already posted to AR (on an invoice with a number) -> left alone. Status POSTED_TO_AR.
--   - Posted before but its order was deleted -> left alone. Status ORDER_DELETED.
--   Lines from posting are never samples. Inactive items, inactive customers, customers without the standing order
--   flag, inactive lines and lines outside their effective dates are left out.
--   Each slot is posted under a lock and in its own savepoint: one failure (FAILED, with the message) does not stop
--   the others. Every posted slot is recorded in om_standing_order_postings.
-- Returns { posted, added, up_to_date, skipped, failed, results: [{ production_date, production_code, customer_id,
--   customer_name, status, order_id, order_number, department_event, lines_added, message }] }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_standing_orders_post(
    p_tenant_id        bigint,
    p_date_from        date,
    p_date_to          date,
    p_production_codes text[],
    p_customer_ids     bigint[] DEFAULT NULL,
    p_order_date       date     DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_actor     bigint := bps.fnd_nav_app_user_id();
    v_date      date;
    v_dow       text;
    v_slot      record;
    v_log       om_standing_order_postings%ROWTYPE;
    v_order     om_orders%ROWTYPE;
    v_order_cust bigint;
    v_event     text;
    v_status    text;
    v_message   text;
    v_added     integer;
    v_saved     jsonb;
    v_prices    jsonb;
    v_lines     jsonb;
    v_results   jsonb := '[]'::jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can post standing orders';
    END IF;
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to < p_date_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;
    IF p_date_to - p_date_from > 13 THEN
        RAISE EXCEPTION 'Standing orders can be posted for at most 14 days at a time';
    END IF;
    IF COALESCE(array_length(p_production_codes, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one production time';
    END IF;

    FOR v_date IN SELECT d::date FROM generate_series(p_date_from, p_date_to, interval '1 day') d LOOP
        v_dow := (ARRAY['SUN','MON','TUE','WED','THU','FRI','SAT'])[EXTRACT(DOW FROM v_date)::int + 1];

        FOR v_slot IN
            SELECT DISTINCT so.customer_id, so.production_code, c.customer_name, c.customer_type, c.customer_parent_id,
                   c.customer_number
              FROM om_standing_orders so
              JOIN fnd_customers c ON c.customer_id = so.customer_id AND c.tenant_id = so.tenant_id
             WHERE so.tenant_id = p_tenant_id
               AND so.production_dow = v_dow
               AND so.production_code = ANY (p_production_codes)
               AND so.is_active
               AND (so.effective_from IS NULL OR so.effective_from <= v_date)
               AND (so.effective_to IS NULL OR so.effective_to >= v_date)
               AND c.is_active AND c.is_standing_order
               AND (p_customer_ids IS NULL OR so.customer_id = ANY (p_customer_ids))
             ORDER BY so.production_code, c.customer_number, so.customer_id
        LOOP
            v_status := NULL; v_message := NULL; v_added := 0; v_order := NULL; v_log := NULL;
            v_event := COALESCE(NULLIF(UPPER(TRIM(v_slot.customer_name)), ''), 'ORDER');
            v_order_cust := CASE WHEN UPPER(TRIM(v_slot.customer_type)) = 'DEPARTMENT' AND v_slot.customer_parent_id IS NOT NULL
                                 THEN v_slot.customer_parent_id ELSE v_slot.customer_id END;
            BEGIN
                PERFORM pg_advisory_xact_lock(hashtext('om_standing_orders_post'),
                                              hashtext(p_tenant_id || ':' || v_slot.customer_id || ':' || v_date || ':' || v_slot.production_code));

                SELECT * INTO v_log FROM om_standing_order_postings
                 WHERE tenant_id = p_tenant_id AND customer_id = v_slot.customer_id
                   AND production_date = v_date AND production_code = v_slot.production_code
                 FOR UPDATE;

                IF v_log.order_id IS NOT NULL THEN
                    SELECT * INTO v_order FROM om_orders WHERE tenant_id = p_tenant_id AND order_id = v_log.order_id;
                END IF;
                IF v_order.order_id IS NULL THEN
                    SELECT * INTO v_order FROM om_orders
                     WHERE tenant_id = p_tenant_id AND customer_id = v_order_cust
                       AND production_date = v_date AND production_code = v_slot.production_code
                       AND department_event = v_event;
                END IF;

                IF v_order.order_id IS NOT NULL AND EXISTS (
                       SELECT 1 FROM ar_transaction_lines l
                         JOIN ar_transactions t ON t.ar_transaction_id = l.ar_transaction_id AND t.tenant_id = l.tenant_id
                        WHERE l.tenant_id = p_tenant_id AND l.order_id = v_order.order_id
                          AND t.document_number IS NOT NULL AND t.status <> 'CANCELLED') THEN
                    v_status := 'POSTED_TO_AR';
                ELSIF v_order.order_id IS NULL AND v_log.posting_id IS NOT NULL THEN
                    v_status := 'ORDER_DELETED';
                ELSE
                    v_prices := bps.om_items_get_v2(p_tenant_id => p_tenant_id, p_customer_id => v_slot.customer_id,
                                                    p_production_date => v_date, p_production_code => v_slot.production_code);
                    SELECT COALESCE(jsonb_agg(jsonb_build_object(
                               'item_id', so.item_id,
                               'item_description', i.item_name,
                               'quantity', so.quantity,
                               'unit_price', COALESCE((SELECT (p->>'unit_price')::numeric FROM jsonb_array_elements(v_prices) p
                                                        WHERE (p->>'item_id')::bigint = so.item_id LIMIT 1), 0),
                               'unit_discount', 0,
                               'prep_options', so.prep_options)
                             ORDER BY i.item_number, so.item_id), '[]'::jsonb)
                      INTO v_lines
                      FROM om_standing_orders so
                      JOIN fnd_items i ON i.item_id = so.item_id AND i.tenant_id = so.tenant_id AND i.is_active
                     WHERE so.tenant_id = p_tenant_id AND so.customer_id = v_slot.customer_id
                       AND so.production_dow = v_dow AND so.production_code = v_slot.production_code
                       AND so.is_active
                       AND (so.effective_from IS NULL OR so.effective_from <= v_date)
                       AND (so.effective_to IS NULL OR so.effective_to >= v_date)
                       AND (v_order.order_id IS NULL OR NOT EXISTS (
                            SELECT 1 FROM om_order_lines ol
                             WHERE ol.tenant_id = p_tenant_id AND ol.order_id = v_order.order_id AND ol.item_id = so.item_id));
                    v_added := jsonb_array_length(v_lines);

                    IF v_order.order_id IS NULL THEN
                        IF v_added = 0 THEN
                            v_status := 'UP_TO_DATE';
                            v_message := 'No active items on the standing order.';
                        ELSE
                            v_saved := bps.om_orders_save(p_tenant_id, NULL, NULL, jsonb_build_object(
                                'customer_id', v_slot.customer_id,
                                'order_date', COALESCE(p_order_date, CURRENT_DATE),
                                'production_date', v_date,
                                'production_code', v_slot.production_code,
                                'department_event', v_event,
                                'delivery_amount', 0,
                                'lines', v_lines));
                            SELECT * INTO v_order FROM om_orders WHERE order_id = (v_saved->>'order_id')::bigint;
                            v_status := 'POSTED';
                        END IF;
                    ELSIF v_added = 0 THEN
                        v_status := 'UP_TO_DATE';
                    ELSE
                        INSERT INTO om_order_lines (tenant_id, order_id, item_id, item_description, quantity, unit_price,
                                                    unit_discount, extended_amount, prep_options)
                        SELECT p_tenant_id, v_order.order_id, (l->>'item_id')::bigint, l->>'item_description',
                               (l->>'quantity')::numeric, (l->>'unit_price')::numeric, 0,
                               (l->>'quantity')::numeric * (l->>'unit_price')::numeric, l->'prep_options'
                          FROM jsonb_array_elements(v_lines) l;
                        UPDATE om_orders o SET
                               quantity        = x.qty,
                               amount          = x.amt,
                               discount_amount = x.disc
                          FROM (SELECT COALESCE(SUM(quantity), 0) AS qty,
                                       COALESCE(SUM(COALESCE(extended_amount, 0)), 0) AS amt,
                                       COALESCE(SUM(quantity * unit_discount), 0) AS disc
                                  FROM om_order_lines WHERE tenant_id = p_tenant_id AND order_id = v_order.order_id) x
                         WHERE o.order_id = v_order.order_id;
                        v_status := 'ADDED';
                    END IF;

                    IF v_order.order_id IS NOT NULL OR v_log.posting_id IS NOT NULL THEN
                        INSERT INTO om_standing_order_postings (tenant_id, customer_id, production_date, production_code,
                                                                order_id, lines_added, posted_by)
                        VALUES (p_tenant_id, v_slot.customer_id, v_date, v_slot.production_code, v_order.order_id,
                                v_added, v_actor)
                        ON CONFLICT (tenant_id, customer_id, production_date, production_code) DO UPDATE
                           SET order_id = EXCLUDED.order_id, lines_added = EXCLUDED.lines_added,
                               post_count = om_standing_order_postings.post_count + 1,
                               last_posted_at = now(), posted_by = EXCLUDED.posted_by;
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_status := 'FAILED';
                v_message := SQLERRM;
                v_added := 0;
            END;

            v_results := v_results || jsonb_build_array(jsonb_build_object(
                'production_date', v_date,
                'production_code', v_slot.production_code,
                'customer_id', v_slot.customer_id,
                'customer_number', COALESCE(v_slot.customer_number, ''),
                'customer_name', v_slot.customer_name,
                'status', v_status,
                'order_id', CASE WHEN v_status = 'FAILED' THEN NULL ELSE v_order.order_id END,
                'order_number', CASE WHEN v_status = 'FAILED' THEN NULL ELSE v_order.order_number END,
                'department_event', CASE WHEN v_status = 'FAILED' THEN NULL ELSE v_order.department_event END,
                'lines_added', CASE WHEN v_status IN ('POSTED', 'ADDED') THEN v_added ELSE 0 END,
                'message', v_message));
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object(
        'posted',     (SELECT count(*) FROM jsonb_array_elements(v_results) r WHERE r->>'status' = 'POSTED'),
        'added',      (SELECT count(*) FROM jsonb_array_elements(v_results) r WHERE r->>'status' = 'ADDED'),
        'up_to_date', (SELECT count(*) FROM jsonb_array_elements(v_results) r WHERE r->>'status' = 'UP_TO_DATE'),
        'skipped',    (SELECT count(*) FROM jsonb_array_elements(v_results) r WHERE r->>'status' IN ('POSTED_TO_AR', 'ORDER_DELETED')),
        'failed',     (SELECT count(*) FROM jsonb_array_elements(v_results) r WHERE r->>'status' = 'FAILED'),
        'results',    v_results);
END;
$function$;
