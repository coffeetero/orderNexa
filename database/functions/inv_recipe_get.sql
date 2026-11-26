-- ============================================================
-- inv_recipe_get
-- One recipe for Inventory › Recipes: { recipe (inv_recipe_json), calc (inv_recipe_calc, scaled by p_scale),
--   item (finished item), saved_on (date in the tenant's time zone), saved_by_name,
--   versions [{version_no, change_note, saved_on, saved_by_name}], used_by_items [items whose dough_type = the dough code],
--   used_in [recipes that use this one], can_write, can_delete }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_get(p_tenant_id bigint, p_recipe_id bigint, p_scale jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v    bps.inv_recipes := bps.inv_recipe_check(p_tenant_id, p_recipe_id, 'R');
  v_j  jsonb := bps.inv_recipe_json(p_tenant_id, p_recipe_id);
  v_tz text := COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC');
BEGIN
  RETURN jsonb_build_object(
    'recipe', v_j,
    'calc', bps.inv_recipe_calc(p_tenant_id, v_j, COALESCE(p_scale, '{}'::jsonb)),
    'item', (SELECT jsonb_build_object('item_id', i.item_id, 'item_number', i.item_number, 'item_name', i.item_name)
               FROM fnd_items i WHERE i.item_id = v.item_id),
    'saved_on', to_char(v.updated_at AT TIME ZONE v_tz, 'MM/DD/YYYY'),
    'saved_by_name', (SELECT u.user_name FROM fnd_users u WHERE u.user_id = v.updated_by),
    'versions', COALESCE((SELECT jsonb_agg(jsonb_build_object('version_no', rv.version_no, 'change_note', rv.change_note,
                                    'saved_on', to_char(rv.saved_at AT TIME ZONE v_tz, 'MM/DD/YYYY'),
                                    'saved_by_name', u.user_name) ORDER BY rv.version_no DESC)
                            FROM inv_recipe_versions rv LEFT JOIN fnd_users u ON u.user_id = rv.saved_by
                           WHERE rv.recipe_id = v.recipe_id), '[]'::jsonb),
    'used_by_items', COALESCE((SELECT jsonb_agg(jsonb_build_object('item_id', i.item_id, 'item_number', i.item_number,
                                    'item_name', i.item_name, 'unit_of_sale', i.unit_of_sale, 'is_active', i.is_active)
                                    ORDER BY NOT i.is_active, i.item_number)
                                 FROM fnd_items i
                                WHERE v.dough_code IS NOT NULL AND i.tenant_id = p_tenant_id
                                  AND upper(btrim(i.dough_type)) = upper(v.dough_code)), '[]'::jsonb),
    'used_in', COALESCE((SELECT jsonb_agg(DISTINCT jsonb_build_object('recipe_id', r.recipe_id, 'recipe_name', r.recipe_name))
                           FROM inv_recipe_lines l JOIN inv_recipes r ON r.recipe_id = l.recipe_id
                          WHERE l.sub_recipe_id = v.recipe_id), '[]'::jsonb),
    'can_write', bps.fnd_has_access('inventory.recipes', 'W'),
    'can_delete', bps.fnd_has_access('inventory.recipes', 'D'));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_get(bigint, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_get(bigint, bigint, jsonb) TO authenticated, service_role, bps_dev;
