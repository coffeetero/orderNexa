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
