-- ============================================================
-- FND_TENANT_OPTIONS  –  Per-tenant catalog of configurable option definitions
-- Target: Supabase (PostgreSQL 15+)
--
-- Describes available option keys (code, label, value shape) for tenant-specific
-- settings or item/order metadata. Actual stored values typically live in JSONB
-- or a companion table keyed by option_code.
--
-- Prerequisites:
--   • fnd_entity_id_seq.sql
--   • fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log), fnd_tenants.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_tenant_options (
    tenant_id           BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    tenant_option_id    BIGINT        PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    option_code         TEXT          NOT NULL,
    label               TEXT          NOT NULL,
    value_type          TEXT          NOT NULL,
    sort_order          INT           NOT NULL DEFAULT 0 CHECK (sort_order >= 0),

    is_active           BOOLEAN       NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_by          BIGINT,

    CONSTRAINT uq_fnd_tenant_options_tenant_option_code UNIQUE (tenant_id, option_code)
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE fnd_tenant_options OWNER TO bps_owner;

ALTER TABLE fnd_tenant_options ADD COLUMN IF NOT EXISTS created_by BIGINT;
ALTER TABLE fnd_tenant_options ADD COLUMN IF NOT EXISTS updated_by BIGINT;

CREATE INDEX IF NOT EXISTS idx_fnd_tenant_options_tenant_id
    ON fnd_tenant_options (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_tenant_options_tenant_active_sort
    ON fnd_tenant_options (tenant_id, sort_order)
    WHERE is_active = TRUE;

COMMENT ON TABLE fnd_tenant_options IS
    'Catalog of option definitions per tenant (machine option_code, display label, value shape).';

COMMENT ON COLUMN fnd_tenant_options.option_code IS
    'Stable identifier for the option (e.g. ORDER_ENTRY_DEFAULT_SHIP_DATE).';

COMMENT ON COLUMN fnd_tenant_options.value_type IS
    'Logical type for stored values (e.g. STRING, NUMBER, BOOLEAN, DATE, JSON).';

COMMENT ON COLUMN fnd_tenant_options.sort_order IS
    'Display / enumeration order within the tenant.';

DROP TRIGGER IF EXISTS trg_fnd_tenant_options_set_updated ON fnd_tenant_options;
CREATE TRIGGER trg_fnd_tenant_options_set_updated
    BEFORE UPDATE ON fnd_tenant_options
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_tenant_options_audit ON fnd_tenant_options;
CREATE TRIGGER trg_fnd_tenant_options_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_tenant_options
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('tenant_option_id');

-- RLS policies: fnd_tenant_options_policies.sql
