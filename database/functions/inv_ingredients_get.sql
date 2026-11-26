-- ============================================================
-- inv_ingredients_get
-- The ingredient catalog for Inventory › Recipes: every ingredient of the tenant with its role, price, allergens and
-- how many recipes use it, by name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_ingredients_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.inv_recipe_check(p_tenant_id, NULL, 'R');
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'ingredient_id', i.ingredient_id, 'ingredient_name', i.ingredient_name, 'ingredient_role', i.ingredient_role,
             'cost_amount', i.cost_amount, 'cost_unit', i.cost_unit, 'allergens', to_jsonb(i.allergens), 'notes', i.notes,
             'is_active', i.is_active,
             'recipe_count', (SELECT count(DISTINCT l.recipe_id) FROM inv_recipe_lines l WHERE l.ingredient_id = i.ingredient_id))
           ORDER BY lower(i.ingredient_name))
      FROM inv_ingredients i WHERE i.tenant_id = p_tenant_id), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_ingredients_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_ingredients_get(bigint) TO authenticated, service_role, bps_dev;
