-- ============================================================
-- inv_recipes_get
-- The recipe list for Inventory › Recipes: every recipe of the tenant (active and archived) with its base-batch dough
-- weight, hydration and type, ordered by name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipes_get(p_tenant_id bigint)
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
             'recipe_id', r.recipe_id, 'recipe_name', r.recipe_name, 'recipe_type', r.recipe_type, 'dough_code', r.dough_code,
             'is_active', r.is_active, 'version_no', r.version_no,
             'total_qty', c.calc -> 'totals' -> 'total_qty', 'display_unit', r.display_unit,
             'hydration_pct', c.calc -> 'totals' -> 'hydration_pct',
             'line_count', jsonb_array_length(c.calc -> 'lines'))
           ORDER BY lower(r.recipe_name))
      FROM inv_recipes r
      CROSS JOIN LATERAL (SELECT bps.inv_recipe_calc(p_tenant_id, bps.inv_recipe_json(p_tenant_id, r.recipe_id)) AS calc) c
     WHERE r.tenant_id = p_tenant_id), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipes_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_recipes_get(bigint) TO authenticated, service_role, bps_dev;
