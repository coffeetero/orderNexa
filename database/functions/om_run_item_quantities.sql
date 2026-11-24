-- ============================================================
-- om_run_item_quantities
-- The items to produce for a production run, with compound items expanded: a simple item's order line is returned as ordered
-- (from_compound = false); a compound item's line is replaced by its components, quantity ordered x component quantity
-- (from_compound = true). One level, since compound items hold only simple items. Shared by the production reports.
-- A compound item with no components returns nothing.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_run_item_quantities(p_tenant_id bigint, p_run_id bigint)
RETURNS TABLE (order_id bigint, item_id bigint, item_description text, quantity numeric, from_compound boolean)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $$
    SELECT ol.order_id, ol.item_id, ol.item_description, ol.quantity, false
      FROM om_order_lines ol
      JOIN om_orders o ON o.order_id = ol.order_id AND o.tenant_id = ol.tenant_id
      LEFT JOIN fnd_items i ON i.item_id = ol.item_id
     WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_run_id AND ol.quantity <> 0 AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED' AND COALESCE(i.is_compound, false) = false
    UNION ALL
    SELECT ol.order_id, b.item_id, NULL::text, ol.quantity * b.quantity, true
      FROM om_order_lines ol
      JOIN om_orders o ON o.order_id = ol.order_id AND o.tenant_id = ol.tenant_id
      JOIN fnd_items p ON p.item_id = ol.item_id AND p.is_compound
      JOIN fnd_item_bom b ON b.parent_item_id = p.item_id AND b.tenant_id = p.tenant_id
     WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_run_id AND ol.quantity <> 0 AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED'
$$;

REVOKE EXECUTE ON FUNCTION bps.om_run_item_quantities(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_run_item_quantities(bigint, bigint) TO authenticated, service_role, bps_dev;
