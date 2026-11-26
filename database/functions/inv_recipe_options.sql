-- ============================================================
-- inv_recipe_options
-- What the Inventory › Recipes editor picks from: { ingredients [id, name, role, active], recipes [id, name, type, active],
--   items [active items: id, number, name] }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_options(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.inv_recipe_check(p_tenant_id, NULL, 'R');
  RETURN jsonb_build_object(
    'ingredients', COALESCE((SELECT jsonb_agg(jsonb_build_object('ingredient_id', i.ingredient_id, 'ingredient_name', i.ingredient_name,
                                  'ingredient_role', i.ingredient_role, 'is_active', i.is_active) ORDER BY lower(i.ingredient_name))
                               FROM inv_ingredients i WHERE i.tenant_id = p_tenant_id), '[]'::jsonb),
    'recipes', COALESCE((SELECT jsonb_agg(jsonb_build_object('recipe_id', r.recipe_id, 'recipe_name', r.recipe_name,
                              'recipe_type', r.recipe_type, 'is_active', r.is_active) ORDER BY lower(r.recipe_name))
                           FROM inv_recipes r WHERE r.tenant_id = p_tenant_id), '[]'::jsonb),
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('item_id', i.item_id, 'item_number', i.item_number, 'item_name', i.item_name)
                                ORDER BY i.item_number)
                         FROM fnd_items i WHERE i.tenant_id = p_tenant_id AND i.is_active), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_options(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_options(bigint) TO authenticated, service_role, bps_dev;
