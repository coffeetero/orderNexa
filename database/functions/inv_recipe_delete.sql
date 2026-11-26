-- ============================================================
-- inv_recipe_delete
-- Deletes a recipe with its lines, steps and versions. Refused while another recipe uses it as a sub-recipe.
-- Returns { recipe_id, result: 'DELETED' }. To keep a recipe but hide it, save it with is_active = false (archive).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_delete(p_tenant_id bigint, p_recipe_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v      bps.inv_recipes := bps.inv_recipe_check(p_tenant_id, p_recipe_id, 'D');
  v_used text;
BEGIN
  SELECT string_agg(DISTINCT r.recipe_name, ', ') INTO v_used
    FROM inv_recipe_lines l JOIN inv_recipes r ON r.recipe_id = l.recipe_id WHERE l.sub_recipe_id = v.recipe_id;
  IF v_used IS NOT NULL THEN
    RAISE EXCEPTION '% is used in %. Take it out of those recipes first, or archive it.', v.recipe_name, v_used;
  END IF;
  DELETE FROM inv_recipes WHERE recipe_id = v.recipe_id;
  RETURN jsonb_build_object('recipe_id', v.recipe_id, 'result', 'DELETED');
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
