-- ============================================================
-- inv_item_nutrition_copy
-- Copies the profile of p_from_item_id onto p_to_item_id (replacing any profile it has) as a DRAFT.
-- The source note records where it was copied from. Returns inv_item_nutrition_get of the target item.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_item_nutrition_copy(p_tenant_id bigint, p_from_item_id bigint, p_to_item_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_src jsonb; v_from text;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF p_from_item_id IS NOT DISTINCT FROM p_to_item_id THEN RAISE EXCEPTION 'Pick a different item to copy from'; END IF;
  v_src := bps.inv_item_nutrition_payload(p_tenant_id, p_from_item_id);
  IF v_src IS NULL THEN RAISE EXCEPTION 'The item to copy from has no nutrition profile'; END IF;
  SELECT btrim(concat_ws(' ', item_number, item_name)) INTO v_from FROM fnd_items WHERE tenant_id = p_tenant_id AND item_id = p_from_item_id;
  RETURN bps.inv_item_nutrition_save(p_tenant_id, v_src || jsonb_build_object('item_id', p_to_item_id,
           'source_note', left(concat_ws(' · ', 'Copied from ' || v_from, v_src ->> 'source_note'), 500)));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_item_nutrition_copy(bigint, bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_item_nutrition_copy(bigint, bigint, bigint) TO authenticated, service_role, bps_dev;
