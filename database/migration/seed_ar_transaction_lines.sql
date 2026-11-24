-- ============================================================
-- SEED ar_transaction_lines — OM shipment-based INVOICE + discount; legacy allowance
--
-- Run order: 1) Apply table DDL. 2) seed_om_orders. 3) seed_ar_transactions.
--   4) This file (seed_ar_transaction_lines), seed_ar_payments, seed_ar_payment_applications as needed.
--
-- Prerequisite: seed_ar_transactions.sql; seed_om_orders / om_order_lines /
--   om_order_lines for Alpine Bakery.
--
-- Link to om_orders: same rule as seed_ar_transactions — match tenant, customer,
--   and document_number to COALESCE(invc_no, order_number) via ordr + om_orders.
--
-- INVOICE lines: one row per om_order_lines of the order; ar_transaction_lines.order_id points at the order.
--   quantity = ordrLn.quantity; unit_price from ol (fallback extended_amount/quantity);
--   amount = ordrLn.quantity * that unit_price.
--
-- Fallback: one header line per transaction when no shipment rows (amount = arTrx.amount).
--
-- DISCOUNT lines: amount = -(ordrLn.quantity * ordrLn.unit_discount), unit_price = -ordrLn.unit_discount.
--
-- Allowance: legacy ar (non-zero ar_trn_allowance_amt) when legacy_ar_id is set;
--   otherwise skipped.
--
-- Tenant: Alpine Bakery
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted    INT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    DELETE FROM ar_transaction_lines WHERE tenant_id = v_tenant_id;

    -- 1) INVOICE detail from shipments (unit_price and quantity from OM)
    INSERT INTO ar_transaction_lines (
        tenant_id,
        ar_transaction_id,
        line_number,
        source_type,
        item_description,
        quantity,
        unit_price,
        amount,
        order_id,
        item_id,
        snapshot_data
    )
    SELECT
        arTrx.tenant_id,
        arTrx.ar_transaction_id,
        ROW_NUMBER() OVER (
            PARTITION BY arTrx.ar_transaction_id
            ORDER BY ordrLn.order_line_id
        )::INT as line_number,
        'ITEM' as source_type,
        'INVOICE' as item_description,
        ordrLn.quantity as quantity,
        COALESCE(
            ordrLn.unit_price,
            CASE
                WHEN COALESCE(ordrLn.quantity, 0) <> 0
                    THEN ordrLn.extended_amount / NULLIF(ordrLn.quantity, 0)
            END,
            0::NUMERIC(14,4)
        )::NUMERIC(14,4) as unit_price,
        (
            ordrLn.quantity * COALESCE(
                ordrLn.unit_price,
                CASE
                    WHEN COALESCE(ordrLn.quantity, 0) <> 0
                        THEN ordrLn.extended_amount / NULLIF(ordrLn.quantity, 0)
                END,
                0::NUMERIC(14,4)
            )
        )::NUMERIC(14,4) as amount,
        ordr.order_id,
        ordrLn.item_id,
        jsonb_build_object(
            'seed', 'invoice_from_om_order_lines',
            'order_line_id', ordrLn.order_line_id,
            'legacy_ar_trn_id', arTrx.legacy_ar_id
        )
    FROM ar_transactions arTrx
    INNER JOIN ordr lo
            ON lo.invc_no IS NOT NULL
           AND arTrx.document_number = lo.invc_no::BIGINT::TEXT
        INNER JOIN om_orders ordr
            ON ordr.tenant_id = arTrx.tenant_id
           AND ordr.order_number = lo.ordr_no::BIGINT::TEXT
    INNER JOIN om_order_lines ordrLn
        ON ordrLn.order_id = ordr.order_id
       AND ordrLn.tenant_id = arTrx.tenant_id
    WHERE arTrx.tenant_id = v_tenant_id;

    -- 2) Single header when no shipment-based lines exist for this transaction
    INSERT INTO ar_transaction_lines (
        tenant_id,
        ar_transaction_id,
        line_number,
        source_type,
        item_description,
        quantity,
        unit_price,
        amount,
        order_id,
        item_id,
        snapshot_data
    )
    SELECT
        arTrx.tenant_id,
        arTrx.ar_transaction_id,
        1,
        'ADJUSTMENT',
        'Invoice total (legacy seed)',
        1::NUMERIC(14,4),
        arTrx.amount,
        arTrx.amount,
        NULL::BIGINT,
        NULL::BIGINT,
        jsonb_build_object(
            'seed', 'line_1_header_total',
            'legacy_ar_trn_id', arTrx.legacy_ar_id
        )
    FROM ar_transactions arTrx
    WHERE arTrx.tenant_id = v_tenant_id
      AND NOT EXISTS (
          SELECT 1
          FROM ar_transaction_lines arTrxLn
          WHERE arTrxLn.tenant_id = v_tenant_id
            AND arTrxLn.ar_transaction_id = arTrx.ar_transaction_id
      );

    -- 3) DISCOUNT lines: amount = -(ordrLn.quantity * ordrLn.unit_discount); unit_price = -ordrLn.unit_discount
    INSERT INTO ar_transaction_lines (
        tenant_id,
        ar_transaction_id,
        line_number,
        source_type,
        item_description,
        quantity,
        unit_price,
        amount,
        order_id,
        item_id,
        snapshot_data
    )
    SELECT
        d.tenant_id,
        d.ar_transaction_id,
        d.base_ln + d.ord_in_txn::INT,
        'ADJUSTMENT',
        'DISCOUNT',
        d.ff_qty,
        d.unit_disc,
        d.line_amt,
        d.order_id,
        d.item_id,
        d.snapshot_data
    FROM (
        SELECT
            arTrx.tenant_id,
            arTrx.ar_transaction_id,
            ordr.order_id,
            ordrLn.quantity AS ff_qty,
            ordrLn.item_id,
            -(ordrLn.quantity * COALESCE(ordrLn.unit_discount, 0))::NUMERIC(14,4) AS line_amt,
            -COALESCE(ordrLn.unit_discount, 0)::NUMERIC(14,4) AS unit_disc,
            (SELECT COALESCE(MAX(arTrxLn.line_number), 0)
             FROM ar_transaction_lines arTrxLn
             WHERE arTrxLn.tenant_id = v_tenant_id
               AND arTrxLn.ar_transaction_id = arTrx.ar_transaction_id) AS base_ln,
            ROW_NUMBER() OVER (
                PARTITION BY arTrx.ar_transaction_id
                ORDER BY ordrLn.order_line_id
            ) AS ord_in_txn,
            jsonb_build_object(
                'seed', 'discount_from_om_order_lines',
                'order_line_id', ordrLn.order_line_id,
                'legacy_ar_trn_id', arTrx.legacy_ar_id,
                'om_order_lines.unit_discount', ordrLn.unit_discount
            ) AS snapshot_data
        FROM ar_transactions arTrx
        INNER JOIN ordr lo
            ON lo.invc_no IS NOT NULL
           AND arTrx.document_number = lo.invc_no::BIGINT::TEXT
        INNER JOIN om_orders ordr
            ON ordr.tenant_id = arTrx.tenant_id
           AND ordr.order_number = lo.ordr_no::BIGINT::TEXT
        INNER JOIN om_order_lines ordrLn
            ON ordrLn.order_id = ordr.order_id
           AND ordrLn.tenant_id = arTrx.tenant_id
        WHERE arTrx.tenant_id = v_tenant_id
          AND COALESCE(ordrLn.unit_discount, 0) <> 0
    ) d;

    -- 4) Allowance from legacy ar (only if table exists and legacy_ar_id is populated)
    IF to_regclass('bps.ar') IS NOT NULL THEN
        INSERT INTO ar_transaction_lines (
            tenant_id,
            ar_transaction_id,
            line_number,
            source_type,
            item_description,
            quantity,
            unit_price,
            amount,
            order_id,
            item_id,
            snapshot_data
        )
        SELECT
            arTrx.tenant_id,
            arTrx.ar_transaction_id,
            (SELECT COALESCE(MAX(arTrxLn.line_number), 0) + 1
             FROM ar_transaction_lines arTrxLn
             WHERE arTrxLn.tenant_id = v_tenant_id
               AND arTrxLn.ar_transaction_id = arTrx.ar_transaction_id),
            'ADJUSTMENT',
            'Allowance (legacy ar_trn_allowance_amt)',
            1::NUMERIC(14,4),
            CASE
                WHEN COALESCE(a.ar_trn_allowance_amt, 0) > 0
                    THEN -COALESCE(a.ar_trn_allowance_amt, 0)::NUMERIC(14,4)
                ELSE COALESCE(a.ar_trn_allowance_amt, 0)::NUMERIC(14,4)
            END,
            CASE
                WHEN COALESCE(a.ar_trn_allowance_amt, 0) > 0
                    THEN -COALESCE(a.ar_trn_allowance_amt, 0)::NUMERIC(14,4)
                ELSE COALESCE(a.ar_trn_allowance_amt, 0)::NUMERIC(14,4)
            END,
            NULL::BIGINT,
            NULL::BIGINT,
            jsonb_build_object(
                'seed', 'line_allowance',
                'legacy_ar_trn_id', arTrx.legacy_ar_id,
                'legacy_ar_trn_allowance_amt', a.ar_trn_allowance_amt
            )
        FROM ar_transactions arTrx
        INNER JOIN ar a ON a.ar_trn_id = arTrx.legacy_ar_id
        WHERE arTrx.tenant_id = v_tenant_id
          AND arTrx.legacy_ar_id IS NOT NULL
          AND COALESCE(a.ar_trn_allowance_amt, 0) <> 0;
    END IF;

    -- 5) Invoice-level discount (legacy ar_trn_discount_amt, stored negative) on invoices that have order lines
    INSERT INTO ar_transaction_lines (
        tenant_id, ar_transaction_id, line_number, source_type, item_description,
        quantity, unit_price, amount, order_id, item_id, snapshot_data
    )
    SELECT
        arTrx.tenant_id,
        arTrx.ar_transaction_id,
        (SELECT COALESCE(MAX(l.line_number), 0) + 1 FROM ar_transaction_lines l
          WHERE l.tenant_id = v_tenant_id AND l.ar_transaction_id = arTrx.ar_transaction_id),
        'ADJUSTMENT',
        'Invoice discount (legacy ar_trn_discount_amt)',
        1::NUMERIC(14,4),
        a.ar_trn_discount_amt::NUMERIC(14,4),
        a.ar_trn_discount_amt::NUMERIC(14,4),
        NULL::BIGINT,
        NULL::BIGINT,
        jsonb_build_object('seed', 'line_invoice_discount', 'legacy_ar_trn_id', arTrx.legacy_ar_id)
    FROM ar_transactions arTrx
    INNER JOIN ar a ON a.ar_trn_id = arTrx.legacy_ar_id
    WHERE arTrx.tenant_id = v_tenant_id
      AND COALESCE(a.ar_trn_discount_amt, 0) <> 0
      AND EXISTS (SELECT 1 FROM ar_transaction_lines l
                   WHERE l.tenant_id = v_tenant_id AND l.ar_transaction_id = arTrx.ar_transaction_id AND l.order_id IS NOT NULL);

    -- 5b) The amount due in the old system is ar_trn_amt + invoice discount + allowance + terms discount (payments were applied against it).
    --     Any gap between the lines and that amount becomes one explicit adjustment line, so the total matches the old invoice
    --     and the difference stays visible for review.
    INSERT INTO ar_transaction_lines (
        tenant_id, ar_transaction_id, line_number, source_type, item_description,
        quantity, unit_price, amount, order_id, item_id, snapshot_data
    )
    SELECT
        arTrx.tenant_id,
        arTrx.ar_transaction_id,
        x.max_ln + 1,
        'ADJUSTMENT',
        'Legacy adjustment to match the old invoice amount',
        1::NUMERIC(14,4),
        x.gap::NUMERIC(14,4),
        x.gap::NUMERIC(14,4),
        NULL::BIGINT,
        NULL::BIGINT,
        jsonb_build_object('seed', 'line_legacy_adjustment', 'legacy_ar_trn_id', arTrx.legacy_ar_id,
                           'legacy_amount_due', x.target, 'lines_total', x.lines_total)
    FROM ar_transactions arTrx
    INNER JOIN ar a ON a.ar_trn_id = arTrx.legacy_ar_id
    CROSS JOIN LATERAL (
        SELECT COALESCE(SUM(l.amount), 0) AS lines_total, COALESCE(MAX(l.line_number), 0) AS max_ln,
               (COALESCE(a.ar_trn_amt, 0) + COALESCE(a.ar_trn_discount_amt, 0) + COALESCE(a.ar_trn_allowance_amt, 0) + COALESCE(a.ar_trn_terms_discount_amt, 0)) AS target,
               (COALESCE(a.ar_trn_amt, 0) + COALESCE(a.ar_trn_discount_amt, 0) + COALESCE(a.ar_trn_allowance_amt, 0) + COALESCE(a.ar_trn_terms_discount_amt, 0)) - COALESCE(SUM(l.amount), 0) AS gap
          FROM ar_transaction_lines l
         WHERE l.tenant_id = v_tenant_id AND l.ar_transaction_id = arTrx.ar_transaction_id
    ) x
    WHERE arTrx.tenant_id = v_tenant_id
      AND ABS(x.gap) > 0.005;

    -- 6) The invoice total is what its lines add up to (after discount and allowance)
    UPDATE ar_transactions t SET amount = x.total
      FROM (SELECT ar_transaction_id, SUM(amount) AS total FROM ar_transaction_lines WHERE tenant_id = v_tenant_id GROUP BY ar_transaction_id) x
     WHERE t.ar_transaction_id = x.ar_transaction_id AND t.tenant_id = v_tenant_id AND t.amount IS DISTINCT FROM x.total;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'ar_transaction_lines: inserted % rows (last insert batch only)', v_inserted;
END $$;
