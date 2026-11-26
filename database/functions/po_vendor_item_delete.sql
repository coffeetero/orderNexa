-- ============================================================
-- po_vendor_item_delete
-- Deletes a vendor item and its price history. (Once purchase orders exist, an item on an order is set inactive instead.)
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_vendor_item_delete(p_tenant_id bigint, p_vendor_item_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'D');
  DELETE FROM po_vendor_items WHERE tenant_id = p_tenant_id AND vendor_item_id = p_vendor_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vendor item not found'; END IF;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_vendor_item_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_vendor_item_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
