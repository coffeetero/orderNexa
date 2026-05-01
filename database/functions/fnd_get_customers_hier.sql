-- Hierarchy list for a tenant; delegates to fnd_get_customer_hier.
CREATE OR REPLACE FUNCTION public.fnd_get_customers_hier(tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
  SELECT public.fnd_get_customer_hier(tenant_id);
$$;
