-- ============================================================
-- FND_PRICEBOOKS  –  Named price lists (promo, contract, regional base, …)
-- Target: Supabase (PostgreSQL 15+)
--
-- Customer ↔ price book links: fnd_customer_pricebooks.sql (assignment_type + effective dates).
--
-- Prerequisites:
--   • fnd_entity_id_seq.sql
--   • fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log, …)
--   • fnd_tenants.sql
--   • fnd_currencies.sql
-- ============================================================


CREATE TABLE IF NOT EXISTS fnd_pricebooks (
    pricebook_id          BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    pricebook_name        TEXT        NOT NULL,
    description           TEXT,

    currency_id           BIGINT      NOT NULL REFERENCES fnd_currencies(currency_id),

    is_active             BOOLEAN     NOT NULL DEFAULT TRUE,

    tenant_id             BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by            BIGINT,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by            BIGINT
);

CREATE INDEX IF NOT EXISTS idx_fnd_pricebooks_tenant_id
    ON fnd_pricebooks (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_pricebooks_tenant_active
    ON fnd_pricebooks (tenant_id, is_active)
    WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_fnd_pricebooks_currency_id
    ON fnd_pricebooks (currency_id);


-- TRIGGERS  —  updated_at (ts_only), audit log
-- ============================================================

DROP TRIGGER IF EXISTS trg_fnd_pricebooks_set_updated ON fnd_pricebooks;
CREATE TRIGGER trg_fnd_pricebooks_set_updated
    BEFORE UPDATE ON fnd_pricebooks
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_pricebooks_audit ON fnd_pricebooks;
CREATE TRIGGER trg_fnd_pricebooks_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_pricebooks
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('pricebook_id');


-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE fnd_pricebooks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_pricebooks_tenant ON fnd_pricebooks;
CREATE POLICY pol_fnd_pricebooks_tenant ON fnd_pricebooks
    USING      (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT)
    WITH CHECK (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::BIGINT);

-- Existing DBs created before description existed
ALTER TABLE fnd_pricebooks ADD COLUMN IF NOT EXISTS description TEXT;

COMMENT ON TABLE fnd_pricebooks IS
    'Tenant-scoped price lists (e.g. promo/seasonal, negotiated contract, regional base). Item-level prices: fnd_pricebook_items.';

COMMENT ON COLUMN fnd_pricebooks.description IS
    'Optional longer notes (purpose, audience, internal reference).';

COMMENT ON COLUMN fnd_pricebooks.currency_id IS
    'FK to fnd_currencies; amounts in this book are in that currency.';

COMMENT ON COLUMN fnd_pricebooks.is_active IS
    'Soft-disable without deleting history.';

COMMENT ON COLUMN fnd_pricebooks.pricebook_name IS
    'Human-readable code or label for this list (e.g. legacy cus_price_cd / price book key).';


-- ============================================================
-- MIGRATION — drop effective dates from older fnd_pricebooks
-- ============================================================

ALTER TABLE fnd_pricebooks DROP CONSTRAINT IF EXISTS chk_fnd_pricebooks_effective_range;
DROP INDEX IF EXISTS idx_fnd_pricebooks_tenant_dates;
ALTER TABLE fnd_pricebooks DROP COLUMN IF EXISTS effective_start_date;
ALTER TABLE fnd_pricebooks DROP COLUMN IF EXISTS effective_end_date;
