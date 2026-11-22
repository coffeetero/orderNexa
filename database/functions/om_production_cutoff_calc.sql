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
