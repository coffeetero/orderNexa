-- ============================================================
-- inv_ingredient_save
-- Creates or updates one ingredient of the recipe catalog. Returns the ingredient as inv_ingredients_get lists it.
-- p_ingredient: { ingredient_id (omit for new), ingredient_name, ingredient_role FLOUR|LIQUID|OTHER, cost_amount (blank = no
--   price), cost_unit kg|lb, allergens [codes: milk, egg, fish, shellfish, tree_nuts, peanuts, wheat, soy, sesame], notes, is_active }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_ingredient_save(p_tenant_id bigint, p_ingredient jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user  bigint := bps.fnd_current_user_id();
  v_id    bigint := NULLIF(p_ingredient ->> 'ingredient_id', '')::bigint;
  v_name  text := NULLIF(btrim(p_ingredient ->> 'ingredient_name'), '');
  v_role  text := upper(COALESCE(NULLIF(p_ingredient ->> 'ingredient_role', ''), 'OTHER'));
  v_cost  numeric := NULLIF(btrim(p_ingredient ->> 'cost_amount'), '')::numeric;
  v_cunit text := lower(COALESCE(NULLIF(p_ingredient ->> 'cost_unit', ''), 'lb'));
  v_alg   text[] := COALESCE((SELECT array_agg(DISTINCT lower(a)) FROM jsonb_array_elements_text(COALESCE(p_ingredient -> 'allergens', '[]'::jsonb)) a), '{}');
  v_notes text := NULLIF(btrim(p_ingredient ->> 'notes'), '');
  v_act   boolean := COALESCE((p_ingredient ->> 'is_active')::boolean, true);
BEGIN
  PERFORM bps.inv_recipe_check(p_tenant_id, NULL, 'W');
  IF v_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM inv_ingredients WHERE tenant_id = p_tenant_id AND ingredient_id = v_id) THEN
    RAISE EXCEPTION 'Ingredient not found';
  END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Give the ingredient a name'; END IF;
  IF length(v_name) > 100 THEN RAISE EXCEPTION 'The ingredient name is limited to 100 characters'; END IF;
  IF v_role NOT IN ('FLOUR', 'LIQUID', 'OTHER') THEN RAISE EXCEPTION 'Unknown ingredient role %', v_role; END IF;
  IF v_cost < 0 THEN RAISE EXCEPTION 'The price cannot be negative'; END IF;
  IF v_cunit NOT IN ('kg', 'lb') THEN RAISE EXCEPTION 'Price per kg or per lb'; END IF;
  IF NOT v_alg <@ ARRAY['milk', 'egg', 'fish', 'shellfish', 'tree_nuts', 'peanuts', 'wheat', 'soy', 'sesame'] THEN
    RAISE EXCEPTION 'Unknown allergen';
  END IF;
  IF length(v_notes) > 500 THEN RAISE EXCEPTION 'Notes are limited to 500 characters'; END IF;
  IF EXISTS (SELECT 1 FROM inv_ingredients WHERE tenant_id = p_tenant_id AND lower(ingredient_name) = lower(v_name) AND ingredient_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'There is already an ingredient called %', v_name;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO inv_ingredients (tenant_id, ingredient_name, ingredient_role, cost_amount, cost_unit, allergens, notes, is_active, created_by, updated_by)
    VALUES (p_tenant_id, v_name, v_role, v_cost, v_cunit, v_alg, v_notes, v_act, v_user, v_user)
    RETURNING ingredient_id INTO v_id;
  ELSE
    UPDATE inv_ingredients SET ingredient_name = v_name, ingredient_role = v_role, cost_amount = v_cost, cost_unit = v_cunit,
                               allergens = v_alg, notes = v_notes, is_active = v_act, updated_by = v_user
     WHERE ingredient_id = v_id;
  END IF;

  RETURN (SELECT x FROM jsonb_array_elements(bps.inv_ingredients_get(p_tenant_id)) x WHERE (x ->> 'ingredient_id')::bigint = v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_ingredient_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_ingredient_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
