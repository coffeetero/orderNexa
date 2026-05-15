-- ============================================================
-- FND_VALUESETS  –  Tenant-scoped value sets and cached UI values
-- Target: Supabase (PostgreSQL 15+)
--
-- Valueset SQL, when introduced, is a source loader only. Runtime UI reads
-- from fnd_valueset_values.
--
-- Prerequisites:
--   • fnd_entity_id_seq.sql
--   • fnd_customers.sql (fn_set_updated_at_ts_only, fn_audit_log)
--   • fnd_tenants.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_valuesets (
    tenant_id             BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    valueset_id           BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    valueset_code         TEXT        NOT NULL,
    valueset_name         TEXT        NOT NULL,
    value_type            TEXT        NOT NULL DEFAULT 'TEXT',
    control_type          TEXT        NOT NULL DEFAULT 'select',
    source_type           TEXT        NOT NULL DEFAULT 'STATIC'
                                      CHECK (source_type IN ('STATIC', 'SQL')),
    source_sql            TEXT,

    refresh_mode          TEXT        NOT NULL DEFAULT 'MANUAL'
                                      CHECK (refresh_mode IN ('MANUAL', 'SCHEDULED', 'ON_DEMAND')),
    refresh_status        TEXT        NOT NULL DEFAULT 'NEVER'
                                      CHECK (refresh_status IN ('NEVER', 'SUCCESS', 'FAILED')),
    last_refreshed_at     TIMESTAMPTZ,
    last_refresh_error    TEXT,

    is_active             BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by            BIGINT,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by            BIGINT,

    CONSTRAINT uq_fnd_valuesets_tenant_code UNIQUE (tenant_id, valueset_code),
    CONSTRAINT chk_fnd_valuesets_code_not_blank CHECK (NULLIF(TRIM(valueset_code), '') IS NOT NULL),
    CONSTRAINT chk_fnd_valuesets_sql_source CHECK (
        source_type <> 'SQL'
        OR NULLIF(TRIM(COALESCE(source_sql, '')), '') IS NOT NULL
    )
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE fnd_valuesets OWNER TO bps_owner;

CREATE INDEX IF NOT EXISTS idx_fnd_valuesets_tenant
    ON fnd_valuesets (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_valuesets_tenant_active
    ON fnd_valuesets (tenant_id, valueset_code)
    WHERE is_active = TRUE;

COMMENT ON TABLE fnd_valuesets IS
    'Tenant-scoped value set definitions. Runtime UI reads cached values from fnd_valueset_values.';

COMMENT ON COLUMN fnd_valuesets.source_type IS
    'STATIC values are maintained directly in fnd_valueset_values. SQL valuesets are refreshed into fnd_valueset_values before use.';

DROP TRIGGER IF EXISTS trg_fnd_valuesets_set_updated ON fnd_valuesets;
CREATE TRIGGER trg_fnd_valuesets_set_updated
    BEFORE UPDATE ON fnd_valuesets
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_valuesets_audit ON fnd_valuesets;
CREATE TRIGGER trg_fnd_valuesets_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_valuesets
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('valueset_id');


CREATE TABLE IF NOT EXISTS fnd_valueset_values (
    tenant_id             BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    valueset_value_id     BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    valueset_id           BIGINT      NOT NULL REFERENCES fnd_valuesets(valueset_id) ON DELETE CASCADE,

    value                 TEXT        NOT NULL,
    label                 TEXT        NOT NULL,
    display_order         INT         NOT NULL DEFAULT 0 CHECK (display_order >= 0),
    is_default            BOOLEAN     NOT NULL DEFAULT FALSE,
    is_disabled           BOOLEAN     NOT NULL DEFAULT FALSE,
    metadata              JSONB       NOT NULL DEFAULT '{}'::JSONB,

    source_hash           TEXT,
    refreshed_at          TIMESTAMPTZ,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by            BIGINT,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by            BIGINT,

    CONSTRAINT uq_fnd_valueset_values_tenant_valueset_value UNIQUE (tenant_id, valueset_id, value),
    CONSTRAINT chk_fnd_valueset_values_value_not_blank CHECK (NULLIF(TRIM(value), '') IS NOT NULL)
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE fnd_valueset_values OWNER TO bps_owner;

CREATE INDEX IF NOT EXISTS idx_fnd_valueset_values_tenant_valueset
    ON fnd_valueset_values (tenant_id, valueset_id);

CREATE INDEX IF NOT EXISTS idx_fnd_valueset_values_ui
    ON fnd_valueset_values (tenant_id, valueset_id, display_order, label)
    WHERE is_disabled = FALSE;

COMMENT ON TABLE fnd_valueset_values IS
    'Cached values shown by UI controls. SQL-backed valuesets refresh into this table before runtime use.';

DROP TRIGGER IF EXISTS trg_fnd_valueset_values_set_updated ON fnd_valueset_values;
CREATE TRIGGER trg_fnd_valueset_values_set_updated
    BEFORE UPDATE ON fnd_valueset_values
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_valueset_values_audit ON fnd_valueset_values;
CREATE TRIGGER trg_fnd_valueset_values_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_valueset_values
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('valueset_value_id');

-- RLS policies: fnd_valuesets_policies.sql
