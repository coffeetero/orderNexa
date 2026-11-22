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
       SET cutoff_at = p_cutoff_local AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id)
     WHERE r.tenant_id = p_tenant_id AND r.production_run_id = p_production_run_id AND r.run_status = 'OPEN';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Run % not found, not open, or you are not allowed to change it', p_production_run_id;
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'production_run_id', p_production_run_id);
END;
$function$;
