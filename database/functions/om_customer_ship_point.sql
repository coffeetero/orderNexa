-- ============================================================
-- om_customer_ship_point
-- Where a customer (or, with p_source 'fnd_tenants', the company itself) is on a map: the same ADDRESS contact point
-- om_customer_ship_address picks (the customer's Ship to, fnd_customer_address_pick), with its coordinates once geocoded.
-- Returns { contact_point_id, address, latitude, longitude, geocode_status } or NULL when there is no address.
-- SECURITY DEFINER because app users have no direct access to the contact tables; tenant staff only.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_ship_point(p_tenant_id bigint, p_entity_id bigint, p_source text DEFAULT 'fnd_customers')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RETURN NULL;
    END IF;
    RETURN (SELECT jsonb_build_object('contact_point_id', cp.contact_point_id, 'address', cp.value,
                                      'latitude', cp.latitude, 'longitude', cp.longitude, 'geocode_status', cp.geocode_status)
              FROM fnd_contacts ct
              JOIN fnd_contact_points cp ON cp.contact_id = ct.contact_id AND cp.tenant_id = ct.tenant_id
             WHERE ct.tenant_id = p_tenant_id AND ct.source_table = p_source
               AND cp.type = 'ADDRESS' AND cp.is_active
               AND (CASE WHEN p_source = 'fnd_customers'
                         THEN cp.contact_point_id = bps.fnd_customer_address_pick(p_tenant_id, p_entity_id, 'SHIP')
                         ELSE ct.entity_id = p_entity_id END)
             ORDER BY cp.use_as_shipping DESC, cp.is_primary DESC, cp.sequence
             LIMIT 1);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_customer_ship_point(bigint, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_customer_ship_point(bigint, bigint, text) TO authenticated, service_role, bps_dev;
