-- ============================================================
-- OM_PRODUCTION_RUNS  –  One row per tenant + production date + production code
--
-- A run groups the orders produced together. cutoff_at is computed from om_production_codes when the run is
-- created (first order for that date + code) and may be edited by staff (holidays, special runs).
-- run_status: OPEN (customers may order until cutoff) -> LOCKED -> PROCESSED -> CLOSED.
-- Only OPEN and CLOSED are set in this phase; LOCKED/PROCESSED are used by Process run (later phase).
-- *_printed_at record the last print of each report (set by the reports, later phase).
--
-- production_run_id uses fnd_entity_id_seq.
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_tenants.sql. Policies: ../policies/om_production_runs_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS om_production_runs (
    tenant_id               BIGINT       NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    production_run_id       BIGINT       PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    production_date         DATE         NOT NULL,
    production_code         TEXT         NOT NULL,
    delivery_date           DATE         NOT NULL,
    cutoff_at               TIMESTAMPTZ  NOT NULL,
    run_status              TEXT         NOT NULL DEFAULT 'OPEN',
    processed_at            TIMESTAMPTZ,
    processed_by            BIGINT,
    baker_sheet_printed_at  TIMESTAMPTZ,
    packaging_printed_at    TIMESTAMPTZ,
    labels_printed_at       TIMESTAMPTZ,
    delivery_printed_at     TIMESTAMPTZ,

    created_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by              BIGINT,
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_by              BIGINT,

    CONSTRAINT uq_om_production_runs_tenant_date_code UNIQUE (tenant_id, production_date, production_code),
    CONSTRAINT chk_om_production_runs_status CHECK (run_status IN ('OPEN', 'LOCKED', 'PROCESSED', 'CLOSED'))
);

ALTER TABLE om_production_runs OWNER TO bps_owner;

CREATE INDEX IF NOT EXISTS idx_om_production_runs_tenant_date
    ON om_production_runs (tenant_id, production_date DESC);

DROP TRIGGER IF EXISTS trg_om_production_runs_set_updated ON om_production_runs;
CREATE TRIGGER trg_om_production_runs_set_updated
    BEFORE UPDATE ON om_production_runs
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

COMMENT ON TABLE om_production_runs IS
    'A production date + code for a tenant: cutoff, status and report print times. Orders point here via om_orders.production_run_id.';

-- Orders point at their run.
ALTER TABLE om_orders ADD COLUMN IF NOT EXISTS production_run_id BIGINT REFERENCES om_production_runs(production_run_id);
CREATE INDEX IF NOT EXISTS idx_om_orders_production_run ON om_orders (production_run_id);
