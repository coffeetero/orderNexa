-- ============================================================
-- SEED ar_payments FROM legacy public.ar (payment rows)
--
-- Run order: 1) Apply table DDL. 2) seed_fnd_customers. 3) seed_ar_transactions (optional for apps).
--   4) This file (seed_ar_payments). 5) seed_ar_payment_applications (pmt_detail applications).
--
-- Source: public.ar WHERE upper(trim(ar_trn_type::text)) = 'PMT'
--   customer_id   ← ar.cus_id → fnd_customers.legacy_id → fnd_customers.customer_id
--   payment_date  ← ar.ar_trn_date
--   payment_number← 'PMT' || trim(ar_trn_ref)
--   amount        ← abs(ar_trn_amt); rows with amount 0 are skipped (CHECK amount > 0)
--   payment_method← ar_trn_desc: ACH, CASH, MISC, WIRE, ZELLE; if numeric only → ACH
--   reference_number ← ar_trn_desc when numeric only, else NULL
--   legacy_ar_trn_id ← ar.ar_trn_id
--
-- Prerequisite: dataPump public.ar; fnd_customers for Alpine Bakery.
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

    IF to_regclass('public.ar') IS NULL THEN
        RAISE EXCEPTION 'public.ar not found — run dataPump.py';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    ALTER TABLE ar_payments DISABLE TRIGGER trg_ar_payments_audit;

    BEGIN
        DELETE FROM ar_payments WHERE tenant_id = v_tenant_id;

        INSERT INTO ar_payments (
            tenant_id,
            customer_id,
            payment_date,
            amount,
            payment_number,
            payment_method,
            reference_number,
            legacy_ar_trn_id
        )
        SELECT
            v_tenant_id,
            cus.customer_id,
            a.ar_trn_date::DATE,
            ABS(COALESCE(a.ar_trn_amt, 0))::NUMERIC(14,4) AS amount,
            ('PMT-' || trim(both from coalesce(a.ar_trn_ref::text, ''))) AS payment_number,
            CASE
                WHEN trim(both from coalesce(a.ar_trn_desc::text, '')) ~ '^[0-9]+$' THEN 'ACH'
                ELSE CASE upper(trim(both from coalesce(a.ar_trn_desc::text, '')))
                    WHEN 'ACH' THEN 'ACH'
                    WHEN 'CASH' THEN 'CASH'
                    WHEN 'MISC' THEN 'MISC'
                    WHEN 'WIRE' THEN 'WIRE'
                    WHEN 'ZELLE' THEN 'ZELLE'
                    ELSE 'MISC'
                END
            END AS payment_method,
            CASE
                WHEN trim(both from coalesce(a.ar_trn_desc::text, '')) ~ '^[0-9]+$'
                    THEN trim(both from a.ar_trn_desc::text)
                ELSE NULL
            END AS reference_number,
            a.ar_trn_id::BIGINT
        FROM ar a
        INNER JOIN fnd_customers cus
            ON cus.tenant_id = v_tenant_id
           AND cus.legacy_id = a.cus_id::INT
        WHERE upper(trim(both from coalesce(a.ar_trn_type::text, ''))) = 'PMT'
          AND ABS(COALESCE(a.ar_trn_amt, 0)) > 0;

        GET DIAGNOSTICS v_inserted = ROW_COUNT;
        RAISE NOTICE 'ar_payments: inserted % rows', v_inserted;

    EXCEPTION WHEN OTHERS THEN
        ALTER TABLE ar_payments ENABLE TRIGGER trg_ar_payments_audit;
        RAISE;
    END;

    ALTER TABLE ar_payments ENABLE TRIGGER trg_ar_payments_audit;
END $$;
