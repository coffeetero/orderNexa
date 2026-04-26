-- ============================================================
-- SEED ar_payment_applications (driver: ar_payments)
--
-- Run order: 1) seed_ar_transactions. 2) seed_ar_payments. 3) This file.
--
-- Path (Alpine Bakery tenant):
--   pmt.ar_payment_id                    → ar_payment_applications.ar_payment_id
--   pmt.legacy_ar_trn_id                 → ar.ar_trn_id (PMT row)
--   ar.ar_trn_ref                          → pmt_detail.pd_pmt_no (normalized: trim, strip leading PMT)
--   pmt_detail.pd_ar_trn_id                → invoice public.ar → ar_transactions.ar_transaction_id
--   pmt_detail.pd_pmt_amt                  → applied_amount (abs)
--
-- Invoice → ar_transactions: legacy_ar_id = invoice ar.ar_trn_id OR document_number = invoice ar.ar_trn_ref
--   for same fnd_customers row as ar.cus_id.
--
-- Prerequisite: dataPump public.ar, public.pmt_detail; seed_ar_transactions; seed_ar_payments.
-- Tenant: Alpine Bakery
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted    INT;
BEGIN
    PERFORM set_config('statement_timeout', '0', true);

    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    IF to_regclass('public.pmt_detail') IS NULL THEN
        RAISE EXCEPTION 'public.pmt_detail not found — run dataPump.py';
    END IF;

    IF to_regclass('public.ar') IS NULL THEN
        RAISE EXCEPTION 'public.ar not found — run dataPump.py';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    ALTER TABLE ar_payment_applications DISABLE TRIGGER trg_ar_payment_applications_audit;

    BEGIN
        DELETE FROM ar_payment_applications WHERE tenant_id = v_tenant_id;

        INSERT INTO ar_payment_applications (
          tenant_id,
          ar_payment_id,
          ar_transaction_id,
          applied_amount
        )
        SELECT DISTINCT ON (pmt.ar_payment_id, pmtDtl.ctid)
          pmt.tenant_id,
          pmt.ar_payment_id,
          arTrx.ar_transaction_id AS ar_transaction_id, -- (ar invoice_id)
          ABS(COALESCE(pmtDtl.pd_pmt_amt, 0))::NUMERIC(14,4)
        FROM ar_payments pmt
        INNER JOIN ar arSrc
          ON arSrc.ar_trn_id = pmt.legacy_ar_trn_id
        INNER JOIN pmt_detail pmtDtl
          ON pmtDtl.pd_pmt_no = arSrc.ar_trn_ref
        INNER JOIN ar_transactions arTrx
          ON arTrx.legacy_ar_id = pmtDtl.pd_ar_trn_id
          AND arTrx.tenant_id = pmt.tenant_id;

        GET DIAGNOSTICS v_inserted = ROW_COUNT;
        RAISE NOTICE 'ar_payment_applications: inserted % rows', v_inserted;

    EXCEPTION WHEN OTHERS THEN
        ALTER TABLE ar_payment_applications ENABLE TRIGGER trg_ar_payment_applications_audit;
        RAISE;
    END;

    ALTER TABLE ar_payment_applications ENABLE TRIGGER trg_ar_payment_applications_audit;
END $$;
