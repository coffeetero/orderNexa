-- ============================================================
-- AR_TRANSACTIONS  –  Receivable documents (invoice, credit memo, …)
-- Target: Supabase (PostgreSQL 15+)
--
-- Open balance is NOT stored; derive from amount and ar_payment_applications.
--
-- Run after: fnd_entity_id_seq.sql, fnd_customers.sql, fnd_tenants.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS ar_transactions (
    ar_transaction_id       BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    tenant_id               BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    customer_id             BIGINT      NOT NULL REFERENCES fnd_customers(customer_id) ON DELETE RESTRICT,

    transaction_type        TEXT        NOT NULL DEFAULT 'INV',

    document_number         TEXT        NOT NULL,
    transaction_date        DATE        NOT NULL,
    due_date                DATE,

    currency_code           CHAR(3)     NOT NULL DEFAULT 'USD',

    -- Invoice / document total in transaction currency (positive for normal AR charges)
    amount                  NUMERIC(14,4) NOT NULL,

    status                  TEXT        NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'PARTIAL', 'CLOSED', 'CANCELLED')),

    legacy_ar_id            BIGINT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              BIGINT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              BIGINT,

    CONSTRAINT uq_ar_transactions_tenant_customer_doc
        UNIQUE (tenant_id, customer_id, document_number)
);

CREATE INDEX IF NOT EXISTS idx_ar_transactions_tenant_customer_date
    ON ar_transactions (tenant_id, customer_id, transaction_date DESC);

CREATE INDEX IF NOT EXISTS idx_ar_transactions_legacy_ar_id
    ON ar_transactions (tenant_id, legacy_ar_id)
    WHERE legacy_ar_id IS NOT NULL;


DROP TRIGGER IF EXISTS trg_ar_transactions_set_updated ON ar_transactions;
CREATE TRIGGER trg_ar_transactions_set_updated
    BEFORE UPDATE ON ar_transactions
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_ar_transactions_audit ON ar_transactions;
CREATE TRIGGER trg_ar_transactions_audit
    AFTER INSERT OR UPDATE OR DELETE ON ar_transactions
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('ar_transaction_id');


ALTER TABLE ar_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_transactions_tenant ON ar_transactions;
CREATE POLICY pol_ar_transactions_tenant ON ar_transactions
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

COMMENT ON TABLE ar_transactions IS
    'AR document header; balance = amount − sum(applications) for INVOICE type (subject to sign rules).';

COMMENT ON COLUMN ar_transactions.legacy_ar_id IS
    'Legacy public.ar row id when available (dataPump).';

COMMENT ON COLUMN ar_transactions.status IS
    'Document lifecycle: OPEN, PARTIAL, CLOSED, CANCELLED.';
