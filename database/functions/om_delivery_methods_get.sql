-- ============================================================
-- om_delivery_methods_get  –  the tenant's delivery methods (active and inactive), ordered by name
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_delivery_methods_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'delivery_method_code', m.delivery_method_code,
               'delivery_method_name', m.delivery_method_name,
               'is_own_fleet',         m.is_own_fleet,
               'requires_tracking',    m.requires_tracking,
               'is_active',            m.is_active
           ) ORDER BY m.delivery_method_name), '[]'::jsonb)
      FROM om_delivery_methods m
     WHERE m.tenant_id = p_tenant_id;
$function$;
