-- ============================================================
-- SEED ar_transactions FROM om_orders + legacy public.ordr (not public.ar)
--
-- Run order: 1) Apply table DDL. 2) seed_om_orders. 3) This file (seed_ar_transactions).
--   4) seed_ar_transaction_lines, seed_ar_payments, seed_ar_payment_applications (in that order).
--
-- One row per order that matches legacy ordr on ordr_no = order_number.
-- Prerequisite: dataPump public.ordr; seed_om_orders (Alpine Bakery) populated.
-- Clears for this tenant (FK order): applications → receipts → lines → transactions.
--
--   transaction_type  → INV (adjust literal in INSERT if you need INVx / other codes)
--   document_number   → legacy ordr.invc_no (fallback: om_orders.order_number)
--   amount (ar_transactions) → om_orders.amount (seed_om_orders: ordr_amt + ordr_discount_amt; do not add discount_amount again)
--   transaction_date / due_date → order_date
--
-- legacy_ar_id: backfilled from public.ar (non-PMT) when ar.ar_trn_ref matches document_number
--   so seed_ar_payment_applications can join invoices by legacy ar_trn_id (pd_ar_trn_id).
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

    IF to_regclass('bps.ordr') IS NULL THEN
        RAISE EXCEPTION 'public.ordr not found — run dataPump.py to load legacy ordr';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    DELETE FROM ar_payment_applications WHERE tenant_id = v_tenant_id;
    DELETE FROM ar_payments WHERE tenant_id = v_tenant_id;
    DELETE FROM ar_transaction_lines WHERE tenant_id = v_tenant_id;
    DELETE FROM ar_transactions WHERE tenant_id = v_tenant_id;

    -- One invoice per legacy ar INV row (ar_trn_ref = invoice number). Orders reach it through ordr.invc_no (lines seed).
    INSERT INTO ar_transactions (
        tenant_id, customer_id, transaction_type, document_number, transaction_date, due_date,
        currency_code, amount, legacy_ar_id, status
    )
    SELECT
        c.tenant_id,
        c.customer_id,
        'INV',
        a.ar_trn_ref::BIGINT::TEXT,
        COALESCE(a.ar_trn_date, DATE '2000-01-01'),
        COALESCE(a.ar_trn_date, DATE '2000-01-01'),
        'USD',
        COALESCE(a.ar_trn_amt, 0)::NUMERIC(14,4),
        a.ar_trn_id::BIGINT,
        CASE WHEN COALESCE(a.ar_trn_bal, 0) = 0 THEN 'CLOSED'
             WHEN COALESCE(a.ar_trn_bal, 0) < COALESCE(a.ar_trn_amt, 0) THEN 'PARTIAL'
             ELSE 'OPEN' END
    FROM ar a
    INNER JOIN fnd_customers c
        ON c.tenant_id = v_tenant_id
       AND c.legacy_id = a.cus_id::INT
    WHERE a.ar_trn_type = 'INV'
      AND a.ar_trn_ref IS NOT NULL
      -- Not migrated: entries dated after tomorrow (the old system accepted entries with a wrong year).
      AND COALESCE(a.ar_trn_date, DATE '2000-01-01') <= CURRENT_DATE + 1;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'ar_transactions: inserted % rows (from om_orders + ordr; check transaction_type literal in seed file)', v_inserted;

    -- Old credits (CRE) become credit memos and old debits (DEB) invoices. The old system applied them to invoices with $0
    -- payments, so seed_ar_payment_applications links them like any invoice. Numbered CR-/DB- + old reference (or old id),
    -- so they cannot collide with invoice numbers. seed_ar_transaction_lines gives each one a legacy adjustment line.
    INSERT INTO ar_transactions (
        tenant_id, customer_id, transaction_type, document_number, transaction_date, due_date,
        currency_code, amount, legacy_ar_id, status
    )
    SELECT
        c.tenant_id,
        c.customer_id,
        CASE a.ar_trn_type WHEN 'CRE' THEN 'CM' ELSE 'INV' END,
        CASE a.ar_trn_type WHEN 'CRE' THEN 'CR-' ELSE 'DB-' END || COALESCE(a.ar_trn_ref::BIGINT::TEXT, a.ar_trn_id::TEXT),
        COALESCE(a.ar_trn_date, DATE '2000-01-01'),
        COALESCE(a.ar_trn_date, DATE '2000-01-01'),
        'USD',
        COALESCE(a.ar_trn_amt, 0)::NUMERIC(14,4),
        a.ar_trn_id::BIGINT,
        CASE WHEN COALESCE(a.ar_trn_bal, 0) = 0 THEN 'CLOSED' ELSE 'OPEN' END
    FROM ar a
    INNER JOIN fnd_customers c
        ON c.tenant_id = v_tenant_id
       AND c.legacy_id = a.cus_id::INT
    WHERE a.ar_trn_type IN ('CRE', 'DEB')
      AND COALESCE(a.ar_trn_date, DATE '2000-01-01') <= CURRENT_DATE + 1;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'ar_transactions: inserted % old credits/debits', v_inserted;

    -- DONT KNOW WHY WE NEED THIS
    -- IF to_regclass('bps.ar') IS NOT NULL THEN
    --     UPDATE ar_transactions t
    --     SET legacy_ar_id = m.ar_trn_id
    --     FROM (
    --         SELECT DISTINCT ON (cus.customer_id, trim(both FROM coalesce(a.ar_trn_ref::text, '')))
    --             cus.customer_id,
    --             trim(both FROM coalesce(a.ar_trn_ref::text, '')) AS doc_key,
    --             a.ar_trn_id
    --         FROM public.ar a
    --         INNER JOIN fnd_customers cus
    --             ON cus.tenant_id = v_tenant_id
    --            AND cus.legacy_id = a.cus_id::INT
    --         WHERE upper(trim(both FROM coalesce(a.ar_trn_type::text, ''))) <> 'PMT'
    --         ORDER BY cus.customer_id, trim(both FROM coalesce(a.ar_trn_ref::text, '')), a.ar_trn_id
    --     ) m
    --     WHERE t.tenant_id = v_tenant_id
    --       AND t.legacy_ar_id IS NULL
    --       AND t.customer_id = m.customer_id
    --       AND trim(both FROM t.document_number) = m.doc_key;
    -- END IF;
END $$;
