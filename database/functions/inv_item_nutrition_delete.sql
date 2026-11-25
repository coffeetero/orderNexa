-- ============================================================
-- inv_item_nutrition_delete
-- Deletes an item's nutrition profile and its amounts. Needs Delete on inventory.labels.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_item_nutrition_delete(p_tenant_id bigint, p_item_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.labels', 'D') THEN RAISE EXCEPTION 'You do not have access to delete nutrition labels'; END IF;
  DELETE FROM inv_item_nutrition WHERE tenant_id = p_tenant_id AND item_id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'This item has no nutrition profile'; END IF;
  RETURN jsonb_build_object('deleted', p_item_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_item_nutrition_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_item_nutrition_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
