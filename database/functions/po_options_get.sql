-- ============================================================
-- po_options_get
-- Pick lists for the Purchasing screens: vendors (code, name, active) and recipe ingredients (name, active), by name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_options_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'R');
  RETURN jsonb_build_object(
    'vendors', COALESCE((SELECT jsonb_agg(jsonb_build_object('vendor_id', vendor_id, 'vendor_code', vendor_code, 'vendor_name', vendor_name, 'is_active', is_active)
                                          ORDER BY lower(vendor_name)) FROM po_vendors WHERE tenant_id = p_tenant_id), '[]'::jsonb),
    'ingredients', COALESCE((SELECT jsonb_agg(jsonb_build_object('ingredient_id', ingredient_id, 'ingredient_name', ingredient_name, 'is_active', is_active)
                                              ORDER BY lower(ingredient_name)) FROM inv_ingredients WHERE tenant_id = p_tenant_id), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_options_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_options_get(bigint) TO authenticated, service_role, bps_dev;
