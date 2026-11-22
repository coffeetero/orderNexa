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
               'cutoff_local',      to_char(r.cutoff_at AT TIME ZONE bps.fnd_tenant_time_zone(r.tenant_id), 'YYYY-MM-DD"T"HH24:MI'),
               'time_zone',         bps.fnd_tenant_time_zone(r.tenant_id),
               'run_status',        r.run_status,
               'order_count',       (SELECT COUNT(*) FROM om_orders o WHERE o.production_run_id = r.production_run_id)
           ) ORDER BY r.production_date DESC, r.production_code), '[]'::jsonb)
      FROM om_production_runs r
     WHERE r.tenant_id = p_tenant_id
       AND r.production_date BETWEEN COALESCE(p_from, DATE '0001-01-01') AND COALESCE(p_to, DATE '9999-12-31')
       AND (NOT p_upcoming_only OR r.production_date >= ((now() AT TIME ZONE bps.fnd_tenant_time_zone(r.tenant_id))::date - 1));
$function$;
