-- ============================================================
-- ar_invoices_print_get
-- Production > Print Invoices: the invoices (DRAFT ones too, printed without a number for customer approval; not CANCELLED) of the chosen invoice owners whose orders are
-- for a production date in [p_from, p_to] (one code when given), laid out like the old BPS invoice. Covers migrated and
-- BPS-made invoices (an invoice's slot comes from its run, else from its orders). Staff only.
-- Returns { company_name, footer_note, tagline, invoices: [{
--   ar_transaction_id, document_number, status, production_date, weekday, production_code, production_code_label,
--   account_type, customer_name, customer_number (masked), address_lines, phone (PHONE contact, else Phone1 of the legacy note),
--   item_quantity, item_amount, delivery_amount, other_amount, amount,
--   memos: [{ document_number, transaction_type (DM debit / CM credit), transaction_date, amount,
--             lines: [{ description, quantity, unit_price, amount }] }]  (memos applied to the invoice, not cancelled),
--   total_with_memos (amount + the memos),
--   groups: [{ department_event, department_number, subtotal,
--              lines: [{ item_number (masked), description, quantity, unit, unit_price, amount }] }] }] }
-- A group is one order (its Department/Event and, when known, the department number), sorted by department number
-- then event, like the old invoice. Lines with no order (adjustments) come last in a group with no event.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_invoices_print_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_customer_ids bigint[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code  text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_ten   record;
    v_inv   record;
    v_list  jsonb := '[]'::jsonb;
    v_one   jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can print invoices';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;
    IF p_customer_ids IS NULL OR COALESCE(array_length(p_customer_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one customer';
    END IF;
    SELECT tenant_name, customer_number_mask, item_number_mask, invoice_footer_note, invoice_tagline INTO v_ten
      FROM fnd_tenants WHERE tenant_id = p_tenant_id;

    FOR v_inv IN
        SELECT t.ar_transaction_id, t.document_number, t.status, t.amount, t.customer_id,
               COALESCE(r.production_date, os.production_date) AS production_date,
               COALESCE(r.production_code, os.production_code) AS production_code
          FROM ar_transactions t
          LEFT JOIN om_production_runs r ON r.production_run_id = t.production_run_id
          LEFT JOIN LATERAL (
                SELECT min(o.production_date) AS production_date, min(o.production_code) AS production_code
                  FROM ar_transaction_lines l
                  LEFT JOIN om_shipment_lines sl ON sl.shipment_line_id = l.shipment_line_id
                  JOIN om_orders o ON o.order_id = COALESCE(l.order_id, sl.order_id)
                 WHERE l.ar_transaction_id = t.ar_transaction_id) os ON t.production_run_id IS NULL
         WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED'
           AND t.customer_id = ANY (p_customer_ids)
           -- an invoice is dated on or near its production date; this keeps the lateral lookup to a few weeks
           AND t.transaction_date BETWEEN p_from - 14 AND p_to + 14
           AND COALESCE(r.production_date, os.production_date) BETWEEN p_from AND p_to
           AND (v_code IS NULL OR COALESCE(r.production_code, os.production_code) = v_code)
         ORDER BY 6, 7, t.document_number
    LOOP
        WITH ln AS (
            SELECT l.line_number, l.source_type, l.quantity, l.unit_price, l.amount, l.item_description,
                   i.item_number, i.item_name, i.unit_of_sale, o.order_id, o.department_event, o.snapshot_data, oc.customer_number AS order_cus_no,
                   upper(btrim(oc.customer_type)) AS order_cus_type
              FROM ar_transaction_lines l
              LEFT JOIN om_shipment_lines sl ON sl.shipment_line_id = l.shipment_line_id
              LEFT JOIN om_orders o ON o.order_id = COALESCE(l.order_id, sl.order_id)
              LEFT JOIN fnd_customers oc ON oc.customer_id = o.customer_id
              LEFT JOIN fnd_items i ON i.item_id = l.item_id
             WHERE l.ar_transaction_id = v_inv.ar_transaction_id
        ), grp AS (
            SELECT ln.order_id, min(ln.line_number) AS first_line, max(ln.department_event) AS department_event,
                   -- the department the order came from: the order's own customer when it is a department, else the
                   -- department recorded on a migrated order (snapshot cus_key)
                   max(CASE WHEN ln.order_cus_type IN ('DEPARTMENT', 'LOCATION') THEN ln.order_cus_no
                            WHEN ln.snapshot_data ->> 'cus_key' IS DISTINCT FROM ln.order_cus_no THEN ln.snapshot_data ->> 'cus_key' END) AS department_number,
                   sum(ln.amount) FILTER (WHERE ln.source_type = 'ITEM') AS subtotal,
                   jsonb_agg(jsonb_build_object(
                       'item_number', bps.fnd_customer_number_format(v_ten.item_number_mask, ln.item_number),
                       'description', COALESCE(ln.item_name, ln.item_description), 'quantity', ln.quantity,
                       'unit', initcap(ln.unit_of_sale), 'unit_price', ln.unit_price, 'amount', ln.amount) ORDER BY ln.line_number)
                     AS lines
              FROM ln
             -- delivery charges print in the footer only
             WHERE ln.source_type = 'ITEM' OR (ln.order_id IS NULL AND ln.source_type <> 'DELIVERY')
             GROUP BY ln.order_id
        )
        SELECT jsonb_build_object(
                 'ar_transaction_id', v_inv.ar_transaction_id, 'document_number', v_inv.document_number, 'status', v_inv.status,
                 'production_date', v_inv.production_date, 'weekday', trim(to_char(v_inv.production_date, 'Day')),
                 'production_code', v_inv.production_code,
                 'production_code_label', COALESCE((SELECT vv.label FROM fnd_valueset_values vv JOIN fnd_valuesets vs ON vs.valueset_id = vv.valueset_id
                                                     WHERE vs.valueset_code = 'PRODUCTIONCODE' AND vv.tenant_id = p_tenant_id AND vv.value = v_inv.production_code
                                                     LIMIT 1), v_inv.production_code),
                 'account_type', initcap(c.customer_type), 'customer_name', c.customer_name,
                 'customer_number', bps.fnd_customer_number_format(v_ten.customer_number_mask, c.customer_number),
                 'address_lines', COALESCE((SELECT jsonb_agg(a) FROM regexp_split_to_table(btrim(COALESCE((
                       SELECT cp.value FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id
                        WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = c.customer_id
                          AND cp.type = 'ADDRESS' AND cp.is_active
                        ORDER BY (cp.label = 'Billing') DESC, cp.is_primary DESC, cp.sequence LIMIT 1), '')), '\s*\n\s*') a WHERE a <> ''), '[]'::jsonb),
                 -- a PHONE contact point; migrated customers have their phone only as "Phone1: ..." in the Legacy Data note
                 'phone', (SELECT COALESCE(CASE WHEN cp.type = 'PHONE' THEN cp.value END,
                                           btrim(substring(cp.value FROM 'Phone1:\s*([^\n]+)')))
                             FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id
                            WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = c.customer_id AND cp.is_active
                              AND (cp.type = 'PHONE' OR (cp.type = 'NOTE' AND cp.value ~ 'Phone1:\s*\S'))
                            ORDER BY (cp.type = 'PHONE') DESC, cp.is_primary DESC, cp.sequence LIMIT 1),
                 'item_quantity', COALESCE((SELECT sum(quantity) FROM ln WHERE source_type = 'ITEM'), 0),
                 'item_amount', COALESCE((SELECT sum(amount) FROM ln WHERE source_type = 'ITEM'), 0),
                 'delivery_amount', COALESCE((SELECT sum(amount) FROM ln WHERE source_type = 'DELIVERY'), 0),
                 'other_amount', COALESCE((SELECT sum(amount) FROM ln WHERE source_type NOT IN ('ITEM', 'DELIVERY')), 0),
                 'amount', v_inv.amount,
                 'memos', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                'document_number', m.document_number, 'transaction_type', m.transaction_type,
                                'transaction_date', m.transaction_date, 'amount', m.amount,
                                'lines', COALESCE((SELECT jsonb_agg(jsonb_build_object('description', ml.item_description, 'quantity', ml.quantity,
                                                                                         'unit_price', ml.unit_price, 'amount', ml.amount)
                                                                    ORDER BY ml.line_number)
                                                     FROM ar_transaction_lines ml WHERE ml.ar_transaction_id = m.ar_transaction_id), '[]'::jsonb))
                              ORDER BY m.transaction_date, m.ar_transaction_id)
                       FROM ar_transactions m
                      WHERE m.tenant_id = p_tenant_id AND m.applies_to_ar_transaction_id = v_inv.ar_transaction_id
                        AND m.transaction_type IN ('DM', 'CM') AND m.status <> 'CANCELLED'), '[]'::jsonb),
                 'total_with_memos', v_inv.amount + COALESCE((SELECT SUM(m.amount) FROM ar_transactions m
                      WHERE m.tenant_id = p_tenant_id AND m.applies_to_ar_transaction_id = v_inv.ar_transaction_id
                        AND m.transaction_type IN ('DM', 'CM') AND m.status <> 'CANCELLED'), 0),
                 'groups', COALESCE((SELECT jsonb_agg(jsonb_build_object('department_event', g.department_event, 'department_number', g.department_number,
                                                                        'subtotal', COALESCE(g.subtotal, 0), 'lines', g.lines)
                                                     ORDER BY g.order_id IS NULL, g.department_number NULLS LAST, g.department_event, g.first_line) FROM grp g), '[]'::jsonb))
          INTO v_one
          FROM fnd_customers c WHERE c.customer_id = v_inv.customer_id;
        v_list := v_list || jsonb_build_array(v_one);
    END LOOP;

    RETURN jsonb_build_object('company_name', v_ten.tenant_name, 'footer_note', v_ten.invoice_footer_note,
                              'tagline', v_ten.invoice_tagline, 'invoices', v_list);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_invoices_print_get(bigint, date, date, text, bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_invoices_print_get(bigint, date, date, text, bigint[]) TO authenticated, service_role, bps_dev;
