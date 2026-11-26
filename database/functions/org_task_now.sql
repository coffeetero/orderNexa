-- ============================================================
-- org_task_now
-- The tenant's local date and time (fnd_tenants.time_zone, America/New_York when unset) for the Tasks date rules.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_task_now(p_tenant_id bigint)
RETURNS timestamp
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'America/New_York'))::timestamp
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_task_now(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_task_now(bigint) TO authenticated, service_role, bps_dev;
