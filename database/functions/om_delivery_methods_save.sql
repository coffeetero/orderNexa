-- ============================================================
-- om_delivery_methods_save
-- Upserts one delivery method. Methods are never deleted (customers reference them); set is_active = false.
-- p_payload: { delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking, is_active }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_delivery_methods_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_payload ->> 'delivery_method_code')), '');
    v_name text := NULLIF(TRIM(p_payload ->> 'delivery_method_name'), '');
BEGIN
    IF p_tenant_id IS NULL OR v_code IS NULL OR v_name IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id, delivery_method_code and delivery_method_name are required';
    END IF;

    INSERT INTO om_delivery_methods (tenant_id, delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking, is_active)
    VALUES (
        p_tenant_id, v_code, v_name,
        COALESCE((p_payload ->> 'is_own_fleet')::boolean, FALSE),
        COALESCE((p_payload ->> 'requires_tracking')::boolean, FALSE),
        COALESCE((p_payload ->> 'is_active')::boolean, TRUE)
    )
    ON CONFLICT (tenant_id, delivery_method_code) DO UPDATE SET
        delivery_method_name = EXCLUDED.delivery_method_name,
        is_own_fleet         = EXCLUDED.is_own_fleet,
        requires_tracking    = EXCLUDED.requires_tracking,
        is_active            = EXCLUDED.is_active;

    RETURN jsonb_build_object('success', TRUE, 'delivery_method_code', v_code);
END;
$function$;
