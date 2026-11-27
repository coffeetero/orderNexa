-- ============================================================
-- om_standing_order_call_get
-- Manage Standing Orders: the call setting of one standing order customer + day of the week + production time, and the
-- staff users a call can be assigned to. Staff only.
-- Returns { is_call, assigned_user_id, users: [{ user_id, user_name }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_standing_order_call_get(p_tenant_id bigint, p_customer_id bigint, p_production_dow text, p_production_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can see call settings';
    END IF;
    RETURN jsonb_build_object(
        'is_call', COALESCE((SELECT c.is_call FROM om_standing_order_calls c
                              WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
                                AND c.production_dow = UPPER(p_production_dow) AND c.production_code = p_production_code), false),
        'assigned_user_id', (SELECT c.assigned_user_id FROM om_standing_order_calls c
                              WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
                                AND c.production_dow = UPPER(p_production_dow) AND c.production_code = p_production_code),
        'users', COALESCE((SELECT jsonb_agg(jsonb_build_object('user_id', u.user_id, 'user_name', u.user_name) ORDER BY u.user_name)
                             FROM fnd_users u
                            WHERE u.tenant_id = p_tenant_id AND u.user_type = 'TENANCY_USER' AND u.is_active AND u.deleted_at IS NULL), '[]'::jsonb));
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_standing_order_call_get(bigint, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_standing_order_call_get(bigint, bigint, text, text) TO authenticated, service_role, bps_dev;
