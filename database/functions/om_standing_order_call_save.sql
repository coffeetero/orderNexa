-- ============================================================
-- om_standing_order_call_save
-- Manage Standing Orders: saves Call and Assigned to for a standing order customer + production time on each of the
-- given days of the week (the same days the standing order is saved to). Staff only.
-- Returns the setting of the first day (as om_standing_order_call_get).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_standing_order_call_save(
    p_tenant_id        bigint,
    p_customer_id      bigint,
    p_production_dows  text[],
    p_production_code  text,
    p_is_call          boolean,
    p_assigned_user_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_dow text;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can change call settings';
    END IF;
    IF COALESCE(array_length(p_production_dows, 1), 0) = 0 OR NULLIF(TRIM(p_production_code), '') IS NULL THEN
        RAISE EXCEPTION 'Days and production time are required';
    END IF;
    IF p_assigned_user_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM fnd_users u WHERE u.user_id = p_assigned_user_id AND u.tenant_id = p_tenant_id AND u.user_type = 'TENANCY_USER') THEN
        RAISE EXCEPTION 'Calls can only be assigned to staff of this company';
    END IF;
    FOREACH v_dow IN ARRAY p_production_dows LOOP
        INSERT INTO om_standing_order_calls (tenant_id, customer_id, production_dow, production_code, is_call, assigned_user_id, created_by, updated_by)
        VALUES (p_tenant_id, p_customer_id, UPPER(v_dow), p_production_code, COALESCE(p_is_call, false), p_assigned_user_id,
                bps.fnd_nav_app_user_id(), bps.fnd_nav_app_user_id())
        ON CONFLICT (tenant_id, customer_id, production_dow, production_code) DO UPDATE
           SET is_call = EXCLUDED.is_call, assigned_user_id = EXCLUDED.assigned_user_id, updated_by = EXCLUDED.updated_by;
    END LOOP;
    RETURN bps.om_standing_order_call_get(p_tenant_id, p_customer_id, p_production_dows[1], p_production_code);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_standing_order_call_save(bigint, bigint, text[], text, boolean, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_standing_order_call_save(bigint, bigint, text[], text, boolean, bigint) TO authenticated, service_role, bps_dev;
