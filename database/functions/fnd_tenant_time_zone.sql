-- ============================================================
-- fnd_tenant_time_zone
-- The tenant's IANA time zone (fnd_tenants.time_zone). SECURITY DEFINER because fnd_tenants is not readable under the
-- app token's row level security; it returns only this one setting, and only to members of the tenant (tenant in
-- allowed_tenant_ids) or a trusted connection without JWT claims. NULL for anyone else.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_tenant_time_zone(p_tenant_id bigint)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT t.time_zone
      FROM fnd_tenants t
     WHERE t.tenant_id = p_tenant_id
       AND (
            NULLIF(current_setting('request.jwt.claims', true), '') IS NULL
            OR p_tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
       );
$function$;
