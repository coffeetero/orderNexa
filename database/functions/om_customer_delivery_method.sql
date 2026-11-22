-- ============================================================
-- om_customer_delivery_method
-- Delivery method for a customer: its own delivery_method_code, else the nearest ancestor's (active methods only),
-- else the tenant's first active own-fleet method by code, else NULL.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_delivery_method(p_tenant_id bigint, p_customer_id bigint)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.delivery_method_code, 0 AS depth
          FROM fnd_customers c
         WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.delivery_method_code, up.depth + 1
          FROM fnd_customers c
          JOIN up ON c.customer_id = up.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND up.depth < 10
    )
    SELECT COALESCE(
        (SELECT up.delivery_method_code FROM up
           JOIN om_delivery_methods m ON m.tenant_id = p_tenant_id AND m.delivery_method_code = up.delivery_method_code AND m.is_active
          WHERE up.delivery_method_code IS NOT NULL
          ORDER BY up.depth LIMIT 1),
        (SELECT m.delivery_method_code FROM om_delivery_methods m
          WHERE m.tenant_id = p_tenant_id AND m.is_own_fleet AND m.is_active
          ORDER BY m.delivery_method_code LIMIT 1)
    );
$function$;
