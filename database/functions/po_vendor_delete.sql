-- ============================================================
-- po_vendor_delete
-- Deletes a vendor that has no items (with its contacts). A vendor with items is set inactive instead.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_vendor_delete(p_tenant_id bigint, p_vendor_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_n integer;
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'D');
  IF NOT EXISTS (SELECT 1 FROM po_vendors WHERE tenant_id = p_tenant_id AND vendor_id = p_vendor_id) THEN
    RAISE EXCEPTION 'Vendor not found';
  END IF;
  SELECT count(*) INTO v_n FROM po_vendor_items WHERE vendor_id = p_vendor_id;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'This vendor has % item(s); set it inactive instead, or delete its items first', v_n;
  END IF;
  DELETE FROM fnd_contacts WHERE tenant_id = p_tenant_id AND source_table = 'po_vendors' AND entity_id = p_vendor_id;
  DELETE FROM po_vendors WHERE vendor_id = p_vendor_id;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_vendor_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_vendor_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
