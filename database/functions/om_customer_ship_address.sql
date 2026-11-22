-- ============================================================
-- om_customer_ship_address
-- The customer's delivery address text: its active ADDRESS contact point, preferring the one marked use_as_shipping,
-- then primary. SECURITY DEFINER because app users have no direct access to the contact tables; tenant staff only.
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
    RETURN (SELECT cp.value
              FROM fnd_contacts ct
              JOIN fnd_contact_points cp ON cp.contact_id = ct.contact_id AND cp.tenant_id = ct.tenant_id
             WHERE ct.tenant_id = p_tenant_id AND ct.entity_id = p_customer_id AND ct.source_table = 'fnd_customers'
               AND cp.type = 'ADDRESS' AND cp.is_active
             ORDER BY cp.use_as_shipping DESC, cp.is_primary DESC, cp.sequence
             LIMIT 1);
END;
$function$;
