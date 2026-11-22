-- ============================================================
-- om_production_runs_process
-- Processes every non-closed run whose production date is in [p_from, p_to] (and matches p_production_code when given).
-- Returns an array of om_production_run_process results. Raises when no run matches.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_runs_process(p_tenant_id bigint, p_from date, p_to date, p_production_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_run     record;
    v_results jsonb := '[]'::jsonb;
    v_code    text := NULLIF(UPPER(TRIM(p_production_code)), '');
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can process runs';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;
    FOR v_run IN
        SELECT production_run_id FROM om_production_runs
         WHERE tenant_id = p_tenant_id AND production_date BETWEEN p_from AND p_to
           AND run_status <> 'CLOSED' AND (v_code IS NULL OR production_code = v_code)
         ORDER BY production_date, production_code
    LOOP
        v_results := v_results || jsonb_build_array(bps.om_production_run_process(p_tenant_id, v_run.production_run_id));
    END LOOP;
    IF jsonb_array_length(v_results) = 0 THEN
        RAISE EXCEPTION 'No open production runs between % and %', p_from, p_to;
    END IF;
    RETURN v_results;
END;
$function$;
