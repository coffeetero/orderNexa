-- ============================================================
-- inv_recipe_flat
-- Internal: a saved recipe broken down into its ingredients for ONE base batch, sub-recipes (pre-ferments, fillings)
-- expanded in proportion to how much of them the line uses, at any depth (10 levels at most; saves refuse cycles).
-- Returns one row per ingredient with its grams. Used for the overall formula, cost, allergens and ingredient statement.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_flat(p_tenant_id bigint, p_recipe_id bigint)
RETURNS TABLE (ingredient_id bigint, grams numeric)
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  WITH RECURSIVE totals AS (
    SELECT l.recipe_id, sum(bps.inv_unit_grams(l.quantity, l.unit)) AS total_g
      FROM inv_recipe_lines l WHERE l.tenant_id = p_tenant_id GROUP BY l.recipe_id
  ), t (ingredient_id, sub_recipe_id, grams, depth) AS (
    SELECT l.ingredient_id, l.sub_recipe_id, bps.inv_unit_grams(l.quantity, l.unit), 1
      FROM inv_recipe_lines l WHERE l.tenant_id = p_tenant_id AND l.recipe_id = p_recipe_id
    UNION ALL
    SELECT l.ingredient_id, l.sub_recipe_id, t.grams * bps.inv_unit_grams(l.quantity, l.unit) / tt.total_g, t.depth + 1
      FROM t
      JOIN totals tt ON tt.recipe_id = t.sub_recipe_id
      JOIN inv_recipe_lines l ON l.recipe_id = t.sub_recipe_id
     WHERE t.depth < 10
  )
  SELECT t.ingredient_id, sum(t.grams) FROM t WHERE t.ingredient_id IS NOT NULL GROUP BY t.ingredient_id;
$function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_flat(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_flat(bigint, bigint) TO service_role, bps_dev;
