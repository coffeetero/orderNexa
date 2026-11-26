-- ============================================================
-- inv_recipe_check
-- Internal: checks the caller may act on Inventory › Recipes and returns the recipe.
-- p_action: 'R' read, 'W' write, 'D' delete (inventory.recipes access). p_recipe_id NULL checks access only.
-- Called only from the SECURITY DEFINER inv_recipe* / inv_ingredient* functions; app users cannot execute it.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_check(p_tenant_id bigint, p_recipe_id bigint, p_action text)
RETURNS bps.inv_recipes
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v bps.inv_recipes;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.recipes', p_action) THEN
    RAISE EXCEPTION 'You do not have access to % recipes',
      CASE upper(p_action) WHEN 'R' THEN 'view' WHEN 'D' THEN 'delete' ELSE 'edit' END USING ERRCODE = '42501';
  END IF;
  IF p_recipe_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v FROM inv_recipes r WHERE r.tenant_id = p_tenant_id AND r.recipe_id = p_recipe_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recipe not found'; END IF;
  RETURN v;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_check(bigint, bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_check(bigint, bigint, text) TO service_role, bps_dev;
