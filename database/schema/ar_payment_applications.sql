-- ============================================================
-- AR_PAYMENT_APPLICATIONS  –  Apply payments to AR documents (invoices, etc.)
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: ar_transactions.sql, ar_payments.sql
-- Prerequisite: fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log)
-- ============================================================

CREATE TABLE IF NOT EXISTS ar_payment_applications (
    tenant_id               BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    ar_payment_application_id BIGINT    PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    ar_payment_id           BIGINT      NOT NULL REFERENCES ar_payments(ar_payment_id) ON DELETE RESTRICT,
    ar_transaction_id       BIGINT      NOT NULL REFERENCES ar_transactions(ar_transaction_id) ON DELETE RESTRICT,

    applied_amount          NUMERIC(14,4) NOT NULL CHECK (applied_amount > 0),
    applied_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              BIGINT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              BIGINT
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE ar_payment_applications OWNER TO bps_owner;

CREATE INDEX IF NOT EXISTS idx_ar_payment_applications_payment
    ON ar_payment_applications (tenant_id, ar_payment_id);

CREATE INDEX IF NOT EXISTS idx_ar_payment_applications_transaction
    ON ar_payment_applications (tenant_id, ar_transaction_id);

DROP TRIGGER IF EXISTS trg_ar_payment_applications_set_updated ON ar_payment_applications;
CREATE TRIGGER trg_ar_payment_applications_set_updated
    BEFORE UPDATE ON ar_payment_applications
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_ar_payment_applications_audit ON ar_payment_applications;
CREATE TRIGGER trg_ar_payment_applications_audit
    AFTER INSERT OR UPDATE OR DELETE ON ar_payment_applications
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('ar_payment_application_id');

-- RLS policies: ar_payment_applications_policies.sql

COMMENT ON TABLE ar_payment_applications IS
    'Links a payment to an AR document; partial payments = multiple rows over time for same invoice.';
