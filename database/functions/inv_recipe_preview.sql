-- ============================================================
-- inv_recipe_preview
-- Inventory › Recipes: the computed figures (inv_recipe_calc) for a recipe as JSON, saved or still being edited,
-- scaled as p_scale asks. The screen calls it while editing (live baker's %) and when the scale bar changes.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_preview(p_tenant_id bigint, p_recipe jsonb, p_scale jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.inv_recipe_check(p_tenant_id, NULL, 'R');
  RETURN bps.inv_recipe_calc(p_tenant_id, COALESCE(p_recipe, '{}'::jsonb), COALESCE(p_scale, '{}'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_preview(bigint, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_preview(bigint, jsonb, jsonb) TO authenticated, service_role, bps_dev;
