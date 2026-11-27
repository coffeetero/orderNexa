-- ============================================================
-- om_route_check / om_route_slot_check
-- Internal helpers for the SECURITY DEFINER Routes Maintenance functions; app users cannot execute them.
--   om_route_check(tenant, action)        : the caller may act on routes (delivery.routes R / W / D); returns the user id.
--   om_route_slot_check(tenant, dow, code): checks a day of week (MON..SUN) and an existing production code; returns the code.
--   om_route_row_check(tenant, route_id)  : the route of this tenant, or 'Route not found'.
--   om_route_ship_to_check(tenant, customer_id): an account or site of this tenant (departments go with their parent).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_check(p_tenant_id bigint, p_action text)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('delivery.routes', p_action) THEN
    RAISE EXCEPTION 'You do not have access to % routes',
      CASE upper(p_action) WHEN 'R' THEN 'view' WHEN 'D' THEN 'delete' ELSE 'change' END USING ERRCODE = '42501';
  END IF;
  RETURN bps.fnd_current_user_id();
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_check(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.om_route_check(bigint, text) TO service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.om_route_slot_check(p_tenant_id bigint, p_dow text, p_code text)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_code text := upper(btrim(p_code));
BEGIN
  IF upper(btrim(COALESCE(p_dow, ''))) NOT IN ('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN') THEN
    RAISE EXCEPTION 'Day of week must be MON, TUE, WED, THU, FRI, SAT or SUN';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM om_production_codes WHERE tenant_id = p_tenant_id AND production_code = v_code) THEN
    RAISE EXCEPTION 'Unknown production time %', COALESCE(p_code, '(none)');
  END IF;
  RETURN v_code;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_slot_check(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.om_route_slot_check(bigint, text, text) TO service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.om_route_row_check(p_tenant_id bigint, p_route_id bigint)
RETURNS bps.om_routes
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v bps.om_routes;
BEGIN
  SELECT * INTO v FROM om_routes WHERE tenant_id = p_tenant_id AND route_id = p_route_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Route not found'; END IF;
  RETURN v;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_row_check(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.om_route_row_check(bigint, bigint) TO service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.om_route_ship_to_check(p_tenant_id bigint, p_customer_id bigint)
RETURNS bps.fnd_customers
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v bps.fnd_customers;
BEGIN
  SELECT * INTO v FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
  IF upper(btrim(v.customer_type)) = 'DEPARTMENT' THEN
    RAISE EXCEPTION '% is a department: its orders are delivered with its site or account, so add that instead', v.customer_name;
  END IF;
  IF upper(btrim(v.customer_type)) NOT IN ('ACCOUNT', 'SITE') THEN
    RAISE EXCEPTION '% cannot be a route stop', v.customer_name;
  END IF;
  RETURN v;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_ship_to_check(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.om_route_ship_to_check(bigint, bigint) TO service_role, bps_dev;
