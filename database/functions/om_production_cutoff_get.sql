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
    v_tz := bps.fnd_tenant_time_zone(p_tenant_id);

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
