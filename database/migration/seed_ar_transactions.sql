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

    IF to_regclass('public.ordr') IS NULL THEN
        RAISE EXCEPTION 'public.ordr not found — run dataPump.py to load legacy ordr';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    DELETE FROM ar_payment_applications WHERE tenant_id = v_tenant_id;
    DELETE FROM ar_payments WHERE tenant_id = v_tenant_id;
    DELETE FROM ar_transaction_lines WHERE tenant_id = v_tenant_id;
    DELETE FROM ar_transactions WHERE tenant_id = v_tenant_id;

    INSERT INTO ar_transactions (
        tenant_id,
        customer_id,
        transaction_type,
        document_number,
        transaction_date,
        due_date,
        currency_code,
        amount,
        legacy_ar_id,
        status
    )
    SELECT
        ordr.tenant_id,
        ordr.customer_id,
        'INV' as transaction_type,
        COALESCE(
            NULLIF(trim(both from lo.invc_no::text), ''),
            trim(both from ordr.order_number)
        ) as document_number,
        COALESCE(ordr.order_date, DATE '2000-01-01') as transaction_date,
        COALESCE(ordr.order_date, DATE '2000-01-01') as due_date,
        'USD' as currency_code,
        ordr.amount::NUMERIC(14,4) as amount,
        ar_trn_id::BIGINT as legacy_ar_trn_id,
        'OPEN' as status
    FROM om_orders ordr
    INNER JOIN ordr lo
        ON lo.ordr_no = ordr.order_number::BIGINT
    INNER JOIN ar
      on ar.ar_trn_ref = lo.invc_no
    WHERE 
      ordr.customer_id IS NOT NULL;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'ar_transactions: inserted % rows (from om_orders + ordr; check transaction_type literal in seed file)', v_inserted;

    -- DONT KNOW WHY WE NEED THIS
    -- IF to_regclass('public.ar') IS NOT NULL THEN
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
