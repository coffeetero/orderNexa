-- ============================================================
-- inv_nutrition_labels_get
-- Labels to print for the given items (those that have a profile), ordered by item number:
-- [{ item_id, item_number, item_name, status, approved_at, label (inv_nutrition_label_build) }]. At most 500 items.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_nutrition_labels_get(p_tenant_id bigint, p_item_ids bigint[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.labels', 'R') THEN RAISE EXCEPTION 'You do not have access to nutrition labels'; END IF;
  IF cardinality(p_item_ids) > 500 THEN RAISE EXCEPTION 'Print at most 500 labels at a time'; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'item_id', i.item_id, 'item_number', COALESCE(i.item_number, ''), 'item_name', i.item_name,
             'status', n.status, 'approved_at', n.approved_at,
             'label', bps.inv_nutrition_label_build(p_tenant_id, bps.inv_item_nutrition_payload(p_tenant_id, i.item_id)))
           ORDER BY i.item_number NULLS LAST, i.item_name), '[]'::jsonb)
            FROM fnd_items i
            JOIN inv_item_nutrition n ON n.tenant_id = i.tenant_id AND n.item_id = i.item_id
           WHERE i.tenant_id = p_tenant_id AND i.item_id = ANY(p_item_ids));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_nutrition_labels_get(bigint, bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_nutrition_labels_get(bigint, bigint[]) TO authenticated, service_role, bps_dev;
