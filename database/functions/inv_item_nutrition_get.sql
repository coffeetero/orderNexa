-- ============================================================
-- inv_item_nutrition_get
-- One item for the Nutrition Labels editor: { item, profile (NULL when none yet), label (inv_nutrition_label_build of the
-- profile), nutrients (reference list for the form), can_write, can_approve, can_delete }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_item_nutrition_get(p_tenant_id bigint, p_item_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_item jsonb; v_prof jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.labels', 'R') THEN RAISE EXCEPTION 'You do not have access to nutrition labels'; END IF;
  SELECT jsonb_build_object('item_id', i.item_id, 'item_number', COALESCE(i.item_number, ''), 'item_name', i.item_name,
                            'category', i.category, 'item_weight', i.item_weight, 'weight_uom', i.weight_uom, 'is_active', i.is_active)
    INTO v_item FROM fnd_items i WHERE i.tenant_id = p_tenant_id AND i.item_id = p_item_id;
  IF v_item IS NULL THEN RAISE EXCEPTION 'Item not found'; END IF;
  v_prof := bps.inv_item_nutrition_payload(p_tenant_id, p_item_id);
  RETURN jsonb_build_object(
    'item', v_item,
    'profile', v_prof,
    'label', CASE WHEN v_prof IS NOT NULL THEN bps.inv_nutrition_label_build(p_tenant_id, v_prof) END,
    'nutrients', (SELECT jsonb_agg(jsonb_build_object('code', nutrient_code, 'label', label_name, 'unit', unit,
                                     'daily_value', daily_value, 'is_mandatory', is_mandatory, 'indent', indent_level) ORDER BY display_order)
                    FROM inv_nutrients WHERE is_active),
    'can_write', bps.fnd_has_access('inventory.labels', 'W'),
    'can_approve', bps.fnd_has_access('inventory.labels', 'A'),
    'can_delete', bps.fnd_has_access('inventory.labels', 'D'));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_item_nutrition_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_item_nutrition_get(bigint, bigint) TO authenticated, service_role, bps_dev;
