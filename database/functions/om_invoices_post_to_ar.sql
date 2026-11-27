-- ============================================================
-- om_invoices_post_to_ar
-- Post Orders to AR: gives the DRAFT invoices of the runs with a production date in [p_from, p_to] (one code when given;
-- only the given invoice owners when p_customer_ids is not null) their number from the tenant sequence 'invoice_number'
-- (status DRAFT -> OPEN). This is the only step that numbers invoices. Staff only. At most 14 days at a time; may run
-- ahead (Friday for Saturday to Monday).
--   - Standing orders must be posted first: refused while a standing order for a date and code in the selection has not
--     been posted (om_post_standing_orders_list status NEW).
--   - Each run in the selection that has not shipped is posted to production again first (om_production_run_process),
--     so the invoices match the orders as they are now.
-- Returns { numbered, invoices: [{ ar_transaction_id, document_number, customer_id, customer_name, production_date,
--   production_code, amount }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_invoices_post_to_ar(
    p_tenant_id       bigint,
    p_from            date,
    p_to              date,
    p_production_code text     DEFAULT NULL,
    p_customer_ids    bigint[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code    text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_codes   text[];
    v_missing jsonb;
    v_run     record;
    v_inv     record;
    v_out     jsonb := '[]'::jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can post orders to AR';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;
    IF p_to - p_from > 13 THEN
        RAISE EXCEPTION 'Orders can be posted to AR for at most 14 days at a time';
    END IF;

    -- Standing orders first
    SELECT COALESCE(array_agg(DISTINCT so.production_code), ARRAY[]::text[]) INTO v_codes
      FROM om_standing_orders so
     WHERE so.tenant_id = p_tenant_id AND so.is_active AND (v_code IS NULL OR so.production_code = v_code);
    IF array_length(v_codes, 1) > 0 THEN
        SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object('production_date', r->>'production_date', 'production_code', r->>'production_code')), '[]'::jsonb)
          INTO v_missing
          FROM jsonb_array_elements(bps.om_post_standing_orders_list(p_tenant_id, p_from, p_to, v_codes)) r
         WHERE r->>'status' = 'NEW'
           AND (p_customer_ids IS NULL
                OR bps.om_customer_invoice_owner(p_tenant_id, (r->>'customer_id')::bigint) = ANY (p_customer_ids));
        IF jsonb_array_length(v_missing) > 0 THEN
            RAISE EXCEPTION 'Post standing orders first: some are not posted for %',
                (SELECT string_agg(DISTINCT to_char((m->>'production_date')::date, 'Dy Mon DD') || ' ' || (m->>'production_code'), ', ')
                   FROM jsonb_array_elements(v_missing) m);
        END IF;
    END IF;

    -- Bring the drafts up to date with the orders
    FOR v_run IN
        SELECT r.production_run_id FROM om_production_runs r
         WHERE r.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
           AND r.run_status <> 'CLOSED'
           AND EXISTS (SELECT 1 FROM ar_transactions t WHERE t.production_run_id = r.production_run_id AND t.transaction_type = 'INV' AND t.status = 'DRAFT')
           AND NOT EXISTS (SELECT 1 FROM om_shipments s WHERE s.production_run_id = r.production_run_id AND s.shipment_status IN ('SHIPPED', 'DELIVERED'))
         ORDER BY r.production_date, r.production_code
    LOOP
        PERFORM bps.om_production_run_process(p_tenant_id, v_run.production_run_id);
    END LOOP;

    FOR v_inv IN
        SELECT t.ar_transaction_id, t.transaction_date
          FROM ar_transactions t
          JOIN om_production_runs r ON r.production_run_id = t.production_run_id
          JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
         WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status = 'DRAFT'
           AND (p_customer_ids IS NULL OR t.customer_id = ANY (p_customer_ids))
           AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
         ORDER BY r.production_date, r.production_code, c.customer_name
           FOR UPDATE OF t
    LOOP
        UPDATE ar_transactions
           SET document_number = bps.fnd_tenant_sequence_next(p_tenant_id, 'invoice_number', v_inv.transaction_date),
               status = 'OPEN'
         WHERE ar_transaction_id = v_inv.ar_transaction_id;
        v_out := v_out || jsonb_build_array((
            SELECT jsonb_build_object('ar_transaction_id', t.ar_transaction_id, 'document_number', t.document_number,
                                      'customer_id', c.customer_id, 'customer_name', c.customer_name,
                                      'production_date', r.production_date, 'production_code', r.production_code, 'amount', t.amount)
              FROM ar_transactions t
              JOIN om_production_runs r ON r.production_run_id = t.production_run_id
              JOIN fnd_customers c ON c.customer_id = t.customer_id
             WHERE t.ar_transaction_id = v_inv.ar_transaction_id));
    END LOOP;

    RETURN jsonb_build_object('numbered', jsonb_array_length(v_out), 'invoices', v_out);
END;
$function$;
