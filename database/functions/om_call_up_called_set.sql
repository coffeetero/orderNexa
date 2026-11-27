-- ============================================================
-- om_call_up_called_set
-- Call Up List: the clerk ticks (p_called true) or unticks Called for a customer on a date. Staff only.
-- Returns { customer_id, call_date, called_at, called_by } (called_at null when unticked).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_call_up_called_set(p_tenant_id bigint, p_customer_id bigint, p_date date, p_called boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_row om_call_up_called%ROWTYPE;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can tick calls';
    END IF;
    IF p_customer_id IS NULL OR p_date IS NULL THEN
        RAISE EXCEPTION 'Customer and date are required';
    END IF;
    IF COALESCE(p_called, false) THEN
        INSERT INTO om_call_up_called (tenant_id, customer_id, call_date, called_by)
        VALUES (p_tenant_id, p_customer_id, p_date, bps.fnd_nav_app_user_id())
        ON CONFLICT (tenant_id, customer_id, call_date) DO UPDATE SET called_at = now(), called_by = EXCLUDED.called_by
        RETURNING * INTO v_row;
    ELSE
        DELETE FROM om_call_up_called WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id AND call_date = p_date;
    END IF;
    RETURN jsonb_build_object('customer_id', p_customer_id, 'call_date', p_date, 'called_at', v_row.called_at,
                              'called_by', (SELECT user_name FROM fnd_users WHERE user_id = v_row.called_by));
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_call_up_called_set(bigint, bigint, date, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_call_up_called_set(bigint, bigint, date, boolean) TO authenticated, service_role, bps_dev;
