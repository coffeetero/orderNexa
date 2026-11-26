-- ============================================================
-- ar_credit_memo_create
-- Credits quantities of an issued invoice (e.g. "missing 14 rolls"): creates a CM document for the same customer with a
-- number from the tenant sequence 'credit_memo_number', negative ADJUSTMENT lines (quantity x the invoice line's unit
-- price) and applies_to_ar_transaction_id pointing at the invoice. A line cannot be credited beyond the quantity that
-- shipped (earlier credits count, from the invoice line's quantity_credited). Staff only. Invoices are never edited after printing;
-- only quantity_credited on its lines moves (by trigger).
-- p_payload: { reason, lines: [{ ar_transaction_line_id, quantity }] }
-- Returns { ar_transaction_id, document_number, amount }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_credit_memo_create(p_tenant_id bigint, p_applies_to_ar_transaction_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_inv      ar_transactions%ROWTYPE;
    v_cm_id    bigint;
    v_number   text;
    v_date     date;
    v_line     jsonb;
    v_il       ar_transaction_lines%ROWTYPE;
    v_qty      numeric;
    v_credited numeric;
    v_cap      numeric;
    v_total    numeric := 0;
    v_n        integer := 0;
    v_reason   text := NULLIF(TRIM(p_payload ->> 'reason'), '');
    v_desc     text;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can create credit memos';
    END IF;
    SELECT * INTO v_inv FROM ar_transactions
     WHERE tenant_id = p_tenant_id AND ar_transaction_id = p_applies_to_ar_transaction_id AND transaction_type = 'INV' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice % not found', p_applies_to_ar_transaction_id;
    END IF;
    IF v_inv.status NOT IN ('OPEN', 'PARTIAL', 'CLOSED') THEN
        RAISE EXCEPTION 'Only issued invoices can be credited (this one is %)', v_inv.status;
    END IF;
    IF jsonb_array_length(COALESCE(p_payload -> 'lines', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Choose at least one line to credit';
    END IF;

    v_date := (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date;
    v_number := bps.fnd_tenant_sequence_next(p_tenant_id, 'credit_memo_number', v_date);
    INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status,
                                 applies_to_ar_transaction_id, production_run_id)
    VALUES (p_tenant_id, v_inv.customer_id, 'CM', v_number, v_date, 0, 'OPEN', v_inv.ar_transaction_id, NULL)
    RETURNING ar_transaction_id INTO v_cm_id;

    FOR v_line IN SELECT jsonb_array_elements(p_payload -> 'lines') LOOP
        v_qty := (v_line ->> 'quantity')::numeric;
        SELECT * INTO v_il FROM ar_transaction_lines
         WHERE tenant_id = p_tenant_id AND ar_transaction_id = v_inv.ar_transaction_id
           AND ar_transaction_line_id = (v_line ->> 'ar_transaction_line_id')::bigint;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Line % is not on invoice %', v_line ->> 'ar_transaction_line_id', v_inv.document_number;
        END IF;
        -- imported invoice lines say just 'INVOICE': use the item's name
        v_desc := CASE WHEN COALESCE(UPPER(TRIM(v_il.item_description)), 'INVOICE') IN ('INVOICE', '')
                       THEN COALESCE((SELECT i.item_name FROM fnd_items i WHERE i.item_id = v_il.item_id), v_il.item_description)
                       ELSE v_il.item_description END;
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Credit quantity must be above zero';
        END IF;
        -- kept by trigger from the credit memo lines; the invoice row is locked above, so two users cannot both take the rest
        v_credited := v_il.quantity_credited;
        -- an item line can only be credited up to what actually shipped (a short delivery is already not receivable)
        v_cap := COALESCE((SELECT sl.shipped_quantity FROM om_shipment_lines sl WHERE sl.shipment_line_id = v_il.shipment_line_id), v_il.quantity, 0);
        IF v_qty > v_cap - v_credited THEN
            RAISE EXCEPTION 'Cannot credit % of "%": % delivered, % already credited', trim_scale(v_qty), v_desc, trim_scale(v_cap), trim_scale(v_credited);
        END IF;
        v_n := v_n + 1;
        INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, source_type, item_id, item_description,
                                          quantity, unit_price, amount, snapshot_data)
        VALUES (p_tenant_id, v_cm_id, v_n, 'ADJUSTMENT', v_il.item_id, v_desc, v_qty, v_il.unit_price,
                -(v_qty * COALESCE(v_il.unit_price, 0)),
                jsonb_build_object('credits_line_id', v_il.ar_transaction_line_id, 'invoice_number', v_inv.document_number,
                                   'order_number', v_il.snapshot_data ->> 'order_number', 'reason', v_reason));
        v_total := v_total - (v_qty * COALESCE(v_il.unit_price, 0));
    END LOOP;

    UPDATE ar_transactions SET amount = v_total WHERE ar_transaction_id = v_cm_id;
    RETURN jsonb_build_object('ar_transaction_id', v_cm_id, 'document_number', v_number, 'amount', v_total);
END;
$function$;
