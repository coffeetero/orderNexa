-- ============================================================
-- FND_CURRENCIES  –  ISO 4217 currency master (global, not tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- currency_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
-- fnd_pricebooks.currency_id references this table.
--
-- Run after: fnd_entity_id_seq.sql, fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log)
-- Run before: fnd_pricebooks.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_currencies (
    currency_id     BIGINT PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    iso_code        CHAR(3)     NOT NULL UNIQUE,
    currency_name   TEXT        NOT NULL,
    decimal_places  SMALLINT    NOT NULL DEFAULT 2
        CHECK (decimal_places >= 0 AND decimal_places <= 10),

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      BIGINT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      BIGINT
);

-- Existing DBs created before created_by / updated_by
ALTER TABLE fnd_currencies ADD COLUMN IF NOT EXISTS created_by BIGINT;
ALTER TABLE fnd_currencies ADD COLUMN IF NOT EXISTS updated_by BIGINT;

CREATE INDEX IF NOT EXISTS idx_fnd_currencies_iso_code
    ON fnd_currencies (iso_code)
    WHERE is_active = TRUE;

COMMENT ON TABLE fnd_currencies IS
    'Global currency catalog (ISO 4217). Amounts in fnd_pricebooks / fnd_pricebook_items use the book''s currency.';

COMMENT ON COLUMN fnd_currencies.iso_code IS
    'ISO 4217 three-letter code (e.g. USD, EUR).';

COMMENT ON COLUMN fnd_currencies.decimal_places IS
    'Typical minor-unit precision for display and rounding (e.g. 2 for USD).';

DROP TRIGGER IF EXISTS trg_fnd_currencies_set_updated ON fnd_currencies;
CREATE TRIGGER trg_fnd_currencies_set_updated
    BEFORE UPDATE ON fnd_currencies
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_currencies_audit ON fnd_currencies;
CREATE TRIGGER trg_fnd_currencies_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_currencies
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('currency_id');

ALTER TABLE fnd_currencies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_currencies_select ON fnd_currencies;
CREATE POLICY pol_fnd_currencies_select ON fnd_currencies
    FOR SELECT
    USING (TRUE);

-- Bootstrap: USD required for default price books (idempotent)
INSERT INTO fnd_currencies (iso_code, currency_name, decimal_places)
VALUES ('USD', 'US Dollar', 2)
ON CONFLICT (iso_code) DO NOTHING;
