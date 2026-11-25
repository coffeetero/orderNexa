-- ============================================================
-- fnd_todos_get (Dashboard To-Do list)
-- Items that need someone's attention, each with its own permission:
--   PRICEBOOK_NOT_IN_EFFECT  pricing books not in effect yet (customers.pricing or inventory.pricing approve)
--   INACTIVE_USER, NEW_LOCATION  security signals for user administrators (fnd_security_signals_get, admin.users write)
-- Supersedes the version in migration/add_pricing_books.sql. Load after migration/add_user_activity_signals.sql.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_todos_get(p_tenant_id bigint, p_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_today   date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
  v_pricing jsonb := '[]'::jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF bps.fnd_has_access_any(ARRAY['customers.pricing','inventory.pricing'], 'A') THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('kind', 'PRICEBOOK_NOT_IN_EFFECT', 'customer_id', cp.customer_id, 'customer_name', c.customer_name,
        'pricebook_id', cp.pricebook_id, 'pricebook_name', pb.pricebook_name, 'assignment_type', cp.assignment_type, 'status', cp.status, 'is_active', cp.is_active,
        'effective_start_date', cp.effective_start_date, 'effective_end_date', cp.effective_end_date, 'days_until_start', (cp.effective_start_date - v_today))
        ORDER BY cp.effective_start_date, c.customer_name), '[]'::jsonb)
      INTO v_pricing
      FROM bps.fnd_customer_pricebooks cp JOIN bps.fnd_customers c ON c.customer_id = cp.customer_id JOIN bps.fnd_pricebooks pb ON pb.pricebook_id = cp.pricebook_id
     WHERE cp.tenant_id = p_tenant_id AND cp.status <> 'Archived' AND NOT (cp.is_active AND cp.status = 'Approved')
       AND cp.effective_start_date <= v_today + p_days AND (cp.effective_end_date IS NULL OR cp.effective_end_date >= v_today);
  END IF;
  RETURN bps.fnd_security_signals_get(p_tenant_id) || v_pricing;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_todos_get(bigint, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_todos_get(bigint, integer) TO authenticated, service_role, bps_dev;
