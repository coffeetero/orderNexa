-- ============================================================
-- SEED ar_* settlements: close what the old system shows as closed
--
-- Run order: after seed_ar_payment_applications (needs add_ar_settlements.sql applied first).
--
-- Why: the old system's payment detail (pmt_detail) applies some payments twice (e.g. one check entered as two payments, both
-- applied to the same invoice), so the rebuilt applications leave old invoices overpaid and old payments with unapplied cash.
-- The old system's own stored balance (ar.ar_trn_bal) shows those documents as closed. This step settles the difference so
-- the open items match the old system; the documents and their applications stay as migrated.
--
-- Rule, per migrated document that is still open here (bps.ar_open_items):
--   old balance 0 or missing  → settled_amount = what is open here, settled_at = the document's own date
--   old balance not 0         → left alone (the old system also shows it open)
-- Documents created in BPS after go-live have no old row and are never touched.
-- Re-runnable: earlier settlements made by this step are cleared first.
--
-- Reads the legacy table ar and the legacy_* ids: migration-only, retired at production like the other seed files.
-- Tenant: Alpine Bakery
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_reason    CONSTANT TEXT := 'Closed in the old system (data migration)';
    v_trx       INT;
    v_pmt       INT;
BEGIN
    PERFORM set_config('statement_timeout', '0', true);
    PERFORM set_config('search_path', 'bps, public', true);   -- also run on its own (apply-to-cloud.sh), not only by seed_all.py

    SELECT tenant_id INTO v_tenant_id FROM fnd_tenants WHERE tenant_name = 'Alpine Bakery' LIMIT 1;
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;
    IF to_regclass('bps.ar') IS NULL THEN
        RAISE EXCEPTION 'Legacy table ar not found — run dataPump.py';
    END IF;

    -- start over (the open-items triggers recalculate the documents touched)
    UPDATE ar_transactions SET settled_amount = 0, settled_at = NULL, settled_reason = NULL
     WHERE tenant_id = v_tenant_id AND settled_reason = v_reason;
    UPDATE ar_payments SET settled_amount = 0, settled_at = NULL, settled_reason = NULL
     WHERE tenant_id = v_tenant_id AND settled_reason = v_reason;

    -- invoices and credit memos
    UPDATE ar_transactions t
       SET settled_amount = o.open_amount,
           settled_at     = t.transaction_date::timestamptz,
           settled_reason = v_reason
      FROM ar_open_items o, ar a
     WHERE o.tenant_id = v_tenant_id AND o.ar_transaction_id = t.ar_transaction_id
       AND t.tenant_id = v_tenant_id AND t.legacy_ar_id IS NOT NULL
       AND a.ar_trn_id = t.legacy_ar_id
       AND COALESCE(a.ar_trn_bal, 0) = 0;
    GET DIAGNOSTICS v_trx = ROW_COUNT;

    -- payments with unapplied cash (or applied beyond their amount)
    UPDATE ar_payments p
       SET settled_amount = -o.open_amount,
           settled_at     = p.payment_date::timestamptz,
           settled_reason = v_reason
      FROM ar_open_items o, ar a
     WHERE o.tenant_id = v_tenant_id AND o.ar_payment_id = p.ar_payment_id
       AND p.tenant_id = v_tenant_id AND p.legacy_ar_trn_id IS NOT NULL
       AND a.ar_trn_id = p.legacy_ar_trn_id
       AND COALESCE(a.ar_trn_bal, 0) = 0;
    GET DIAGNOSTICS v_pmt = ROW_COUNT;

    RAISE NOTICE 'Settled as closed in the old system: % invoices / credit memos, % payments', v_trx, v_pmt;
END $$;
