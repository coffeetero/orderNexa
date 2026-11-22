-- ============================================================
-- fnd_tenant_sequences_save
-- Upserts one numbering sequence (order_number, invoice_number, shipment_number or credit_memo_number). Staff only.
-- p_payload: { sequence_name, mask, start_value, next_value, increment_by, reset_period, requires_gapless }
-- next_value is only applied when it is not lower than the current next_value (numbers are never reused).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_tenant_sequences_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_name text := p_payload ->> 'sequence_name';
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can change numbering';
    END IF;
    IF v_name IS NULL OR v_name NOT IN ('order_number', 'invoice_number', 'shipment_number', 'credit_memo_number') THEN
        RAISE EXCEPTION 'Unknown sequence %', v_name;
    END IF;
    IF NULLIF(TRIM(p_payload ->> 'mask'), '') IS NULL OR POSITION('#' IN p_payload ->> 'mask') = 0 THEN
        RAISE EXCEPTION 'The mask must contain at least one # (digit placeholder)';
    END IF;

    INSERT INTO fnd_tenant_sequences (tenant_id, sequence_name, start_value, next_value, increment_by, mask, reset_period, requires_gapless)
    VALUES (p_tenant_id, v_name,
            COALESCE((p_payload ->> 'start_value')::bigint, 1000),
            COALESCE((p_payload ->> 'next_value')::bigint, (p_payload ->> 'start_value')::bigint, 1000),
            COALESCE((p_payload ->> 'increment_by')::bigint, 1),
            TRIM(p_payload ->> 'mask'),
            COALESCE(p_payload ->> 'reset_period', 'NEVER'),
            COALESCE((p_payload ->> 'requires_gapless')::boolean, FALSE))
    ON CONFLICT (tenant_id, sequence_name) DO UPDATE SET
        start_value      = EXCLUDED.start_value,
        next_value       = GREATEST(fnd_tenant_sequences.next_value, EXCLUDED.next_value),
        increment_by     = EXCLUDED.increment_by,
        mask             = EXCLUDED.mask,
        reset_period     = EXCLUDED.reset_period,
        requires_gapless = EXCLUDED.requires_gapless;

    RETURN jsonb_build_object('success', TRUE, 'sequence_name', v_name);
END;
$function$;
