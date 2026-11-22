-- ============================================================
-- om_customer_cutoff_extra_minutes
-- Extra minutes a customer may order after a run's cutoff: the nearest ancestor-or-self with a value, else 0.
-- SECURITY DEFINER so a restricted user still sees the value inherited from a parent they cannot read; it exposes
-- one integer for a customer the caller is already ordering for.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_cutoff_extra_minutes(
    p_tenant_id   bigint,
    p_customer_id bigint
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.cutoff_extra_minutes, 0 AS depth
          FROM fnd_customers c
         WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.cutoff_extra_minutes, up.depth + 1
          FROM fnd_customers c
          JOIN up ON c.customer_id = up.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND up.depth < 10
    )
    SELECT COALESCE((SELECT cutoff_extra_minutes FROM up WHERE cutoff_extra_minutes IS NOT NULL ORDER BY depth LIMIT 1), 0);
$function$;
