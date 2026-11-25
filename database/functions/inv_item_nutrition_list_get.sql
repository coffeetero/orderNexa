-- ============================================================
-- inv_item_nutrition_list_get
-- Items for the Nutrition Labels list: active items plus inactive ones that have a profile, with label status
-- (NONE / DRAFT / APPROVED), ordered by item number.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_item_nutrition_list_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.labels', 'R') THEN RAISE EXCEPTION 'You do not have access to nutrition labels'; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'item_id', i.item_id, 'item_number', COALESCE(i.item_number, ''), 'item_name', i.item_name, 'category', i.category,
             'is_active', i.is_active, 'status', COALESCE(n.status, 'NONE'), 'updated_at', n.updated_at, 'approved_at', n.approved_at)
           ORDER BY i.item_number NULLS LAST, i.item_name), '[]'::jsonb)
            FROM fnd_items i
            LEFT JOIN inv_item_nutrition n ON n.tenant_id = i.tenant_id AND n.item_id = i.item_id
           WHERE i.tenant_id = p_tenant_id AND (i.is_active OR n.item_nutrition_id IS NOT NULL));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_item_nutrition_list_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_item_nutrition_list_get(bigint) TO authenticated, service_role, bps_dev;
