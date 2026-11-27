-- ============================================================
-- po_vendor_item_prices_get
-- Price history of one vendor item, newest first, with the change from the price before.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_vendor_item_prices_get(p_tenant_id bigint, p_vendor_item_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'R');
  IF NOT EXISTS (SELECT 1 FROM po_vendor_items WHERE tenant_id = p_tenant_id AND vendor_item_id = p_vendor_item_id) THEN
    RAISE EXCEPTION 'Vendor item not found';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'effective_date', to_char(x.effective_date, 'MM/DD/YYYY'), 'pack_price', x.pack_price, 'price_source', x.price_source,
             'change', x.pack_price - x.prev, 'change_pct', CASE WHEN x.prev > 0 THEN round((x.pack_price - x.prev) / x.prev * 100, 1) END,
             'saved_by_name', x.user_name)
           ORDER BY x.effective_date DESC, x.created_at DESC)
      FROM (SELECT p.*, u.user_name,
                   lag(p.pack_price) OVER (ORDER BY p.effective_date, p.created_at) AS prev
              FROM po_vendor_item_prices p LEFT JOIN fnd_users u ON u.user_id = p.created_by
             WHERE p.vendor_item_id = p_vendor_item_id) x), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_vendor_item_prices_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_vendor_item_prices_get(bigint, bigint) TO authenticated, service_role, bps_dev;
