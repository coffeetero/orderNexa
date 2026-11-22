-- ============================================================
-- om_production_codes_save
-- Upserts the cutoff settings for one production code.
-- p_payload: { production_code, cutoff_time 'HH:MI', cutoff_days_before, delivery_days_after, is_active }
-- Staff only (RLS); the code must exist in the tenant's PRODUCTIONCODE valueset.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_codes_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_payload ->> 'production_code')), '');
BEGIN
    IF p_tenant_id IS NULL OR v_code IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id and production_code are required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM fnd_valuesets s JOIN fnd_valueset_values v ON v.valueset_id = s.valueset_id
         WHERE s.tenant_id = p_tenant_id AND s.valueset_code = 'PRODUCTIONCODE' AND UPPER(v.value) = v_code
    ) THEN
        RAISE EXCEPTION 'Production code % is not in the PRODUCTIONCODE list', v_code;
    END IF;

    INSERT INTO om_production_codes (tenant_id, production_code, cutoff_time, cutoff_days_before, delivery_days_after, is_active)
    VALUES (
        p_tenant_id, v_code,
        (p_payload ->> 'cutoff_time')::time,
        COALESCE((p_payload ->> 'cutoff_days_before')::integer, 1),
        COALESCE((p_payload ->> 'delivery_days_after')::integer, 1),
        COALESCE((p_payload ->> 'is_active')::boolean, TRUE)
    )
    ON CONFLICT (tenant_id, production_code) DO UPDATE SET
        cutoff_time         = EXCLUDED.cutoff_time,
        cutoff_days_before  = EXCLUDED.cutoff_days_before,
        delivery_days_after = EXCLUDED.delivery_days_after,
        is_active           = EXCLUDED.is_active;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Not allowed to change production code settings';
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'production_code', v_code);
END;
$function$;
