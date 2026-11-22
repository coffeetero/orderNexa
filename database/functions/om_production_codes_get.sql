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
