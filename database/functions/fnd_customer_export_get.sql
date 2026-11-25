-- ============================================================
-- fnd_customer_export_get
-- Customers > Export Customers: one row per customer (ACCOUNT, SITE, DEPARTMENT) in hierarchy order, each with its parent's
-- customer number, in the layout Import Customers reads back (keys: see fnd_customer_export_rows).
--   p_active_only  true = active customers only
--   p_account_id   an ACCOUNT: only that account and everything under it; NULL = all customers
-- Staff with read access to Export Customers; users limited to some customers export only those.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_customer_export_get(p_tenant_id bigint, p_active_only boolean DEFAULT true, p_account_id bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_ids   bigint[];
    v_all   boolean;
    v_scope bigint[];
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF NOT bps.fnd_has_access('customers.exports', 'R') THEN
        RAISE EXCEPTION 'You do not have access to Export Customers' USING ERRCODE = '42501';
    END IF;
    IF p_account_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = p_account_id
                                                   AND customer_type = 'ACCOUNT') THEN
        RAISE EXCEPTION 'Pick a customer account';
    END IF;
    v_all := bps.fnd_scope_is_all();
    IF NOT v_all THEN v_scope := COALESCE(bps.fnd_scope_customer_ids(), '{}'::bigint[]); END IF;

    WITH RECURSIVE sub AS (
        SELECT p_account_id AS customer_id, 0 AS depth WHERE p_account_id IS NOT NULL
        UNION ALL
        SELECT c.customer_id, s.depth + 1 FROM fnd_customers c JOIN sub s ON c.customer_parent_id = s.customer_id
         WHERE c.tenant_id = p_tenant_id AND s.depth < 20
    )
    SELECT array_agg(c.customer_id) INTO v_ids
      FROM fnd_customers c
     WHERE c.tenant_id = p_tenant_id
       AND (NOT COALESCE(p_active_only, true) OR c.is_active)
       AND (p_account_id IS NULL OR c.customer_id IN (SELECT customer_id FROM sub))
       AND (v_all OR c.customer_id = ANY (v_scope));

    RETURN COALESCE((SELECT jsonb_agg(r.data ORDER BY r.sort_key)
                       FROM bps.fnd_customer_export_rows(p_tenant_id, COALESCE(v_ids, '{}'::bigint[])) r), '[]'::jsonb);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_export_get(bigint, boolean, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_export_get(bigint, boolean, bigint) TO authenticated, service_role, bps_dev;
