-- ============================================================
-- po_vendors_get
-- The vendor list for Purchasing › Vendors: every vendor of the tenant with its terms and how many items it sells us,
-- by name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_vendors_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'R');
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'vendor_id', v.vendor_id, 'vendor_code', v.vendor_code, 'vendor_name', v.vendor_name,
             'account_number', v.account_number, 'payment_terms', v.payment_terms, 'lead_time_days', v.lead_time_days,
             'delivery_days', to_jsonb(v.delivery_days), 'min_order_amount', v.min_order_amount, 'currency_code', v.currency_code,
             'website', v.website, 'notes', v.notes, 'is_active', v.is_active,
             'item_count', (SELECT count(*) FROM po_vendor_items i WHERE i.vendor_id = v.vendor_id AND i.is_active))
           ORDER BY lower(v.vendor_name))
      FROM po_vendors v WHERE v.tenant_id = p_tenant_id), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_vendors_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_vendors_get(bigint) TO authenticated, service_role, bps_dev;
