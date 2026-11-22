-- Delivery confirmation, AR recognition and credit memos (Phase 4 of order-to-invoice). Requires add_order_reports.sql first.
-- Local only. A receivable is recognised from shipped quantities once a shipment is SHIPPED/DELIVERED.
SET search_path = bps, public;

-- ===== policies/ar_payments_policies.sql =====
-- ============================================================
-- AR_PAYMENTS — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: ar_payments.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_payments TO authenticated;
GRANT ALL ON TABLE ar_payments TO bps_dev;

ALTER TABLE ar_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_payments_tenant ON ar_payments;
DROP POLICY IF EXISTS pol_ar_payments_read ON ar_payments;
CREATE POLICY pol_ar_payments_read ON ar_payments
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR (customer_id)::text = ANY (ARRAY(SELECT jsonb_array_elements_text(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids')))
        )
    );

DROP POLICY IF EXISTS pol_ar_payments_staff_write ON ar_payments;
CREATE POLICY pol_ar_payments_staff_write ON ar_payments
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );

-- ===== policies/ar_payment_applications_policies.sql =====
-- ============================================================
-- AR_PAYMENT_APPLICATIONS — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: ar_payment_applications.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_payment_applications TO authenticated;
GRANT ALL ON TABLE ar_payment_applications TO bps_dev;

ALTER TABLE ar_payment_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_payment_applications_tenant ON ar_payment_applications;
DROP POLICY IF EXISTS pol_ar_payment_applications_read ON ar_payment_applications;
CREATE POLICY pol_ar_payment_applications_read ON ar_payment_applications
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR EXISTS (SELECT 1 FROM ar_payments p WHERE p.ar_payment_id = ar_payment_applications.ar_payment_id)
        )
    );

DROP POLICY IF EXISTS pol_ar_payment_applications_staff_write ON ar_payment_applications;
CREATE POLICY pol_ar_payment_applications_staff_write ON ar_payment_applications
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );

-- ===== functions/om_shipments_get.sql =====
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

-- ===== functions/om_shipment_confirm.sql =====
-- ============================================================
-- om_shipment_confirm
-- Confirms a shipment: marks it SHIPPED or DELIVERED, records what actually went (per line, default = planned) and how
-- (method, carrier, tracking, route, the bakery's delivery cost), and rolls the shipped quantities up into
-- om_order_lines.fulfilled_quantity. From this point the invoice lines on the shipment count as receivable.
-- Staff only. A method that requires tracking needs a tracking reference. shipped_quantity cannot exceed the planned
-- quantity (extra goods are a new order). Can be repeated to correct the record or move SHIPPED -> DELIVERED.
-- p_payload: { shipment_status 'SHIPPED'|'DELIVERED', delivery_method_code, carrier, tracking_reference, route,
--              delivery_cost, lines: [{ shipment_line_id, shipped_quantity }] }
-- Returns { shipment_id, shipment_status, shortages: [{ shipment_line_id, item_name, planned, shipped, short }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_shipment_confirm(p_tenant_id bigint, p_shipment_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_ship      om_shipments%ROWTYPE;
    v_status    text := UPPER(COALESCE(NULLIF(TRIM(p_payload ->> 'shipment_status'), ''), 'SHIPPED'));
    v_method    text;
    v_tracking  text;
    v_track_req boolean := FALSE;
    v_line      jsonb;
    v_sl        om_shipment_lines%ROWTYPE;
    v_qty       numeric;
    v_actor     bigint := bps.fnd_nav_app_user_id();
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can confirm shipments';
    END IF;
    IF v_status NOT IN ('SHIPPED', 'DELIVERED') THEN
        RAISE EXCEPTION 'shipment_status must be SHIPPED or DELIVERED';
    END IF;
    SELECT * INTO v_ship FROM om_shipments WHERE tenant_id = p_tenant_id AND shipment_id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shipment % not found', p_shipment_id;
    END IF;
    IF v_ship.shipment_status = 'CANCELLED' THEN
        RAISE EXCEPTION 'Shipment % is cancelled', v_ship.shipment_number;
    END IF;

    v_method   := COALESCE(NULLIF(UPPER(TRIM(p_payload ->> 'delivery_method_code')), ''), v_ship.delivery_method_code);
    v_tracking := CASE WHEN p_payload ? 'tracking_reference' THEN NULLIF(TRIM(p_payload ->> 'tracking_reference'), '') ELSE v_ship.tracking_reference END;
    IF v_method IS NOT NULL THEN
        SELECT m.requires_tracking INTO v_track_req FROM om_delivery_methods m
         WHERE m.tenant_id = p_tenant_id AND m.delivery_method_code = v_method AND m.is_active;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Delivery method % is not available', v_method;
        END IF;
        IF v_track_req AND v_tracking IS NULL THEN
            RAISE EXCEPTION 'Delivery method % requires a tracking reference', v_method;
        END IF;
    END IF;

    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload -> 'lines', '[]'::jsonb)) LOOP
        SELECT * INTO v_sl FROM om_shipment_lines
         WHERE tenant_id = p_tenant_id AND shipment_id = p_shipment_id AND shipment_line_id = (v_line ->> 'shipment_line_id')::bigint;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Shipment line % does not belong to shipment %', v_line ->> 'shipment_line_id', v_ship.shipment_number;
        END IF;
        v_qty := (v_line ->> 'shipped_quantity')::numeric;
        IF v_qty IS NULL OR v_qty < 0 OR v_qty > v_sl.quantity THEN
            RAISE EXCEPTION 'Shipped quantity for line % must be between 0 and %', v_sl.shipment_line_id, v_sl.quantity;
        END IF;
        UPDATE om_shipment_lines SET shipped_quantity = v_qty WHERE shipment_line_id = v_sl.shipment_line_id;
    END LOOP;
    -- lines not mentioned default to the planned quantity
    UPDATE om_shipment_lines SET shipped_quantity = quantity WHERE shipment_id = p_shipment_id AND shipped_quantity IS NULL;

    UPDATE om_shipments SET
        shipment_status      = v_status,
        delivery_method_code = v_method,
        carrier              = CASE WHEN p_payload ? 'carrier' THEN NULLIF(TRIM(p_payload ->> 'carrier'), '') ELSE carrier END,
        tracking_reference   = v_tracking,
        route                = CASE WHEN p_payload ? 'route' THEN NULLIF(TRIM(p_payload ->> 'route'), '') ELSE route END,
        delivery_cost        = CASE WHEN p_payload ? 'delivery_cost' THEN NULLIF(TRIM(p_payload ->> 'delivery_cost'), '')::numeric ELSE delivery_cost END,
        shipped_at           = COALESCE(shipped_at, now()),
        shipped_by           = COALESCE(shipped_by, v_actor)
     WHERE shipment_id = p_shipment_id;

    UPDATE om_order_lines ol SET fulfilled_quantity = COALESCE((
            SELECT SUM(sl.shipped_quantity) FROM om_shipment_lines sl JOIN om_shipments s ON s.shipment_id = sl.shipment_id
             WHERE sl.order_line_id = ol.order_line_id AND s.shipment_status IN ('SHIPPED', 'DELIVERED')), 0)
     WHERE ol.order_line_id IN (SELECT order_line_id FROM om_shipment_lines WHERE shipment_id = p_shipment_id AND order_line_id IS NOT NULL);

    RETURN jsonb_build_object(
        'shipment_id', p_shipment_id, 'shipment_status', v_status,
        'shortages', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'shipment_line_id', sl.shipment_line_id,
                'item_name', COALESCE(NULLIF(TRIM(ol.item_description), ''), i.item_name),
                'planned', sl.quantity, 'shipped', sl.shipped_quantity, 'short', sl.quantity - sl.shipped_quantity))
              FROM om_shipment_lines sl
              LEFT JOIN om_order_lines ol ON ol.order_line_id = sl.order_line_id
              LEFT JOIN fnd_items i ON i.item_id = ol.item_id
             WHERE sl.shipment_id = p_shipment_id AND sl.shipped_quantity < sl.quantity), '[]'::jsonb));
END;
$function$;

-- ===== functions/ar_invoice_recognized_amount.sql =====
-- ============================================================
-- ar_invoice_recognized_amount
-- The part of an invoice that counts toward the customer's balance: each ITEM line at shipped_quantity x unit_price once
-- its shipment is SHIPPED or DELIVERED, plus a DELIVERY line when any item of the same order has shipped. Invoices that are
-- DRAFT or CANCELLED recognise nothing.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_invoice_recognized_amount(p_ar_transaction_id bigint)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(SUM(CASE
               WHEN l.source_type = 'ITEM' THEN COALESCE(sl.shipped_quantity, 0) * COALESCE(l.unit_price, 0)
               WHEN l.source_type = 'DELIVERY' THEN CASE WHEN EXISTS (
                       SELECT 1 FROM ar_transaction_lines il
                         JOIN om_shipment_lines isl ON isl.shipment_line_id = il.shipment_line_id
                         JOIN om_shipments ish ON ish.shipment_id = isl.shipment_id AND ish.shipment_status IN ('SHIPPED', 'DELIVERED')
                        WHERE il.ar_transaction_id = l.ar_transaction_id AND il.source_type = 'ITEM'
                          AND il.snapshot_data ->> 'order_id' = l.snapshot_data ->> 'order_id' AND COALESCE(isl.shipped_quantity, 0) > 0
                   ) THEN l.amount ELSE 0 END
               ELSE 0 END), 0)
      FROM ar_transactions t
      JOIN ar_transaction_lines l ON l.ar_transaction_id = t.ar_transaction_id
      LEFT JOIN om_shipment_lines sl ON sl.shipment_line_id = l.shipment_line_id
      LEFT JOIN om_shipments s ON s.shipment_id = sl.shipment_id AND s.shipment_status IN ('SHIPPED', 'DELIVERED')
     WHERE t.ar_transaction_id = p_ar_transaction_id AND t.transaction_type = 'INV' AND t.status NOT IN ('DRAFT', 'CANCELLED')
       AND (l.source_type <> 'ITEM' OR s.shipment_id IS NOT NULL);
$function$;

-- ===== functions/ar_credit_memo_create.sql =====
-- ============================================================
-- ar_credit_memo_create
-- Credits quantities of an issued invoice (e.g. "missing 14 rolls"): creates a CM document for the same customer with a
-- number from the tenant sequence 'credit_memo_number', negative ADJUSTMENT lines (quantity x the invoice line's unit
-- price) and applies_to_ar_transaction_id pointing at the invoice. A line cannot be credited beyond the quantity that
-- shipped (earlier credits count). Staff only. Invoices are never edited after printing.
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
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Credit quantity must be above zero';
        END IF;
        SELECT COALESCE(SUM(cl.quantity), 0) INTO v_credited
          FROM ar_transaction_lines cl JOIN ar_transactions ct ON ct.ar_transaction_id = cl.ar_transaction_id AND ct.status <> 'CANCELLED'
         WHERE ct.applies_to_ar_transaction_id = v_inv.ar_transaction_id AND (cl.snapshot_data ->> 'credits_line_id')::bigint = v_il.ar_transaction_line_id;
        -- an item line can only be credited up to what actually shipped (a short delivery is already not receivable)
        v_cap := COALESCE((SELECT sl.shipped_quantity FROM om_shipment_lines sl WHERE sl.shipment_line_id = v_il.shipment_line_id), v_il.quantity, 0);
        IF v_qty > v_cap - v_credited THEN
            RAISE EXCEPTION 'Cannot credit % of "%": % delivered, % already credited', v_qty, v_il.item_description, v_cap, v_credited;
        END IF;
        v_n := v_n + 1;
        INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, source_type, item_id, item_description,
                                          quantity, unit_price, amount, snapshot_data)
        VALUES (p_tenant_id, v_cm_id, v_n, 'ADJUSTMENT', v_il.item_id, v_il.item_description, v_qty, v_il.unit_price,
                -(v_qty * COALESCE(v_il.unit_price, 0)),
                jsonb_build_object('credits_line_id', v_il.ar_transaction_line_id, 'invoice_number', v_inv.document_number,
                                   'order_number', v_il.snapshot_data ->> 'order_number', 'reason', v_reason));
        v_total := v_total - (v_qty * COALESCE(v_il.unit_price, 0));
    END LOOP;

    UPDATE ar_transactions SET amount = v_total WHERE ar_transaction_id = v_cm_id;
    RETURN jsonb_build_object('ar_transaction_id', v_cm_id, 'document_number', v_number, 'amount', v_total);
END;
$function$;

-- ===== functions/ar_customer_balance_get.sql =====
-- ============================================================
-- ar_customer_balance_get
-- What a paying customer (an account, or a department that pays for itself) owes: recognised invoices (shipped lines)
-- of the customer and of everything beneath it that is not itself an ACCOUNT, minus credit memos, minus payments applied.
-- Staff only. Returns { recognized_invoices, credits, payments_applied, balance }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_customer_balance_get(p_tenant_id bigint, p_customer_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_inv  numeric;
    v_cred numeric;
    v_pay  numeric;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can see balances';
    END IF;

    WITH RECURSIVE tree AS (
        SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
         WHERE c.tenant_id = p_tenant_id AND UPPER(TRIM(c.customer_type)) <> 'ACCOUNT'
    ), docs AS (
        SELECT t.ar_transaction_id, t.transaction_type, t.amount FROM ar_transactions t
         WHERE t.tenant_id = p_tenant_id AND t.customer_id IN (SELECT customer_id FROM tree) AND t.status NOT IN ('DRAFT', 'CANCELLED')
    )
    SELECT COALESCE(SUM(bps.ar_invoice_recognized_amount(d.ar_transaction_id)) FILTER (WHERE d.transaction_type = 'INV'), 0),
           COALESCE(SUM(d.amount) FILTER (WHERE d.transaction_type = 'CM'), 0),
           COALESCE((SELECT SUM(pa.applied_amount) FROM ar_payment_applications pa WHERE pa.tenant_id = p_tenant_id
                        AND pa.ar_transaction_id IN (SELECT ar_transaction_id FROM docs WHERE transaction_type = 'INV')), 0)
      INTO v_inv, v_cred, v_pay
      FROM docs d;

    RETURN jsonb_build_object('recognized_invoices', v_inv, 'credits', v_cred, 'payments_applied', v_pay, 'balance', v_inv + v_cred - v_pay);
END;
$function$;

-- ===== functions/ar_document_lookup.sql =====
-- ============================================================
-- ar_document_lookup
-- Finds invoices by invoice number or by an order number on them (case-insensitive, exact), for the person on the phone
-- ("the kitchen was short 2 breads"). Staff only.
-- Returns { invoices: [{ ar_transaction_id, document_number, status, customer_name, delivery_date, amount, recognized_amount,
--   credited_amount, lines: [{ ar_transaction_line_id, source_type, order_number, department_event, item_description, quantity,
--   unit_price, amount, shipped_quantity, credited_quantity }], credits: [{ document_number, amount, reason }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_document_lookup(p_tenant_id bigint, p_search text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_q text := UPPER(TRIM(COALESCE(p_search, '')));
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can look up documents';
    END IF;
    IF v_q = '' THEN
        RAISE EXCEPTION 'Enter an invoice number or an order number';
    END IF;

    RETURN jsonb_build_object('invoices', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'ar_transaction_id', t.ar_transaction_id, 'document_number', t.document_number, 'status', t.status,
                   'customer_name', c.customer_name, 'delivery_date', t.transaction_date, 'amount', t.amount,
                   'recognized_amount', bps.ar_invoice_recognized_amount(t.ar_transaction_id),
                   'credited_amount', COALESCE((SELECT -SUM(ct.amount) FROM ar_transactions ct WHERE ct.applies_to_ar_transaction_id = t.ar_transaction_id AND ct.status <> 'CANCELLED'), 0),
                   'lines', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                'ar_transaction_line_id', l.ar_transaction_line_id, 'source_type', l.source_type,
                                'order_number', l.snapshot_data ->> 'order_number', 'department_event', l.snapshot_data ->> 'department_event',
                                'item_description', l.item_description, 'quantity', l.quantity, 'unit_price', l.unit_price, 'amount', l.amount,
                                'shipped_quantity', sl.shipped_quantity,
                                'credited_quantity', COALESCE((SELECT SUM(cl.quantity) FROM ar_transaction_lines cl
                                                                 JOIN ar_transactions ct ON ct.ar_transaction_id = cl.ar_transaction_id AND ct.status <> 'CANCELLED'
                                                                WHERE ct.applies_to_ar_transaction_id = t.ar_transaction_id
                                                                  AND (cl.snapshot_data ->> 'credits_line_id')::bigint = l.ar_transaction_line_id), 0))
                                ORDER BY l.line_number)
                              FROM ar_transaction_lines l LEFT JOIN om_shipment_lines sl ON sl.shipment_line_id = l.shipment_line_id
                             WHERE l.ar_transaction_id = t.ar_transaction_id), '[]'::jsonb),
                   'credits', COALESCE((SELECT jsonb_agg(jsonb_build_object('document_number', ct.document_number, 'amount', ct.amount,
                                'reason', (SELECT cl.snapshot_data ->> 'reason' FROM ar_transaction_lines cl WHERE cl.ar_transaction_id = ct.ar_transaction_id LIMIT 1))
                                ORDER BY ct.document_number)
                              FROM ar_transactions ct WHERE ct.applies_to_ar_transaction_id = t.ar_transaction_id AND ct.status <> 'CANCELLED'), '[]'::jsonb)
               ) ORDER BY t.document_number)
          FROM ar_transactions t
          JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
         WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status NOT IN ('DRAFT', 'CANCELLED')
           AND (UPPER(t.document_number) = v_q
                OR EXISTS (SELECT 1 FROM ar_transaction_lines ol WHERE ol.ar_transaction_id = t.ar_transaction_id AND UPPER(ol.snapshot_data ->> 'order_number') = v_q))
    ), '[]'::jsonb));
END;
$function$;

-- ===== grants =====
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_payments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_payment_applications TO authenticated;
GRANT EXECUTE ON FUNCTION bps.om_shipments_get(bigint, date, date, text, text) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_shipment_confirm(bigint, bigint, jsonb) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.ar_invoice_recognized_amount(bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.ar_credit_memo_create(bigint, bigint, jsonb) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.ar_customer_balance_get(bigint, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.ar_document_lookup(bigint, text) TO authenticated, bps_dev, service_role;