-- ============================================================
-- om_customer_ship_address
-- The customer's delivery address text: its Ship to address (fnd_customer_address_pick; a department without addresses
-- uses its account's). SECURITY DEFINER because app users have no direct access to the contact tables; tenant staff only.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_ship_address(p_tenant_id bigint, p_customer_id bigint)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RETURN NULL;
    END IF;
    RETURN (SELECT cp.value FROM fnd_contact_points cp
             WHERE cp.contact_point_id = bps.fnd_customer_address_pick(p_tenant_id, p_customer_id, 'SHIP'));
END;
$function$;
