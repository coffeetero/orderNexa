-- ============================================================
-- om_production_cutoff_assert
-- Raises when a customer-restricted caller (tenant in the restricted_tenant_ids claim) tries to enter or change an
-- order for a run that is past its effective cutoff. Tenant staff are never blocked.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_cutoff_assert(
    p_tenant_id       bigint,
    p_production_date date,
    p_production_code text,
    p_customer_id     bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_restricted boolean;
    v_info       jsonb;
BEGIN
    SELECT p_tenant_id::text = ANY (ARRAY(
        SELECT jsonb_array_elements_text(
            NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids')))
      INTO v_restricted;
    IF NOT COALESCE(v_restricted, FALSE) THEN
        RETURN;
    END IF;

    v_info := bps.om_production_cutoff_get(p_tenant_id, p_production_date, p_production_code, p_customer_id);
    IF (v_info ->> 'is_open')::boolean THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'Ordering for % (%) closed %. Please call the bakery to add or change this order.',
        p_production_date, UPPER(TRIM(p_production_code)),
        COALESCE(to_char((v_info ->> 'effective_cutoff_at')::timestamptz AT TIME ZONE (v_info ->> 'time_zone'),
                         'Dy Mon DD "at" HH12:MI AM'), 'already');
END;
$function$;
