-- ============================================================
-- om_production_run_process
-- "Post Orders to Production" (was "Process run"): locks one run and prepares everything the reports print from. Staff
-- only. Re-runnable until a shipment has been shipped (it rebuilds the PLANNED shipments and the draft invoices).
--   1. run_status -> PROCESSED (processed_at/by).
--   2. Shipments: one PLANNED shipment per ship-to customer (the order's customer) and delivery method; one shipment
--      line per order line (quantity > 0). Shipment numbers come from the tenant sequence 'shipment_number'.
--      Own-fleet shipments get their route and stop number from Routes Maintenance (om_shipments_route_stamp: the run's
--      delivery day of week + production code, date changes applied).
--   3. Invoices: one per invoice owner (om_customer_invoice_owner) per run, DRAFT until Post Orders to AR
--      (om_invoices_post_to_ar) numbers it. Lines: each order line with a quantity above zero (ITEM, net of discount) and
--      each order's delivery charge (DELIVERY), ordered by department/event, order number, line.
--      DRAFT invoices are rebuilt. Invoices already posted to AR follow the company's accounting rules
--      (fnd_tenants.accounting_rules):
--        STRICT  the invoice is never changed; the difference between the orders now and the invoice plus its earlier
--                order-change memos becomes a debit memo (DM, more: higher quantity, new item, new order) and/or a credit
--                memo (CM, less), numbered, dated today and applied to the invoice (memo lines: source ORDER_CHANGE).
--        RELAXED the invoice itself is rebuilt (same number); lines a credit memo points at are updated in place.
--      Drafts whose orders are gone are deleted; RELAXED numbered invoices with no lines left are CANCELLED.
--   4. Invoice amounts = sum of lines.
-- Imported orders count only once their import is approved (om_orders.import_status APPROVED or not imported).
-- Returns { production_run_id, orders, shipments, invoices, orders_waiting_approval, memos }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_run_process(p_tenant_id bigint, p_production_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_run     om_production_runs%ROWTYPE;
    v_actor   bigint := bps.fnd_nav_app_user_id();
    v_pair    record;
    v_orders  integer;
    v_ships   integer;
    v_invs    integer;
    v_held    integer;
    v_rules   text;
    v_inv     ar_transactions%ROWTYPE;
    v_kind    text;
    v_delta   record;
    v_memo_id bigint;
    v_line_no integer;
    v_memos   integer := 0;
    v_date    date;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can process a run';
    END IF;
    SELECT * INTO v_run FROM om_production_runs
     WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Run % not found', p_production_run_id;
    END IF;
    IF v_run.run_status = 'CLOSED' THEN
        RAISE EXCEPTION 'Run % % is closed and cannot be processed', v_run.production_date, v_run.production_code;
    END IF;
    IF EXISTS (SELECT 1 FROM om_shipments WHERE production_run_id = p_production_run_id AND shipment_status IN ('SHIPPED', 'DELIVERED')) THEN
        RAISE EXCEPTION 'Run % % has shipped deliveries and cannot be processed again', v_run.production_date, v_run.production_code;
    END IF;

    UPDATE om_production_runs
       SET run_status = 'PROCESSED', processed_at = now(), processed_by = v_actor
     WHERE production_run_id = p_production_run_id;
    SELECT COALESCE(accounting_rules, 'STRICT') INTO v_rules FROM fnd_tenants WHERE tenant_id = p_tenant_id;

    -- ── Shipments ────────────────────────────────────────────────────────
    DELETE FROM om_shipment_lines
     WHERE shipment_id IN (SELECT shipment_id FROM om_shipments WHERE production_run_id = p_production_run_id AND shipment_status = 'PLANNED');

    FOR v_pair IN
        SELECT DISTINCT o.customer_id, bps.om_customer_delivery_method(p_tenant_id, o.customer_id) AS method
          FROM om_orders o
         WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND o.customer_id IS NOT NULL AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM om_shipments s
             WHERE s.tenant_id = p_tenant_id AND s.production_run_id = p_production_run_id
               AND s.ship_to_customer_id = v_pair.customer_id AND s.delivery_method_code IS NOT DISTINCT FROM v_pair.method
        ) THEN
            INSERT INTO om_shipments (tenant_id, production_run_id, ship_to_customer_id, shipment_number, delivery_date, delivery_method_code)
            VALUES (p_tenant_id, p_production_run_id, v_pair.customer_id,
                    bps.fnd_tenant_sequence_next(p_tenant_id, 'shipment_number', v_run.delivery_date),
                    v_run.delivery_date, v_pair.method);
        END IF;
    END LOOP;

    INSERT INTO om_shipment_lines (tenant_id, shipment_id, order_id, order_line_id, quantity)
    SELECT p_tenant_id, s.shipment_id, ol.order_id, ol.order_line_id, ol.quantity
      FROM om_order_lines ol
      JOIN om_orders o ON o.order_id = ol.order_id AND o.tenant_id = ol.tenant_id
      JOIN om_shipments s
        ON s.tenant_id = o.tenant_id AND s.production_run_id = o.production_run_id
       AND s.ship_to_customer_id = o.customer_id
       AND s.delivery_method_code IS NOT DISTINCT FROM bps.om_customer_delivery_method(o.tenant_id, o.customer_id)
       AND s.shipment_status = 'PLANNED'
     WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND ol.quantity > 0 AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED';

    DELETE FROM om_shipments s
     WHERE s.production_run_id = p_production_run_id AND s.shipment_status = 'PLANNED'
       AND NOT EXISTS (SELECT 1 FROM om_shipment_lines l WHERE l.shipment_id = s.shipment_id);

    PERFORM bps.om_shipments_route_stamp(p_tenant_id, p_production_run_id);

    -- ── Invoices ─────────────────────────────────────────────────────────
    INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status, production_run_id)
    SELECT p_tenant_id, x.owner_id, 'INV', NULL, v_run.delivery_date, 0, 'DRAFT', p_production_run_id
      FROM (SELECT DISTINCT bps.om_customer_invoice_owner(p_tenant_id, o.customer_id) AS owner_id
              FROM om_orders o
             WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND o.customer_id IS NOT NULL AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED') x
     WHERE x.owner_id IS NOT NULL
    ON CONFLICT (tenant_id, customer_id, production_run_id)
        WHERE transaction_type = 'INV' AND production_run_id IS NOT NULL AND status <> 'CANCELLED'
    DO NOTHING;

    -- What every invoice of the run should hold now: one row per order line (quantity > 0) and per delivery charge.
    -- line_key = 'L' || order_line_id or 'D' || order_id, used to compare with what an invoice posted to AR already holds.
    IF to_regclass('pg_temp._om_run_target') IS NULL THEN
        CREATE TEMP TABLE _om_run_target (
            ar_transaction_id bigint, line_key text, sort_no bigint, source_type text, item_id bigint, item_description text,
            quantity numeric, unit_price numeric, amount numeric, shipment_line_id bigint, order_id bigint, snapshot_data jsonb
        ) ON COMMIT DROP;
    ELSE
        TRUNCATE _om_run_target;
    END IF;
    INSERT INTO _om_run_target
    SELECT src.ar_transaction_id, src.line_key,
           ROW_NUMBER() OVER (PARTITION BY src.ar_transaction_id ORDER BY src.department_event, src.order_number, src.kind_rank, src.order_line_id),
           src.source_type, src.item_id, src.item_description, src.quantity, src.unit_price, src.amount, src.shipment_line_id, src.order_id,
           jsonb_build_object('order_id', src.order_id, 'order_number', src.order_number, 'order_line_id', src.order_line_id,
                              'department_event', src.department_event, 'customer_id', src.customer_id,
                              'customer_name', src.customer_name, 'po_number', src.po_number)
      FROM (
        SELECT inv.ar_transaction_id, 'L' || ol.order_line_id AS line_key, o.order_id, o.order_number, o.department_event, o.customer_id,
               o.customer_name, o.po_number, ol.order_line_id, 1 AS kind_rank, 'ITEM'::text AS source_type, ol.item_id,
               COALESCE(NULLIF(TRIM(ol.item_description), ''), i.item_name) AS item_description,
               ol.quantity, (ol.unit_price - COALESCE(ol.unit_discount, 0)) AS unit_price, ol.extended_amount AS amount,
               sl.shipment_line_id
          FROM om_orders o
          JOIN om_order_lines ol ON ol.order_id = o.order_id AND ol.tenant_id = o.tenant_id
          LEFT JOIN fnd_items i ON i.item_id = ol.item_id
          LEFT JOIN om_shipment_lines sl ON sl.order_line_id = ol.order_line_id AND sl.tenant_id = o.tenant_id
          JOIN ar_transactions inv
            ON inv.tenant_id = o.tenant_id AND inv.production_run_id = o.production_run_id
           AND inv.transaction_type = 'INV' AND inv.status <> 'CANCELLED'
           AND inv.customer_id = bps.om_customer_invoice_owner(o.tenant_id, o.customer_id)
         WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND ol.quantity > 0 AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED'
        UNION ALL
        SELECT inv.ar_transaction_id, 'D' || o.order_id, o.order_id, o.order_number, o.department_event, o.customer_id, o.customer_name, o.po_number,
               NULL::bigint, 2, 'DELIVERY', NULL::bigint, 'Delivery', 1, o.delivery_charge, o.delivery_charge, NULL::bigint
          FROM om_orders o
          JOIN ar_transactions inv
            ON inv.tenant_id = o.tenant_id AND inv.production_run_id = o.production_run_id
           AND inv.transaction_type = 'INV' AND inv.status <> 'CANCELLED'
           AND inv.customer_id = bps.om_customer_invoice_owner(o.tenant_id, o.customer_id)
         WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND o.delivery_charge > 0 AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED'
      ) src;

    -- Drafts (and, under RELAXED, invoices posted to AR): the invoice is rebuilt from the orders.
    -- Lines a credit memo points at are kept and updated in place, so the credit stays tied to its line.
    FOR v_inv IN
        SELECT t.* FROM ar_transactions t
         WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id AND t.transaction_type = 'INV'
           AND (t.status = 'DRAFT' OR (v_rules = 'RELAXED' AND t.status IN ('OPEN', 'PARTIAL', 'CLOSED')))
    LOOP
        UPDATE ar_transaction_lines l
           SET line_number = -l.line_number, source_type = x.source_type, item_id = x.item_id, item_description = x.item_description,
               quantity = x.quantity, unit_price = x.unit_price, amount = x.amount, shipment_line_id = x.shipment_line_id,
               order_id = x.order_id, snapshot_data = x.snapshot_data
          FROM _om_run_target x
         WHERE l.ar_transaction_id = v_inv.ar_transaction_id AND x.ar_transaction_id = v_inv.ar_transaction_id
           AND x.line_key = CASE WHEN l.source_type = 'DELIVERY' THEN 'D' || l.order_id ELSE 'L' || (l.snapshot_data ->> 'order_line_id') END
           AND l.quantity_credited > 0;
        DELETE FROM ar_transaction_lines l
         WHERE l.ar_transaction_id = v_inv.ar_transaction_id AND l.line_number > 0
           AND NOT (l.quantity_credited > 0 AND v_inv.status <> 'DRAFT');
        -- credited lines whose order line is gone stay (after the rebuilt lines)
        UPDATE ar_transaction_lines l SET line_number = 100000 + l.line_number
         WHERE l.ar_transaction_id = v_inv.ar_transaction_id AND l.line_number > 0;
        INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, source_type, item_id, item_description,
                                          quantity, unit_price, amount, shipment_line_id, order_id, snapshot_data)
        SELECT p_tenant_id, x.ar_transaction_id, x.sort_no, x.source_type, x.item_id, x.item_description, x.quantity, x.unit_price,
               x.amount, x.shipment_line_id, x.order_id, x.snapshot_data
          FROM _om_run_target x
         WHERE x.ar_transaction_id = v_inv.ar_transaction_id
           AND NOT EXISTS (SELECT 1 FROM ar_transaction_lines l WHERE l.ar_transaction_id = v_inv.ar_transaction_id AND l.line_number < 0
                             AND x.line_key = CASE WHEN l.source_type = 'DELIVERY' THEN 'D' || l.order_id ELSE 'L' || (l.snapshot_data ->> 'order_line_id') END);
        UPDATE ar_transaction_lines l SET line_number = x.sort_no
          FROM _om_run_target x
         WHERE l.ar_transaction_id = v_inv.ar_transaction_id AND l.line_number < 0 AND x.ar_transaction_id = v_inv.ar_transaction_id
           AND x.line_key = CASE WHEN l.source_type = 'DELIVERY' THEN 'D' || l.order_id ELSE 'L' || (l.snapshot_data ->> 'order_line_id') END;
        UPDATE ar_transactions t
           SET amount = COALESCE((SELECT SUM(l.amount) FROM ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id), 0),
               transaction_date = CASE WHEN t.status = 'DRAFT' THEN v_run.delivery_date ELSE t.transaction_date END
         WHERE t.ar_transaction_id = v_inv.ar_transaction_id;
    END LOOP;

    -- STRICT, invoices posted to AR: the invoice is never changed. The difference between what the orders hold now and
    -- what the invoice plus its earlier order-change memos hold becomes a debit memo (more) and/or a credit memo (less),
    -- applied to the invoice. Memo lines carry source ORDER_CHANGE and the line_key.
    IF v_rules = 'STRICT' THEN
        FOR v_inv IN
            SELECT t.* FROM ar_transactions t
             WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id AND t.transaction_type = 'INV'
               AND t.status IN ('OPEN', 'PARTIAL', 'CLOSED')
        LOOP
            -- keep the invoice lines tied to the rebuilt shipment lines
            UPDATE ar_transaction_lines l SET shipment_line_id = x.shipment_line_id
              FROM _om_run_target x
             WHERE l.ar_transaction_id = v_inv.ar_transaction_id AND x.ar_transaction_id = v_inv.ar_transaction_id
               AND l.source_type = 'ITEM' AND x.line_key = 'L' || (l.snapshot_data ->> 'order_line_id')
               AND l.shipment_line_id IS DISTINCT FROM x.shipment_line_id;

            v_date := (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date;
            FOR v_kind IN SELECT unnest(ARRAY['DM', 'CM']) LOOP
                v_memo_id := NULL;
                FOR v_delta IN
                    WITH cur AS (
                        SELECT CASE WHEN l.source_type = 'DELIVERY' THEN 'D' || l.order_id ELSE 'L' || (l.snapshot_data ->> 'order_line_id') END AS line_key,
                               l.quantity AS qty, l.amount, l.item_id, l.item_description, l.unit_price, l.source_type, l.order_id, l.snapshot_data
                          FROM ar_transaction_lines l WHERE l.ar_transaction_id = v_inv.ar_transaction_id
                        UNION ALL
                        SELECT ml.snapshot_data ->> 'line_key', CASE WHEN m.transaction_type = 'DM' THEN ml.quantity ELSE -ml.quantity END,
                               ml.amount, ml.item_id, ml.item_description, ml.unit_price, 'ITEM', ml.order_id, ml.snapshot_data
                          FROM ar_transactions m
                          JOIN ar_transaction_lines ml ON ml.ar_transaction_id = m.ar_transaction_id
                         WHERE m.tenant_id = p_tenant_id AND m.applies_to_ar_transaction_id = v_inv.ar_transaction_id
                           AND m.transaction_type IN ('DM', 'CM') AND m.status <> 'CANCELLED'
                           AND ml.snapshot_data ->> 'source' = 'ORDER_CHANGE'
                    ), c AS (
                        SELECT line_key, SUM(qty) AS qty, SUM(amount) AS amount,
                               (array_agg(item_id) FILTER (WHERE item_id IS NOT NULL))[1] AS item_id,
                               (array_agg(item_description))[1] AS item_description,
                               (array_agg(unit_price))[1] AS unit_price, (array_agg(order_id))[1] AS order_id,
                               (array_agg(snapshot_data))[1] AS snapshot_data
                          FROM cur GROUP BY line_key
                    )
                    SELECT COALESCE(x.line_key, c.line_key) AS line_key,
                           COALESCE(x.quantity, 0) - COALESCE(c.qty, 0) AS dq,
                           COALESCE(x.amount, 0) - COALESCE(c.amount, 0) AS da,
                           COALESCE(x.item_id, c.item_id) AS item_id,
                           COALESCE(x.item_description, c.item_description) AS item_description,
                           COALESCE(x.unit_price, c.unit_price) AS unit_price,
                           COALESCE(x.order_id, c.order_id) AS order_id,
                           COALESCE(x.snapshot_data, c.snapshot_data) AS snapshot_data,
                           COALESCE(x.sort_no, 999999) AS sort_no
                      FROM (SELECT * FROM _om_run_target WHERE ar_transaction_id = v_inv.ar_transaction_id) x
                      FULL JOIN c ON c.line_key = x.line_key
                     ORDER BY 9, 1
                LOOP
                    CONTINUE WHEN v_delta.da = 0 AND v_delta.dq = 0;
                    CONTINUE WHEN (v_kind = 'DM') <> (v_delta.da > 0 OR (v_delta.da = 0 AND v_delta.dq > 0));
                    IF v_memo_id IS NULL THEN
                        INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount,
                                                     status, applies_to_ar_transaction_id, production_run_id)
                        VALUES (p_tenant_id, v_inv.customer_id, v_kind,
                                bps.fnd_tenant_sequence_next(p_tenant_id, CASE WHEN v_kind = 'DM' THEN 'debit_memo_number' ELSE 'credit_memo_number' END, v_date),
                                v_date, 0, 'OPEN', v_inv.ar_transaction_id, NULL)
                        RETURNING ar_transaction_id INTO v_memo_id;
                        v_line_no := 0;
                        v_memos := v_memos + 1;
                    END IF;
                    v_line_no := v_line_no + 1;
                    INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, source_type, item_id, item_description,
                                                      quantity, unit_price, amount, order_id, snapshot_data)
                    VALUES (p_tenant_id, v_memo_id, v_line_no, 'ADJUSTMENT', v_delta.item_id, v_delta.item_description,
                            abs(v_delta.dq), v_delta.unit_price, v_delta.da, v_delta.order_id,
                            COALESCE(v_delta.snapshot_data, '{}'::jsonb) || jsonb_build_object('source', 'ORDER_CHANGE', 'line_key', v_delta.line_key,
                                                                          'invoice_number', v_inv.document_number));
                END LOOP;
                IF v_memo_id IS NOT NULL THEN
                    UPDATE ar_transactions SET amount = (SELECT SUM(amount) FROM ar_transaction_lines WHERE ar_transaction_id = v_memo_id)
                     WHERE ar_transaction_id = v_memo_id;
                END IF;
            END LOOP;
        END LOOP;
    END IF;

    -- invoices that no longer have any order: drop drafts, cancel numbered ones (never deleted; RELAXED only, a STRICT
    -- invoice keeps its lines and is credited instead)
    DELETE FROM ar_transactions t
     WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id AND t.transaction_type = 'INV'
       AND t.status = 'DRAFT' AND NOT EXISTS (SELECT 1 FROM ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id);
    UPDATE ar_transactions t SET status = 'CANCELLED'
     WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id AND t.transaction_type = 'INV'
       AND t.status IN ('OPEN', 'PARTIAL') AND NOT EXISTS (SELECT 1 FROM ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id);

    SELECT COUNT(*) FILTER (WHERE COALESCE(import_status, 'APPROVED') = 'APPROVED'), COUNT(*) FILTER (WHERE import_status IN ('IMPORTED', 'ISSUES'))
      INTO v_orders, v_held FROM om_orders WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id;
    SELECT COUNT(*) INTO v_ships  FROM om_shipments WHERE production_run_id = p_production_run_id;
    SELECT COUNT(*) INTO v_invs   FROM ar_transactions
     WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id AND transaction_type = 'INV' AND status <> 'CANCELLED';

    RETURN jsonb_build_object('production_run_id', p_production_run_id, 'production_date', v_run.production_date,
                              'production_code', v_run.production_code, 'orders', v_orders, 'shipments', v_ships, 'invoices', v_invs,
                              'orders_waiting_approval', v_held, 'memos', v_memos);
END;
$function$;
