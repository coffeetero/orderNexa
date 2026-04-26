-- ============================================================
-- AR_PAYMENTS  –  Payments received (check, ACH, cash, …)
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: fnd_customers.sql, fnd_tenants.sql
-- Applications: ar_payment_applications.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS ar_payments (
    ar_payment_id           BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    tenant_id               BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    customer_id             BIGINT      NOT NULL REFERENCES fnd_customers(customer_id) ON DELETE RESTRICT,

    payment_date            DATE        NOT NULL,
    amount                  NUMERIC(14,4) NOT NULL CHECK (amount > 0),

    payment_number          TEXT,
    payment_method          TEXT,
    reference_number        TEXT,

    legacy_ar_trn_id        BIGINT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              BIGINT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              BIGINT
);

CREATE INDEX IF NOT EXISTS idx_ar_payments_tenant_customer_date
    ON ar_payments (tenant_id, customer_id, payment_date DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ar_payments_legacy_ar_trn
    ON ar_payments (tenant_id, legacy_ar_trn_id)
    WHERE legacy_ar_trn_id IS NOT NULL;


DROP TRIGGER IF EXISTS trg_ar_payments_set_updated ON ar_payments;
CREATE TRIGGER trg_ar_payments_set_updated
    BEFORE UPDATE ON ar_payments
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_ar_payments_audit ON ar_payments;
CREATE TRIGGER trg_ar_payments_audit
    AFTER INSERT OR UPDATE OR DELETE ON ar_payments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('ar_payment_id');


ALTER TABLE ar_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_payments_tenant ON ar_payments;
CREATE POLICY pol_ar_payments_tenant ON ar_payments
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

COMMENT ON TABLE ar_payments IS
    'Payment header; legacy seed loads PMT rows from public.ar (see seed_ar_payments.sql).';

COMMENT ON COLUMN ar_payments.payment_number IS
    'Human-facing payment number (e.g. payment or batch number).';

COMMENT ON COLUMN ar_payments.legacy_ar_trn_id IS
    'Legacy public.ar.ar_trn_id for this payment row (PMT); unique per tenant with uq_ar_payments_legacy_ar_trn.';
