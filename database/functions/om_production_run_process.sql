-- ============================================================
-- om_production_run_process
-- "Process run": locks one run and prepares everything the reports print from. Staff only. Re-runnable until a
-- shipment has been shipped (it rebuilds the PLANNED shipments and the invoice lines; invoice numbers are kept).
--   1. run_status -> PROCESSED (processed_at/by).
--   2. Shipments: one PLANNED shipment per ship-to customer (the order's customer) and delivery method; one shipment
--      line per order line (quantity > 0). Shipment numbers come from the tenant sequence 'shipment_number'.
--   3. Invoices: one per invoice owner (om_customer_invoice_owner) per run, DRAFT until the Packaging print numbers it.
--      Lines: each order line with a quantity above zero (ITEM, net of discount) and each order's delivery charge (DELIVERY), ordered by
--      department/event, order number, line. Invoices whose orders are gone are deleted (DRAFT) or CANCELLED (numbered).
--   4. Invoice amounts = sum of lines.
-- Imported orders count only once their import is approved (om_orders.import_status APPROVED or not imported).
-- Returns { production_run_id, orders, shipments, invoices, orders_waiting_approval }.
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

    DELETE FROM ar_transaction_lines
     WHERE ar_transaction_id IN (SELECT ar_transaction_id FROM ar_transactions
                                  WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id
                                    AND transaction_type = 'INV' AND status <> 'CANCELLED');

    INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, source_type, item_id, item_description,
                                      quantity, unit_price, amount, shipment_line_id, order_id, snapshot_data)
    SELECT p_tenant_id, src.ar_transaction_id,
           ROW_NUMBER() OVER (PARTITION BY src.ar_transaction_id ORDER BY src.department_event, src.order_number, src.kind_rank, src.order_line_id),
           src.source_type, src.item_id, src.item_description, src.quantity, src.unit_price, src.amount, src.shipment_line_id, src.order_id,
           jsonb_build_object('order_id', src.order_id, 'order_number', src.order_number, 'order_line_id', src.order_line_id,
                              'department_event', src.department_event, 'customer_id', src.customer_id,
                              'customer_name', src.customer_name, 'po_number', src.po_number)
      FROM (
        SELECT inv.ar_transaction_id, o.order_id, o.order_number, o.department_event, o.customer_id, o.customer_name, o.po_number,
               ol.order_line_id, 1 AS kind_rank, 'ITEM'::text AS source_type, ol.item_id,
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
        SELECT inv.ar_transaction_id, o.order_id, o.order_number, o.department_event, o.customer_id, o.customer_name, o.po_number,
               NULL::bigint, 2, 'DELIVERY', NULL::bigint, 'Delivery', 1, o.delivery_charge, o.delivery_charge, NULL::bigint
          FROM om_orders o
          JOIN ar_transactions inv
            ON inv.tenant_id = o.tenant_id AND inv.production_run_id = o.production_run_id
           AND inv.transaction_type = 'INV' AND inv.status <> 'CANCELLED'
           AND inv.customer_id = bps.om_customer_invoice_owner(o.tenant_id, o.customer_id)
         WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND o.delivery_charge > 0 AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED'
      ) src;

    UPDATE ar_transactions t
       SET amount = COALESCE((SELECT SUM(l.amount) FROM ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id), 0),
           transaction_date = v_run.delivery_date
     WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id
       AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED';

    -- invoices that no longer have any order: drop drafts, cancel numbered ones (never deleted)
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
                              'orders_waiting_approval', v_held);
END;
$function$;
