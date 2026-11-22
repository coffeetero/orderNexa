-- ============================================================
-- fnd_is_tenant_staff
-- True when the caller may act as staff in the tenant: the tenant is in allowed_tenant_ids and NOT in
-- restricted_tenant_ids. A connection without JWT claims (migrations, tests, admin) is trusted.
-- Used by functions that change production, shipping or billing data.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_is_tenant_staff(p_tenant_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT CASE
        WHEN NULLIF(current_setting('request.jwt.claims', true), '') IS NULL THEN TRUE
        ELSE
            p_tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
            AND NOT (p_tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    END;
$function$;
