-- Order runs, production-code cutoffs and delivery methods (Phase 1 of order-to-invoice).
-- Generated from the files named below; apply in this order. Local only: NOT applied to the cloud project.
-- Requires add_user_nav_tracking.sql first (fnd_nav_app_user_id is not used here, but policies follow the same JWT claims).
SET search_path = bps, public;

-- ===== schema/fnd_tenants.sql (time_zone) =====
-- ============================================================
-- time_zone: IANA zone used to interpret per-tenant clock times (e.g. order cutoff). See om_production_codes.sql.
-- ============================================================
ALTER TABLE fnd_tenants ADD COLUMN IF NOT EXISTS time_zone TEXT NOT NULL DEFAULT 'America/New_York';
COMMENT ON COLUMN fnd_tenants.time_zone IS
    'IANA time zone of the tenant (cutoff times and delivery dates are read in this zone).';

-- ===== schema/om_production_codes.sql =====
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

-- ===== schema/om_delivery_methods.sql =====
-- ============================================================
-- OM_DELIVERY_METHODS  –  Per-tenant, table-driven delivery methods
--
-- e.g. OWN_TRUCK (is_own_fleet), CARRIER (UPS/FedEx, requires_tracking), COURIER (Uber), PICKUP.
-- is_own_fleet = true means the method appears on the driver's delivery sheet.
-- fnd_customers.delivery_method_code points here (null = inherit from the parent customer).
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_customers.sql, fnd_tenants.sql. Policies: ../policies/om_delivery_methods_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS om_delivery_methods (
    tenant_id              BIGINT       NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    delivery_method_code   TEXT         NOT NULL,
    delivery_method_name   TEXT         NOT NULL,
    is_own_fleet           BOOLEAN      NOT NULL DEFAULT FALSE,
    requires_tracking      BOOLEAN      NOT NULL DEFAULT FALSE,
    is_active              BOOLEAN      NOT NULL DEFAULT TRUE,

    created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by             BIGINT,
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_by             BIGINT,

    PRIMARY KEY (tenant_id, delivery_method_code),
    CONSTRAINT chk_om_delivery_methods_code CHECK (delivery_method_code = UPPER(TRIM(delivery_method_code)) AND delivery_method_code <> '')
);

ALTER TABLE om_delivery_methods OWNER TO bps_owner;

DROP TRIGGER IF EXISTS trg_om_delivery_methods_set_updated ON om_delivery_methods;
CREATE TRIGGER trg_om_delivery_methods_set_updated
    BEFORE UPDATE ON om_delivery_methods
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

COMMENT ON TABLE om_delivery_methods IS
    'Per-tenant delivery methods (own truck, carrier, courier, pickup). Referenced by customers and, later, shipments.';

-- Customer default delivery method (added here because fnd_customers is created before this table).
ALTER TABLE fnd_customers ADD COLUMN IF NOT EXISTS delivery_method_code TEXT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_fnd_customers_delivery_method') THEN
        ALTER TABLE fnd_customers
            ADD CONSTRAINT fk_fnd_customers_delivery_method
            FOREIGN KEY (tenant_id, delivery_method_code)
            REFERENCES om_delivery_methods (tenant_id, delivery_method_code);
    END IF;
END $$;

COMMENT ON COLUMN fnd_customers.delivery_method_code IS
    'Default delivery method. NULL = inherit from the nearest ancestor customer that has one.';

-- ===== schema/fnd_customers.sql (cutoff_extra_minutes) =====
-- Extra minutes this customer may keep ordering after a run's cutoff. NULL = inherit from the nearest ancestor that has a value.
ALTER TABLE fnd_customers ADD COLUMN IF NOT EXISTS cutoff_extra_minutes INTEGER;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_fnd_customers_cutoff_extra_minutes') THEN
        ALTER TABLE fnd_customers ADD CONSTRAINT chk_fnd_customers_cutoff_extra_minutes
            CHECK (cutoff_extra_minutes IS NULL OR cutoff_extra_minutes >= 0);
    END IF;
END $$;
COMMENT ON COLUMN fnd_customers.cutoff_extra_minutes IS
    'Extra minutes after a run''s cutoff_at during which this customer may still order. NULL = inherit from parent.';
-- delivery_method_code is added in om_delivery_methods.sql (needs that table for its foreign key).

-- ===== schema/om_orders.sql (delivery_charge) =====
-- Delivery charge entered with the order (billed to the customer; becomes an invoice line in a later phase).
ALTER TABLE om_orders
    ADD COLUMN IF NOT EXISTS delivery_charge NUMERIC(12,2) NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_om_orders_delivery_charge') THEN
        ALTER TABLE om_orders ADD CONSTRAINT chk_om_orders_delivery_charge CHECK (delivery_charge >= 0);
    END IF;
END $$;

-- production_run_id (FK to om_production_runs) is added in om_production_runs.sql.

-- ===== schema/om_production_runs.sql =====
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

-- ===== policies/om_production_codes_policies.sql =====
-- ============================================================
-- OM_PRODUCTION_CODES — Row Level Security
-- Everyone in an allowed tenant can read. Only tenant staff (tenant NOT in restricted_tenant_ids) can write.
-- Run after: om_production_codes.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_production_codes TO authenticated;
GRANT ALL ON TABLE om_production_codes TO bps_dev;

ALTER TABLE om_production_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_production_codes_read ON om_production_codes;
CREATE POLICY pol_om_production_codes_read ON om_production_codes
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
    );

DROP POLICY IF EXISTS pol_om_production_codes_staff_write ON om_production_codes;
CREATE POLICY pol_om_production_codes_staff_write ON om_production_codes
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    );

-- ===== policies/om_delivery_methods_policies.sql =====
-- ============================================================
-- OM_DELIVERY_METHODS — Row Level Security
-- Everyone in an allowed tenant can read. Only tenant staff (tenant NOT in restricted_tenant_ids) can write.
-- Run after: om_delivery_methods.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_delivery_methods TO authenticated;
GRANT ALL ON TABLE om_delivery_methods TO bps_dev;

ALTER TABLE om_delivery_methods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_delivery_methods_read ON om_delivery_methods;
CREATE POLICY pol_om_delivery_methods_read ON om_delivery_methods
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
    );

DROP POLICY IF EXISTS pol_om_delivery_methods_staff_write ON om_delivery_methods;
CREATE POLICY pol_om_delivery_methods_staff_write ON om_delivery_methods
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    );

-- ===== policies/om_production_runs_policies.sql =====
-- ============================================================
-- OM_PRODUCTION_RUNS — Row Level Security
-- Everyone in an allowed tenant can read. Only tenant staff (tenant NOT in restricted_tenant_ids) can write.
-- Run after: om_production_runs.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_production_runs TO authenticated;
GRANT ALL ON TABLE om_production_runs TO bps_dev;

ALTER TABLE om_production_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_production_runs_read ON om_production_runs;
CREATE POLICY pol_om_production_runs_read ON om_production_runs
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
    );

DROP POLICY IF EXISTS pol_om_production_runs_staff_write ON om_production_runs;
CREATE POLICY pol_om_production_runs_staff_write ON om_production_runs
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')
        ))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')
        )))
    );

-- ===== functions/om_production_cutoff_calc.sql =====
-- ============================================================
-- om_production_cutoff_calc
-- Default cutoff for a production date + code from om_production_codes:
--   (production_date - cutoff_days_before) at cutoff_time, in the tenant's time zone.
-- Returns NULL when the code has no active settings row.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_cutoff_calc(
    p_tenant_id       bigint,
    p_production_date date,
    p_production_code text
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT ((p_production_date - pc.cutoff_days_before) + pc.cutoff_time) AT TIME ZONE t.time_zone
      FROM om_production_codes pc
      JOIN fnd_tenants t ON t.tenant_id = pc.tenant_id
     WHERE pc.tenant_id       = p_tenant_id
       AND pc.production_code = UPPER(TRIM(p_production_code))
       AND pc.is_active;
$function$;

-- ===== functions/om_customer_cutoff_extra_minutes.sql =====
-- ============================================================
-- om_customer_cutoff_extra_minutes
-- Extra minutes a customer may order after a run's cutoff: the nearest ancestor-or-self with a value, else 0.
-- SECURITY DEFINER so a restricted user still sees the value inherited from a parent they cannot read; it exposes
-- one integer for a customer the caller is already ordering for.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_cutoff_extra_minutes(
    p_tenant_id   bigint,
    p_customer_id bigint
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.cutoff_extra_minutes, 0 AS depth
          FROM fnd_customers c
         WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.cutoff_extra_minutes, up.depth + 1
          FROM fnd_customers c
          JOIN up ON c.customer_id = up.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND up.depth < 10
    )
    SELECT COALESCE((SELECT cutoff_extra_minutes FROM up WHERE cutoff_extra_minutes IS NOT NULL ORDER BY depth LIMIT 1), 0);
$function$;

-- ===== functions/om_production_run_get_or_create.sql =====
-- ============================================================
-- om_production_run_get_or_create
-- Returns the run id for a tenant + production date + code, creating it (cutoff and delivery date from
-- om_production_codes) when it does not exist. Returns NULL when date or code is missing.
-- SECURITY DEFINER because a customer saving the first order of a run cannot insert runs under RLS; the function
-- checks the caller's allowed_tenant_ids itself (no JWT claims = trusted database connection).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_run_get_or_create(
    p_tenant_id       bigint,
    p_production_date date,
    p_production_code text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_claims jsonb := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb;
    v_code   text  := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_pc     om_production_codes%ROWTYPE;
    v_id     bigint;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;
    IF v_claims IS NOT NULL AND NOT (p_tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(v_claims -> 'app_metadata' -> 'allowed_tenant_ids')))) THEN
        RAISE EXCEPTION 'Not authorised for tenant %', p_tenant_id;
    END IF;
    IF p_production_date IS NULL OR v_code IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT production_run_id INTO v_id
      FROM om_production_runs
     WHERE tenant_id = p_tenant_id AND production_date = p_production_date AND production_code = v_code;
    IF v_id IS NOT NULL THEN
        RETURN v_id;
    END IF;

    SELECT * INTO v_pc
      FROM om_production_codes
     WHERE tenant_id = p_tenant_id AND production_code = v_code AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production code % has no cutoff settings for this tenant (Admin > Production Codes).', v_code;
    END IF;

    INSERT INTO om_production_runs (tenant_id, production_date, production_code, delivery_date, cutoff_at)
    VALUES (
        p_tenant_id, p_production_date, v_code,
        p_production_date + v_pc.delivery_days_after,
        bps.om_production_cutoff_calc(p_tenant_id, p_production_date, v_code)
    )
    ON CONFLICT (tenant_id, production_date, production_code) DO NOTHING
    RETURNING production_run_id INTO v_id;

    IF v_id IS NULL THEN
        SELECT production_run_id INTO v_id
          FROM om_production_runs
         WHERE tenant_id = p_tenant_id AND production_date = p_production_date AND production_code = v_code;
    END IF;
    RETURN v_id;
END;
$function$;

-- ===== functions/om_production_cutoff_get.sql =====
-- ============================================================
-- om_production_cutoff_get
-- Cutoff status for a production date + code (and optionally a customer, who may have extra minutes).
-- Reads the run when it exists, otherwise the default from om_production_codes. Never creates a run.
-- Returns: { production_run_id, run_status, cutoff_at, extra_minutes, effective_cutoff_at, time_zone, is_open }
-- is_open = run is OPEN (or does not exist yet) and now is before effective_cutoff_at (no settings = open).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_cutoff_get(
    p_tenant_id       bigint,
    p_production_date date,
    p_production_code text,
    p_customer_id     bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code      text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_run       om_production_runs%ROWTYPE;
    v_cutoff    timestamptz;
    v_extra     integer := 0;
    v_effective timestamptz;
    v_status    text;
    v_tz        text;
    v_open      boolean;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;
    SELECT time_zone INTO v_tz FROM fnd_tenants WHERE tenant_id = p_tenant_id;

    IF p_production_date IS NULL OR v_code IS NULL THEN
        RETURN jsonb_build_object('production_run_id', NULL, 'run_status', NULL, 'cutoff_at', NULL,
            'extra_minutes', 0, 'effective_cutoff_at', NULL, 'time_zone', v_tz, 'is_open', TRUE);
    END IF;

    SELECT * INTO v_run
      FROM om_production_runs
     WHERE tenant_id = p_tenant_id AND production_date = p_production_date AND production_code = v_code;
    IF FOUND THEN
        v_cutoff := v_run.cutoff_at;
        v_status := v_run.run_status;
    ELSE
        v_cutoff := bps.om_production_cutoff_calc(p_tenant_id, p_production_date, v_code);
    END IF;

    IF p_customer_id IS NOT NULL THEN
        v_extra := bps.om_customer_cutoff_extra_minutes(p_tenant_id, p_customer_id);
    END IF;
    IF v_cutoff IS NOT NULL THEN
        v_effective := v_cutoff + make_interval(mins => v_extra);
    END IF;

    v_open := COALESCE(v_status, 'OPEN') = 'OPEN'
          AND (v_effective IS NULL OR clock_timestamp() < v_effective);

    RETURN jsonb_build_object(
        'production_run_id',   v_run.production_run_id,
        'run_status',          v_status,
        'cutoff_at',           v_cutoff,
        'extra_minutes',       v_extra,
        'effective_cutoff_at', v_effective,
        'time_zone',           v_tz,
        'is_open',             v_open
    );
END;
$function$;

-- ===== functions/om_production_cutoff_assert.sql =====
-- ============================================================
-- om_production_cutoff_assert
-- Raises when a customer-restricted caller (tenant in the restricted_tenant_ids claim) tries to enter or change an
-- order for a run that is past its effective cutoff. Tenant staff are never blocked.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_cutoff_assert(
    p_tenant_id       bigint,
    p_production_date date,
    p_production_code text,
    p_customer_id     bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_restricted boolean;
    v_info       jsonb;
BEGIN
    SELECT p_tenant_id::text = ANY (ARRAY(
        SELECT jsonb_array_elements_text(
            NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')))
      INTO v_restricted;
    IF NOT COALESCE(v_restricted, FALSE) THEN
        RETURN;
    END IF;

    v_info := bps.om_production_cutoff_get(p_tenant_id, p_production_date, p_production_code, p_customer_id);
    IF (v_info ->> 'is_open')::boolean THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'Ordering for % (%) closed %. Please call the bakery to add or change this order.',
        p_production_date, UPPER(TRIM(p_production_code)),
        COALESCE(to_char((v_info ->> 'effective_cutoff_at')::timestamptz AT TIME ZONE (v_info ->> 'time_zone'),
                         'Dy Mon DD "at" HH12:MI AM'), 'already');
END;
$function$;

-- ===== functions/om_production_codes_get.sql =====
-- ============================================================
-- om_production_codes_get
-- Every value of the tenant's PRODUCTIONCODE valueset with its cutoff settings (NULL settings = not configured yet).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_codes_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'production_code',     UPPER(v.value),
               'label',               v.label,
               'cutoff_time',         to_char(pc.cutoff_time, 'HH24:MI'),
               'cutoff_days_before',  pc.cutoff_days_before,
               'delivery_days_after', pc.delivery_days_after,
               'is_active',           pc.is_active
           ) ORDER BY v.display_order, v.value), '[]'::jsonb)
      FROM fnd_valuesets s
      JOIN fnd_valueset_values v ON v.valueset_id = s.valueset_id
      LEFT JOIN om_production_codes pc
             ON pc.tenant_id = s.tenant_id AND pc.production_code = UPPER(v.value)
     WHERE s.tenant_id = p_tenant_id AND s.valueset_code = 'PRODUCTIONCODE';
$function$;

-- ===== functions/om_production_codes_save.sql =====
-- ============================================================
-- om_production_codes_save
-- Upserts the cutoff settings for one production code.
-- p_payload: { production_code, cutoff_time 'HH:MI', cutoff_days_before, delivery_days_after, is_active }
-- Staff only (RLS); the code must exist in the tenant's PRODUCTIONCODE valueset.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_codes_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_payload ->> 'production_code')), '');
BEGIN
    IF p_tenant_id IS NULL OR v_code IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id and production_code are required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM fnd_valuesets s JOIN fnd_valueset_values v ON v.valueset_id = s.valueset_id
         WHERE s.tenant_id = p_tenant_id AND s.valueset_code = 'PRODUCTIONCODE' AND UPPER(v.value) = v_code
    ) THEN
        RAISE EXCEPTION 'Production code % is not in the PRODUCTIONCODE list', v_code;
    END IF;

    INSERT INTO om_production_codes (tenant_id, production_code, cutoff_time, cutoff_days_before, delivery_days_after, is_active)
    VALUES (
        p_tenant_id, v_code,
        (p_payload ->> 'cutoff_time')::time,
        COALESCE((p_payload ->> 'cutoff_days_before')::integer, 1),
        COALESCE((p_payload ->> 'delivery_days_after')::integer, 1),
        COALESCE((p_payload ->> 'is_active')::boolean, TRUE)
    )
    ON CONFLICT (tenant_id, production_code) DO UPDATE SET
        cutoff_time         = EXCLUDED.cutoff_time,
        cutoff_days_before  = EXCLUDED.cutoff_days_before,
        delivery_days_after = EXCLUDED.delivery_days_after,
        is_active           = EXCLUDED.is_active;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Not allowed to change production code settings';
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'production_code', v_code);
END;
$function$;

-- ===== functions/om_delivery_methods_get.sql =====
-- ============================================================
-- om_delivery_methods_get  –  the tenant's delivery methods (active and inactive), ordered by name
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_delivery_methods_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'delivery_method_code', m.delivery_method_code,
               'delivery_method_name', m.delivery_method_name,
               'is_own_fleet',         m.is_own_fleet,
               'requires_tracking',    m.requires_tracking,
               'is_active',            m.is_active
           ) ORDER BY m.delivery_method_name), '[]'::jsonb)
      FROM om_delivery_methods m
     WHERE m.tenant_id = p_tenant_id;
$function$;

-- ===== functions/om_delivery_methods_save.sql =====
-- ============================================================
-- om_delivery_methods_save
-- Upserts one delivery method. Methods are never deleted (customers reference them); set is_active = false.
-- p_payload: { delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking, is_active }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_delivery_methods_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_payload ->> 'delivery_method_code')), '');
    v_name text := NULLIF(TRIM(p_payload ->> 'delivery_method_name'), '');
BEGIN
    IF p_tenant_id IS NULL OR v_code IS NULL OR v_name IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id, delivery_method_code and delivery_method_name are required';
    END IF;

    INSERT INTO om_delivery_methods (tenant_id, delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking, is_active)
    VALUES (
        p_tenant_id, v_code, v_name,
        COALESCE((p_payload ->> 'is_own_fleet')::boolean, FALSE),
        COALESCE((p_payload ->> 'requires_tracking')::boolean, FALSE),
        COALESCE((p_payload ->> 'is_active')::boolean, TRUE)
    )
    ON CONFLICT (tenant_id, delivery_method_code) DO UPDATE SET
        delivery_method_name = EXCLUDED.delivery_method_name,
        is_own_fleet         = EXCLUDED.is_own_fleet,
        requires_tracking    = EXCLUDED.requires_tracking,
        is_active            = EXCLUDED.is_active;

    RETURN jsonb_build_object('success', TRUE, 'delivery_method_code', v_code);
END;
$function$;

-- ===== functions/om_production_runs_get.sql =====
-- ============================================================
-- om_production_runs_get  –  runs in a production-date range with their order counts (newest first).
-- p_upcoming_only = true limits to runs from yesterday (tenant time zone) onward; the date is worked out here, not by the caller.
-- cutoff_local is the cutoff in the tenant's time zone ('YYYY-MM-DDTHH:MI') for editing.
-- ============================================================
DROP FUNCTION IF EXISTS bps.om_production_runs_get(bigint, date, date);

CREATE OR REPLACE FUNCTION bps.om_production_runs_get(p_tenant_id bigint, p_from date, p_to date, p_upcoming_only boolean DEFAULT false)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'production_run_id', r.production_run_id,
               'production_date',   r.production_date,
               'production_code',   r.production_code,
               'delivery_date',     r.delivery_date,
               'cutoff_at',         r.cutoff_at,
               'cutoff_local',      to_char(r.cutoff_at AT TIME ZONE t.time_zone, 'YYYY-MM-DD"T"HH24:MI'),
               'time_zone',         t.time_zone,
               'run_status',        r.run_status,
               'order_count',       (SELECT COUNT(*) FROM om_orders o WHERE o.production_run_id = r.production_run_id)
           ) ORDER BY r.production_date DESC, r.production_code), '[]'::jsonb)
      FROM om_production_runs r
      JOIN fnd_tenants t ON t.tenant_id = r.tenant_id
     WHERE r.tenant_id = p_tenant_id
       AND r.production_date BETWEEN COALESCE(p_from, DATE '0001-01-01') AND COALESCE(p_to, DATE '9999-12-31')
       AND (NOT p_upcoming_only OR r.production_date >= ((now() AT TIME ZONE t.time_zone)::date - 1));
$function$;

-- ============================================================
-- om_production_runs_get  –  runs in a production-date range with their order counts (newest first).
-- cutoff_local is the cutoff in the tenant's time zone ('YYYY-MM-DDTHH:MI') for editing.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_runs_get(p_tenant_id bigint, p_from date, p_to date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'production_run_id', r.production_run_id,
               'production_date',   r.production_date,
               'production_code',   r.production_code,
               'delivery_date',     r.delivery_date,
               'cutoff_at',         r.cutoff_at,
               'cutoff_local',      to_char(r.cutoff_at AT TIME ZONE t.time_zone, 'YYYY-MM-DD"T"HH24:MI'),
               'time_zone',         t.time_zone,
               'run_status',        r.run_status,
               'order_count',       (SELECT COUNT(*) FROM om_orders o WHERE o.production_run_id = r.production_run_id)
           ) ORDER BY r.production_date DESC, r.production_code), '[]'::jsonb)
      FROM om_production_runs r
      JOIN fnd_tenants t ON t.tenant_id = r.tenant_id
     WHERE r.tenant_id = p_tenant_id
       AND r.production_date BETWEEN COALESCE(p_from, DATE '0001-01-01') AND COALESCE(p_to, DATE '9999-12-31');
$function$;

-- ============================================================
-- om_production_runs_get  –  runs in a production-date range with their order counts (newest first)
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_runs_get(p_tenant_id bigint, p_from date, p_to date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'production_run_id', r.production_run_id,
               'production_date',   r.production_date,
               'production_code',   r.production_code,
               'delivery_date',     r.delivery_date,
               'cutoff_at',         r.cutoff_at,
               'run_status',        r.run_status,
               'order_count',       (SELECT COUNT(*) FROM om_orders o WHERE o.production_run_id = r.production_run_id)
           ) ORDER BY r.production_date DESC, r.production_code), '[]'::jsonb)
      FROM om_production_runs r
     WHERE r.tenant_id = p_tenant_id
       AND r.production_date BETWEEN COALESCE(p_from, DATE '0001-01-01') AND COALESCE(p_to, DATE '9999-12-31');
$function$;

-- ===== functions/om_production_run_cutoff_save.sql =====
-- ============================================================
-- om_production_run_cutoff_save  –  staff change one run's cutoff (holidays, special runs). OPEN runs only.
-- p_cutoff_local is a wall-clock time in the TENANT's time zone (fnd_tenants.time_zone), e.g. '2026-11-25 12:00'.
-- ============================================================
DROP FUNCTION IF EXISTS bps.om_production_run_cutoff_save(bigint, bigint, timestamptz);

CREATE OR REPLACE FUNCTION bps.om_production_run_cutoff_save(p_tenant_id bigint, p_production_run_id bigint, p_cutoff_local timestamp)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF p_tenant_id IS NULL OR p_production_run_id IS NULL OR p_cutoff_local IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id, p_production_run_id and p_cutoff_local are required';
    END IF;
    UPDATE om_production_runs r
       SET cutoff_at = p_cutoff_local AT TIME ZONE (SELECT t.time_zone FROM fnd_tenants t WHERE t.tenant_id = p_tenant_id)
     WHERE r.tenant_id = p_tenant_id AND r.production_run_id = p_production_run_id AND r.run_status = 'OPEN';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Run % not found, not open, or you are not allowed to change it', p_production_run_id;
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'production_run_id', p_production_run_id);
END;
$function$;

-- ============================================================
-- om_production_run_cutoff_save  –  staff change one run's cutoff (holidays, special runs). OPEN runs only.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_run_cutoff_save(p_tenant_id bigint, p_production_run_id bigint, p_cutoff_at timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF p_tenant_id IS NULL OR p_production_run_id IS NULL OR p_cutoff_at IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id, p_production_run_id and p_cutoff_at are required';
    END IF;
    UPDATE om_production_runs
       SET cutoff_at = p_cutoff_at
     WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id AND run_status = 'OPEN';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Run % not found, not open, or you are not allowed to change it', p_production_run_id;
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'production_run_id', p_production_run_id);
END;
$function$;

-- ===== functions/om_orders_get_v2.sql =====
-- ============================================================
-- om_orders_get_v2
-- Fetches order data for the order entry / management screens.
--
-- Modes:
--   Detail (p_order_id set):
--     Returns a single order with or without lines.
--
--   Department/Event suggestions (p_department_events_only = true):
--     Returns distinct department_event values for the combobox.
--     All orders are included regardless of department_event value —
--     the old filter on non-null department_event was removed because
--     orders defaulted to 'ORDER' and departments now always get a
--     department_event value from om_orders_save.
--
--   List (neither of the above):
--     Returns up to 500 order headers matching the filters.
--
-- Customer type: DEPARTMENT customers are looked up via their parent.
-- (LOCATION is no longer used — superseded by DEPARTMENT.)
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_orders_get_v2(
    p_tenant_id              bigint,
    p_order_id               bigint  DEFAULT NULL,
    p_customer_id            bigint  DEFAULT NULL,
    p_production_date_from   date    DEFAULT NULL,
    p_production_date_to     date    DEFAULT NULL,
    p_production_code        text    DEFAULT NULL,
    p_return_headers_only    boolean DEFAULT true,
    p_return_actives_only    boolean DEFAULT true,
    p_department_events_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_result                   JSONB;
    v_lookup_customer_id       BIGINT;
    v_production_code          TEXT;
    v_default_department_event TEXT := 'ORDER';
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── Detail mode: single order ─────────────────────────────────────────
    IF p_order_id IS NOT NULL THEN
        IF p_return_headers_only THEN
            SELECT jsonb_build_object(
                'order_id',         o.order_id,
                'order_number',     o.order_number,
                'po_number',        o.po_number,
                'order_date',       o.order_date,
                'production_date',  o.production_date,
                'production_code',  o.production_code,
                'delivery_amount',  o.delivery_charge,
                'production_run_id', o.production_run_id,
                'department_event', o.department_event,
                'amount',           o.amount,
                'total_quantity',   o.quantity,
                'discount_amount',  o.discount_amount,
                'customer_id',      o.customer_id,
                'customer_name',    COALESCE(o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', ''),
                'snapshot_data',    o.snapshot_data,
                'lines',            '[]'::JSONB
            ) INTO v_result
            FROM om_orders o
            LEFT JOIN fnd_customers c
                   ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
            LEFT JOIN fnd_customers top_c
                   ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
            WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id
              AND (NOT p_return_actives_only OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)));
        ELSE
            SELECT jsonb_build_object(
                'order_id',         o.order_id,
                'order_number',     o.order_number,
                'po_number',        o.po_number,
                'order_date',       o.order_date,
                'production_date',  o.production_date,
                'production_code',  o.production_code,
                'delivery_amount',  o.delivery_charge,
                'production_run_id', o.production_run_id,
                'department_event', o.department_event,
                'amount',           o.amount,
                'total_quantity',   o.quantity,
                'discount_amount',  o.discount_amount,
                'customer_id',      o.customer_id,
                'customer_name',    COALESCE(o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', ''),
                'snapshot_data',    o.snapshot_data,
                'lines',            COALESCE(lines_agg.lines, '[]'::JSONB)
            ) INTO v_result
            FROM om_orders o
            LEFT JOIN fnd_customers c
                   ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
            LEFT JOIN fnd_customers top_c
                   ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
            LEFT JOIN LATERAL (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'order_id',             l.order_id,
                        'order_line_id',        l.order_line_id,
                        'item_id',              l.item_id,
                        'item_number',          COALESCE(i.item_number, ''),
                        'item_description',     l.item_description,
                        'quantity',             l.quantity,
                        'unit_price',           COALESCE(l.unit_price, 0),
                        'unit_discount',        l.unit_discount,
                        'extended_amount',      COALESCE(l.extended_amount, 0),
                        'allowed_prep_options', COALESCE(prep_allowed.allowed_prep_options, '[]'::JSONB),
                        'prep_options',         COALESCE(l.prep_options, '[]'::JSONB),
                        'is_scored',            FALSE,
                        'can_score',            FALSE
                    ) ORDER BY l.order_line_id
                ) AS lines
                FROM om_order_lines l
                LEFT JOIN fnd_items i ON i.item_id = l.item_id
                LEFT JOIN LATERAL (
                    SELECT COALESCE(
                        jsonb_agg(jsonb_build_object('value', vv.value, 'label', vv.label) ORDER BY vv.display_order, vv.label),
                        '[]'::JSONB
                    ) AS allowed_prep_options
                    FROM jsonb_array_elements_text(COALESCE(i.allowed_prep_options, '[]'::JSONB)) opt(value)
                    JOIN fnd_valuesets vs
                      ON vs.tenant_id = i.tenant_id AND vs.valueset_code = 'ITEMPREP' AND vs.is_active = TRUE
                    JOIN fnd_valueset_values vv
                      ON vv.tenant_id = vs.tenant_id AND vv.valueset_id = vs.valueset_id
                     AND vv.value = opt.value AND vv.is_disabled = FALSE
                ) prep_allowed ON TRUE
                WHERE l.order_id = o.order_id AND l.tenant_id = o.tenant_id
            ) lines_agg ON TRUE
            WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id
              AND (NOT p_return_actives_only OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)));
        END IF;
        RETURN COALESCE(v_result, 'null'::JSONB);
    END IF;

    -- ── Resolve lookup customer + default department_event ────────────────
    v_lookup_customer_id := p_customer_id;
    v_production_code    := NULLIF(UPPER(TRIM(p_production_code)), '');

    IF p_customer_id IS NOT NULL THEN
        SELECT
            CASE WHEN UPPER(TRIM(customer_type)) = 'DEPARTMENT' AND customer_parent_id IS NOT NULL
                 THEN customer_parent_id ELSE customer_id END,
            CASE WHEN UPPER(TRIM(customer_type)) = 'DEPARTMENT'
                 THEN UPPER(TRIM(customer_name)) ELSE 'ORDER' END
          INTO v_lookup_customer_id, v_default_department_event
          FROM fnd_customers
         WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id;
    END IF;

    -- ── Department/Event suggestions ──────────────────────────────────────
    -- Returns distinct department_event values for the combobox.
    -- No filter on null/blank department_event — all orders are included.
    IF p_department_events_only THEN
        SELECT jsonb_agg(jsonb_build_object('department_event', department_event) ORDER BY department_event)
          INTO v_result
          FROM (
              SELECT DISTINCT UPPER(TRIM(o.department_event)) AS department_event
                FROM om_orders o
                LEFT JOIN fnd_customers c
                       ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
                LEFT JOIN fnd_customers top_c
                       ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
               WHERE o.tenant_id  = p_tenant_id
                 AND v_lookup_customer_id IS NOT NULL
                 AND o.customer_id = v_lookup_customer_id
                 AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
                 AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
                 AND (NOT p_return_actives_only OR o.customer_id IS NULL
                      OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)))
          ) suggestions;
        RETURN COALESCE(v_result, '[]'::JSONB);
    END IF;

    -- ── Order headers list ────────────────────────────────────────────────
    SELECT jsonb_agg(row_data ORDER BY customer_name_sort ASC, department_event_sort ASC, order_id_sort DESC)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'order_id',         o.order_id,
            'order_number',     o.order_number,
            'po_number',        o.po_number,
            'order_date',       o.order_date,
            'production_date',  o.production_date,
            'production_code',  o.production_code,
            'department_event', o.department_event,
            'amount',           o.amount,
            'customer_id',      o.customer_id,
            'customer_name',    o.customer_name
        ) AS row_data,
        o.order_id AS order_id_sort,
        COALESCE(o.customer_name, '') AS customer_name_sort,
        COALESCE(o.department_event, '') AS department_event_sort
        FROM om_orders o
       WHERE o.tenant_id = p_tenant_id
         AND (v_lookup_customer_id IS NULL OR o.customer_id = v_lookup_customer_id)
         AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
         AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
         AND (v_production_code IS NULL OR o.production_code = v_production_code)
       ORDER BY customer_name_sort ASC, department_event_sort ASC, o.order_id DESC
       LIMIT 500
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$function$;

-- ===== functions/om_orders_save.sql =====
-- ============================================================
-- om_orders_save
-- Atomically saves an order header + lines.
--
-- department_event defaulting (new orders only):
--   1. If department_event is passed in the payload → use it
--   2. Else if customer is DEPARTMENT → use the department's customer_name
--   3. Else → default to 'ORDER'
--
-- When department_event collides with an existing order for the same
-- slot (customer + production_date + production_code + department_event),
-- a suffix is appended: 'ORDER-01', 'KITCHEN-02', etc.
--
-- delivery_amount (payload) is stored in om_orders.delivery_charge; entered with the order, defaults to 0.
--
-- DEPARTMENT customers: order is stored under the parent customer_id.
-- (LOCATION type is no longer used — replaced by DEPARTMENT.)
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_orders_save(
    p_tenant_id bigint,
    p_action    text    DEFAULT NULL,
    p_order_id  bigint  DEFAULT NULL,
    p_payload   jsonb   DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_order_id     BIGINT;
    v_order_number TEXT;
    v_po_number    TEXT;
    v_mode         TEXT;
    v_line         JSONB;
    v_line_id      BIGINT;
    v_deleted_line_count INTEGER := 0;
    v_line_refs    JSONB := '[]'::JSONB;
    v_qty          NUMERIC(14,4);
    v_price        NUMERIC(14,4);
    v_discount     NUMERIC(14,4);
    v_extended     NUMERIC(14,4);
    v_total_qty    NUMERIC(14,4) := 0;
    v_total_amt    NUMERIC(14,4) := 0;
    v_total_disc   NUMERIC(14,4) := 0;
    v_payload_customer_id   BIGINT;
    v_order_customer_id     BIGINT;
    v_order_customer_name   TEXT;
    v_is_department         BOOLEAN := FALSE;
    v_payload_customer_name TEXT;
    v_production_date DATE;
    v_production_code TEXT;
    v_department_event TEXT;
    v_base_department_event TEXT;
    v_next_department_event_suffix INTEGER;
    v_requires_gapless BOOLEAN;
    v_constraint_name TEXT;
    v_has_po_number BOOLEAN := FALSE;
    v_delivery_charge NUMERIC(12,2);
    v_run_id        BIGINT;
    v_old_order     om_orders%ROWTYPE;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── DELETE ────────────────────────────────────────────────────────────
    IF LOWER(COALESCE(p_action, '')) = 'delete' THEN
        IF p_order_id IS NULL THEN
            RAISE EXCEPTION 'p_order_id is required for delete';
        END IF;
        SELECT * INTO v_old_order FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF FOUND THEN
            PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_old_order.production_date,
                                                    v_old_order.production_code, v_old_order.customer_id);
        END IF;
        v_requires_gapless := FALSE;
        SELECT COALESCE(seq.requires_gapless, FALSE)
          INTO v_requires_gapless
          FROM fnd_tenant_sequences seq
         WHERE seq.tenant_id = p_tenant_id
           AND seq.sequence_name = 'order_number';
        IF COALESCE(v_requires_gapless, FALSE) THEN
            RAISE EXCEPTION 'Order % cannot be deleted because this tenant requires gapless order numbers. Cancel or void the order instead.', p_order_id;
        END IF;
        DELETE FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', p_order_id;
        END IF;
        RETURN jsonb_build_object('success', TRUE, 'order_id', p_order_id, 'order_number', NULL, 'message', 'Order deleted.');
    END IF;

    IF p_payload IS NULL THEN
        RAISE EXCEPTION 'p_payload is required';
    END IF;

    v_production_date  := NULLIF(TRIM(p_payload->>'production_date'), '')::DATE;
    v_production_code  := NULLIF(UPPER(TRIM(p_payload->>'production_code')), '');
    v_department_event := NULLIF(UPPER(TRIM(p_payload->>'department_event')), '');
    v_po_number        := NULLIF(TRIM(p_payload->>'po_number'), '');

    SELECT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = 'bps'
           AND table_name = 'om_orders'
           AND column_name = 'po_number'
    ) INTO v_has_po_number;

    v_payload_customer_id := NULLIF((p_payload->>'customer_id')::TEXT, 'null')::BIGINT;
    v_order_customer_id   := v_payload_customer_id;

    -- ── Customer lookup: DEPARTMENT → store order under parent ───────────
    IF v_payload_customer_id IS NOT NULL THEN
        SELECT
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'DEPARTMENT'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_id
                ELSE selected.customer_id
            END,
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'DEPARTMENT'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_name
                ELSE selected.customer_name
            END,
            UPPER(TRIM(selected.customer_type)) = 'DEPARTMENT',
            selected.customer_name
          INTO v_order_customer_id, v_order_customer_name,
               v_is_department, v_payload_customer_name
          FROM fnd_customers selected
          LEFT JOIN fnd_customers parent
                 ON parent.tenant_id   = selected.tenant_id
                AND parent.customer_id = selected.customer_parent_id
         WHERE selected.tenant_id   = p_tenant_id
           AND selected.customer_id = v_payload_customer_id;
    END IF;

    -- ── Cutoff: customers cannot enter or change orders for a run past its cutoff ──
    IF p_order_id IS NOT NULL THEN
        SELECT * INTO v_old_order FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF FOUND THEN
            PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_old_order.production_date,
                                                    v_old_order.production_code, v_old_order.customer_id);
        END IF;
    END IF;
    PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_production_date, v_production_code, v_order_customer_id);
    v_run_id := bps.om_production_run_get_or_create(p_tenant_id, v_production_date, v_production_code);
    v_delivery_charge := COALESCE(NULLIF(TRIM(p_payload->>'delivery_amount'), '')::NUMERIC, 0);
    IF v_delivery_charge < 0 THEN
        RAISE EXCEPTION 'delivery_amount cannot be negative';
    END IF;

    -- ── Default department_event when not supplied in payload ─────────────
    -- 1. Passed in payload → already in v_department_event
    -- 2. Customer is DEPARTMENT → use department's own customer_name
    -- 3. Otherwise → 'ORDER'
    IF v_department_event IS NULL THEN
        v_department_event := CASE
            WHEN v_is_department THEN UPPER(TRIM(v_payload_customer_name))
            ELSE 'ORDER'
        END;
    END IF;

    -- ── HEADER INSERT (new order) ─────────────────────────────────────────
    IF p_order_id IS NULL THEN
        v_base_department_event := v_department_event;

        v_order_number := TRIM(p_payload->>'order_number');
        IF v_order_number IS NULL OR v_order_number = '' OR v_order_number = 'New Order' THEN
            v_order_number := fnd_tenant_sequence_next(
                p_tenant_id, 'order_number', COALESCE(v_production_date, CURRENT_DATE)
            );
        END IF;

        -- Check for collision; append suffix if needed
        IF EXISTS (
            SELECT 1 FROM om_orders existing
             WHERE existing.tenant_id       = p_tenant_id
               AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
               AND existing.production_date = v_production_date
               AND existing.production_code IS NOT DISTINCT FROM v_production_code
               AND existing.department_event = v_base_department_event
        ) THEN
            SELECT COALESCE(MAX(
                CASE
                    WHEN existing.department_event = v_base_department_event THEN 0
                    WHEN substring(existing.department_event FROM length(v_base_department_event) + 2) ~ '^[0-9]+$'
                    THEN substring(existing.department_event FROM length(v_base_department_event) + 2)::INTEGER
                    ELSE NULL
                END), 0) + 1
              INTO v_next_department_event_suffix
              FROM om_orders existing
             WHERE existing.tenant_id       = p_tenant_id
               AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
               AND existing.production_date = v_production_date
               AND existing.production_code IS NOT DISTINCT FROM v_production_code
               AND (existing.department_event = v_base_department_event
                    OR existing.department_event LIKE v_base_department_event || '-%');
            v_department_event := v_base_department_event || '-' || LPAD(v_next_department_event_suffix::TEXT, 2, '0');
        END IF;

        LOOP
            BEGIN
                IF v_has_po_number THEN
                    INSERT INTO om_orders (
                        order_number, po_number, order_date, production_date, production_code,
                        quantity, amount, discount_amount,
                        customer_id, customer_name, department_event,
                        order_source, tenant_id, snapshot_data,
                        delivery_charge, production_run_id
                    ) VALUES (
                        v_order_number,
                        v_po_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB),
                        v_delivery_charge, v_run_id
                    )
                    RETURNING order_id INTO v_order_id;
                ELSE
                    INSERT INTO om_orders (
                        order_number, order_date, production_date, production_code,
                        quantity, amount, discount_amount,
                        customer_id, customer_name, department_event,
                        order_source, tenant_id, snapshot_data,
                        delivery_charge, production_run_id
                    ) VALUES (
                        v_order_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB),
                        v_delivery_charge, v_run_id
                    )
                    RETURNING order_id INTO v_order_id;
                END IF;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
                IF v_constraint_name <> 'uq_om_orders_slot_department_event' THEN RAISE; END IF;
                SELECT COALESCE(MAX(
                    CASE
                        WHEN existing.department_event = v_base_department_event THEN 0
                        WHEN substring(existing.department_event FROM length(v_base_department_event) + 2) ~ '^[0-9]+$'
                        THEN substring(existing.department_event FROM length(v_base_department_event) + 2)::INTEGER
                        ELSE NULL
                    END), 0) + 1
                  INTO v_next_department_event_suffix
                  FROM om_orders existing
                 WHERE existing.tenant_id       = p_tenant_id
                   AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
                   AND existing.production_date = v_production_date
                   AND existing.production_code IS NOT DISTINCT FROM v_production_code
                   AND (existing.department_event = v_base_department_event
                        OR existing.department_event LIKE v_base_department_event || '-%');
                v_department_event := v_base_department_event || '-' || LPAD(v_next_department_event_suffix::TEXT, 2, '0');
            END;
        END LOOP;
        v_mode := 'created';

    ELSE
        -- ── HEADER UPDATE ─────────────────────────────────────────────────
        v_order_id := p_order_id;
        IF v_has_po_number THEN
            UPDATE om_orders SET
                order_number     = COALESCE(NULLIF(TRIM(p_payload->>'order_number'), ''), order_number),
                po_number        = CASE WHEN p_payload ? 'po_number' THEN v_po_number ELSE po_number END,
                order_date       = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                production_date  = v_production_date,
                production_code  = v_production_code,
                production_run_id = v_run_id,
                delivery_charge  = CASE WHEN p_payload ? 'delivery_amount' THEN v_delivery_charge ELSE delivery_charge END,
                customer_id      = v_order_customer_id,
                customer_name    = v_order_customer_name,
                department_event = CASE
                    WHEN p_payload ? 'department_event' THEN v_department_event
                    ELSE department_event
                END
            WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        ELSE
            UPDATE om_orders SET
                order_number     = COALESCE(NULLIF(TRIM(p_payload->>'order_number'), ''), order_number),
                order_date       = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                production_date  = v_production_date,
                production_code  = v_production_code,
                production_run_id = v_run_id,
                delivery_charge  = CASE WHEN p_payload ? 'delivery_amount' THEN v_delivery_charge ELSE delivery_charge END,
                customer_id      = v_order_customer_id,
                customer_name    = v_order_customer_name,
                department_event = CASE
                    WHEN p_payload ? 'department_event' THEN v_department_event
                    ELSE department_event
                END
            WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        END IF;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', v_order_id;
        END IF;
        v_mode := 'updated';
    END IF;

    -- ── LINES UPSERT ──────────────────────────────────────────────────────
    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload->'lines', '[]'::JSONB)) LOOP
        v_qty      := COALESCE((v_line->>'quantity')::NUMERIC,     0);
        v_price    := COALESCE((v_line->>'unit_price')::NUMERIC,   0);
        v_discount := COALESCE((v_line->>'unit_discount')::NUMERIC,0);
        v_extended := v_qty * (v_price - v_discount);
        v_line_id  := NULLIF((v_line->>'order_line_id')::TEXT, 'null')::BIGINT;

        IF v_line_id IS NULL THEN
            INSERT INTO om_order_lines (
                order_id, item_id, item_description,
                quantity, unit_price, unit_discount, extended_amount,
                prep_options, tenant_id
            ) VALUES (
                v_order_id,
                NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                COALESCE(TRIM(v_line->>'item_description'), ''),
                v_qty, v_price, v_discount, v_extended,
                COALESCE(v_line->'prep_options', '[]'::JSONB),
                p_tenant_id
            )
            RETURNING order_line_id INTO v_line_id;
        ELSE
            UPDATE om_order_lines SET
                item_id          = NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                item_description = COALESCE(TRIM(v_line->>'item_description'), ''),
                quantity         = v_qty,
                unit_price       = v_price,
                unit_discount    = v_discount,
                extended_amount  = v_extended,
                prep_options     = COALESCE(v_line->'prep_options', '[]'::JSONB)
            WHERE order_line_id = v_line_id
              AND order_id      = v_order_id
              AND tenant_id     = p_tenant_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Order line % not found for order % and tenant %', v_line_id, v_order_id, p_tenant_id;
            END IF;
        END IF;

        v_line_refs  := v_line_refs || jsonb_build_array(jsonb_build_object(
            'client_temp_id', NULLIF(TRIM(v_line->>'client_temp_id'), ''),
            'order_line_id',  v_line_id
        ));
        v_total_qty  := v_total_qty  + v_qty;
        v_total_amt  := v_total_amt  + v_extended;
        v_total_disc := v_total_disc + (v_qty * v_discount);
    END LOOP;

    -- Remove lines omitted from payload (full-state save contract)
    IF jsonb_array_length(COALESCE(p_payload->'lines', '[]'::JSONB)) = 0 THEN
        DELETE FROM om_order_lines WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        GET DIAGNOSTICS v_deleted_line_count = ROW_COUNT;
    ELSE
        DELETE FROM om_order_lines l
         WHERE l.order_id  = v_order_id
           AND l.tenant_id = p_tenant_id
           AND NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(v_line_refs) r
                 WHERE (r->>'order_line_id')::BIGINT = l.order_line_id
           );
        GET DIAGNOSTICS v_deleted_line_count = ROW_COUNT;
    END IF;

    -- Update header rollups
    UPDATE om_orders SET
        quantity        = v_total_qty,
        amount          = v_total_amt,
        discount_amount = v_total_disc
    WHERE order_id = v_order_id;

    IF v_order_number IS NULL THEN
        SELECT order_number INTO v_order_number FROM om_orders WHERE order_id = v_order_id;
    END IF;

    RETURN jsonb_build_object(
        'success',          TRUE,
        'order_id',         v_order_id,
        'order_number',     v_order_number,
        'po_number',        v_po_number,
        'department_event', v_department_event,
        'mode',             v_mode,
        'line_refs',        v_line_refs,
        'deleted_lines',    v_deleted_line_count,
        'message',          'Order saved.'
    );

EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'uq_om_orders_slot_department_event' THEN
        RAISE EXCEPTION 'An order already exists for this customer, production date, production code, and Department/Event.';
    END IF;
    RAISE EXCEPTION 'Order number % already exists for this tenant.', v_order_number;
END;
$function$;

-- ===== grants =====
GRANT EXECUTE ON FUNCTION bps.om_production_cutoff_calc(bigint, date, text) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_customer_cutoff_extra_minutes(bigint, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_run_get_or_create(bigint, date, text) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_cutoff_get(bigint, date, text, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_cutoff_assert(bigint, date, text, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_codes_get(bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_codes_save(bigint, jsonb) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_delivery_methods_get(bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_delivery_methods_save(bigint, jsonb) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_runs_get(bigint, date, date, boolean) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_run_cutoff_save(bigint, bigint, timestamp) TO authenticated, bps_dev, service_role;

-- ===== migration/seed_om_production_settings.sql =====
-- ============================================================
-- Seed production-code cutoffs and delivery methods for tenant "Alpine Bakery" (local data).
-- Cutoffs are defaults only (4:00 PM the day before, delivery the day after): adjust in Admin > Production Codes.
-- Idempotent. Prerequisites: om_production_codes.sql, om_delivery_methods.sql, PRODUCTIONCODE valueset seeded.
-- ============================================================
DO $$
DECLARE v_tenant_id BIGINT;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM bps.fnd_tenants WHERE tenant_name = 'Alpine Bakery' LIMIT 1;
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    INSERT INTO bps.om_production_codes (tenant_id, production_code, cutoff_time, cutoff_days_before, delivery_days_after)
    SELECT v_tenant_id, UPPER(v.value), TIME '16:00', 1, 1
      FROM bps.fnd_valuesets s JOIN bps.fnd_valueset_values v ON v.valueset_id = s.valueset_id
     WHERE s.tenant_id = v_tenant_id AND s.valueset_code = 'PRODUCTIONCODE'
    ON CONFLICT (tenant_id, production_code) DO NOTHING;

    INSERT INTO bps.om_delivery_methods (tenant_id, delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking)
    VALUES
        (v_tenant_id, 'OWN_TRUCK', 'Own truck',  TRUE,  FALSE),
        (v_tenant_id, 'CARRIER',   'Carrier (UPS, FedEx)', FALSE, TRUE),
        (v_tenant_id, 'COURIER',   'Courier (Uber)',       FALSE, FALSE),
        (v_tenant_id, 'PICKUP',    'Customer pickup',      FALSE, FALSE)
    ON CONFLICT (tenant_id, delivery_method_code) DO NOTHING;
END $$;

-- ===== backfill =====
-- Backfill: give existing orders their run (runs for past production dates are CLOSED).
INSERT INTO om_production_runs (tenant_id, production_date, production_code, delivery_date, cutoff_at, run_status)
SELECT DISTINCT o.tenant_id, o.production_date, o.production_code,
       o.production_date + pc.delivery_days_after,
       bps.om_production_cutoff_calc(o.tenant_id, o.production_date, o.production_code),
       CASE WHEN o.production_date < CURRENT_DATE THEN 'CLOSED' ELSE 'OPEN' END
  FROM om_orders o
  JOIN om_production_codes pc ON pc.tenant_id = o.tenant_id AND pc.production_code = o.production_code
 WHERE o.production_code IS NOT NULL AND o.production_run_id IS NULL
ON CONFLICT (tenant_id, production_date, production_code) DO NOTHING;

UPDATE om_orders o
   SET production_run_id = r.production_run_id
  FROM om_production_runs r
 WHERE r.tenant_id = o.tenant_id AND r.production_date = o.production_date AND r.production_code = o.production_code
   AND o.production_run_id IS NULL;
