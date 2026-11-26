-- ============================================================
-- inv_ingredient_delete
-- Deletes an ingredient from the recipe catalog. Refused while a recipe uses it (set it inactive instead).
-- Returns { ingredient_id, result: 'DELETED' }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_ingredient_delete(p_tenant_id bigint, p_ingredient_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_name text;
  v_used text;
BEGIN
  PERFORM bps.inv_recipe_check(p_tenant_id, NULL, 'D');
  SELECT ingredient_name INTO v_name FROM inv_ingredients WHERE tenant_id = p_tenant_id AND ingredient_id = p_ingredient_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ingredient not found'; END IF;
  SELECT string_agg(DISTINCT r.recipe_name, ', ') INTO v_used
    FROM inv_recipe_lines l JOIN inv_recipes r ON r.recipe_id = l.recipe_id WHERE l.ingredient_id = p_ingredient_id;
  IF v_used IS NOT NULL THEN
    RAISE EXCEPTION '% is used in %. Set it inactive instead.', v_name, v_used;
  END IF;
  DELETE FROM inv_ingredients WHERE ingredient_id = p_ingredient_id;
  RETURN jsonb_build_object('ingredient_id', p_ingredient_id, 'result', 'DELETED');
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_ingredient_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_ingredient_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
