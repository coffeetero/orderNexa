-- ============================================================
-- om_report_defaults_get
-- Defaults for the production pages: the next production date (tenant-local today + 1) as both from and to date,
-- and the production codes (value + label) in display order.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_defaults_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT jsonb_build_object(
        'from_date', ((now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date + 1),
        'to_date',   ((now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date + 1),
        'production_codes', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('value', UPPER(v.value), 'label', v.label) ORDER BY v.display_order, v.value)
              FROM fnd_valuesets s
              JOIN fnd_valueset_values v ON v.valueset_id = s.valueset_id
             WHERE s.tenant_id = p_tenant_id AND s.valueset_code = 'PRODUCTIONCODE'
        ), '[]'::jsonb)
    );
$function$;
