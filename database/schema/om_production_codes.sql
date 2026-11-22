-- ============================================================
-- OM_PRODUCTION_CODES  –  Per-tenant settings for each production code
--
-- production_code matches a value of the PRODUCTIONCODE valueset (MORNING, LUNCH, DINNER, SPECIAL1, SPECIAL2).
-- It cannot be a foreign key (the valueset is keyed by valueset_value_id), so om_production_run_get_or_create checks it.
--
-- A run's cutoff is: (production_date - cutoff_days_before) at cutoff_time, in fnd_tenants.time_zone.
-- delivery_date of a run = production_date + delivery_days_after.
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_tenants.sql (fnd_customers.sql). Policies: ../policies/om_production_codes_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS om_production_codes (
    tenant_id            BIGINT       NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    production_code      TEXT         NOT NULL,
    cutoff_time          TIME         NOT NULL,
    cutoff_days_before   INTEGER      NOT NULL DEFAULT 1,
    delivery_days_after  INTEGER      NOT NULL DEFAULT 1,
    is_active            BOOLEAN      NOT NULL DEFAULT TRUE,

    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by           BIGINT,
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_by           BIGINT,

    PRIMARY KEY (tenant_id, production_code),
    CONSTRAINT chk_om_production_codes_cutoff_days   CHECK (cutoff_days_before  >= 0),
    CONSTRAINT chk_om_production_codes_delivery_days CHECK (delivery_days_after >= 0),
    CONSTRAINT chk_om_production_codes_code          CHECK (production_code = UPPER(TRIM(production_code)) AND production_code <> '')
);

ALTER TABLE om_production_codes OWNER TO bps_owner;

DROP TRIGGER IF EXISTS trg_om_production_codes_set_updated ON om_production_codes;
CREATE TRIGGER trg_om_production_codes_set_updated
    BEFORE UPDATE ON om_production_codes
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

COMMENT ON TABLE om_production_codes IS
    'Per-tenant cutoff and delivery offsets for each PRODUCTIONCODE value. Drives om_production_runs.cutoff_at.';
