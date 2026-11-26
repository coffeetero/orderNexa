-- ============================================================
-- SQL tests for Inventory › Recipes: ingredient catalog, recipe save with a pre-ferment sub-recipe, baker's %, overall
-- formula (total flour, hydration, pre-fermented flour), scaling by batches / dough / flour / pieces, units, cost with and
-- without prices, allergens, ingredient statement, water temperature, versions and conflicts, cycles, deletes, access.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/recipes_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator), items with dough_type CIAPATA.
-- Creates staff user "zz recipes none" (no role) inside the transaction.
-- Example: Ciabatta = final dough (bread flour 7 kg, water 4800 g, poolish 6003 g, olive oil 300 g, salt 220 g, yeast 50 g)
--          + Poolish (bread flour 3000 g, water 3000 g, yeast 3 g). Overall: flour 10,000 g, water 7,800 g, dough 18,373 g.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v text);
GRANT ALL ON _t, _v TO PUBLIC;

DO $$
DECLARE t bigint := 200000000002; u3 bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-0000000000d7', 'zz recipes none', 'TENANCY_USER') RETURNING user_id INTO u3;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t, u3);
  UPDATE inv_recipes SET dough_code = NULL WHERE tenant_id = t AND upper(dough_code) = 'CIAPATA';  -- free the code for the test (rolled back)
END $$;

CREATE TEMP TABLE _as (k text PRIMARY KEY, auth uuid);
GRANT ALL ON _as TO PUBLIC;
INSERT INTO _as VALUES ('one', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'), ('none', 'aaaaaaaa-0000-4000-8000-0000000000d7');

-- 1) staff administrator
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; d boolean; r jsonb; c jsonb; p jsonb; cia jsonb;
  flour bigint; water bigint; salt bigint; yeast bigint; oil bigint; pool bigint; ciab bigint;
  ln jsonb; v_cost numeric;
BEGIN
  -- ingredient catalog
  flour := (bps.inv_ingredient_save(t, '{"ingredient_name":"zz Bread flour","ingredient_role":"FLOUR","cost_amount":"0.42","cost_unit":"lb","allergens":["wheat"]}') ->> 'ingredient_id')::bigint;
  water := (bps.inv_ingredient_save(t, '{"ingredient_name":"zz Water","ingredient_role":"LIQUID","cost_amount":"0"}') ->> 'ingredient_id')::bigint;
  salt  := (bps.inv_ingredient_save(t, '{"ingredient_name":"zz Salt","cost_amount":"0.30","cost_unit":"lb"}') ->> 'ingredient_id')::bigint;
  yeast := (bps.inv_ingredient_save(t, '{"ingredient_name":"zz Instant yeast","cost_amount":"3.50","cost_unit":"lb"}') ->> 'ingredient_id')::bigint;
  oil   := (bps.inv_ingredient_save(t, '{"ingredient_name":"zz Olive oil"}') ->> 'ingredient_id')::bigint;
  INSERT INTO _t VALUES ('ingredients saved with role, price and allergens',
    (SELECT ingredient_role = 'FLOUR' AND cost_amount = 0.42 AND allergens = '{wheat}' FROM inv_ingredients WHERE ingredient_id = flour));
  BEGIN PERFORM bps.inv_ingredient_save(t, '{"ingredient_name":"ZZ BREAD FLOUR"}'); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'There is already%'; END;
  INSERT INTO _t VALUES ('ingredient names are unique (any case)', d);
  BEGIN PERFORM bps.inv_ingredient_save(t, '{"ingredient_name":"zz x","allergens":["gluten"]}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('unknown allergen refused', d);

  -- pre-ferment
  r := bps.inv_recipe_save(t, jsonb_build_object('recipe_name', 'zz Poolish', 'recipe_type', 'PREFERMENT',
         'lines', jsonb_build_array(jsonb_build_object('ingredient_id', flour, 'quantity', 3, 'unit', 'kg'),
                                    jsonb_build_object('ingredient_id', water, 'quantity', 3000, 'unit', 'g'),
                                    jsonb_build_object('ingredient_id', yeast, 'quantity', 3, 'unit', 'g'))));
  pool := (r -> 'recipe' ->> 'recipe_id')::bigint;
  INSERT INTO _t VALUES ('poolish: 100% hydration, total 6,003 g', (r -> 'calc' -> 'totals' ->> 'hydration_pct')::numeric = 100
    AND (r -> 'calc' -> 'totals' ->> 'total_g')::numeric = 6003);
  INSERT INTO _t VALUES ('new recipe is version 1 with a "Created" version row', (r -> 'recipe' ->> 'version_no')::int = 1
    AND r -> 'versions' -> 0 ->> 'change_note' = 'Created');

  -- final dough using the poolish
  r := bps.inv_recipe_save(t, jsonb_build_object('recipe_name', 'zz Ciabatta', 'recipe_type', 'DOUGH', 'dough_code', ' ciapata ',
         'loss_pct', 2, 'piece_weight', 170, 'piece_unit', 'g', 'ddt_f', 76, 'friction_f', 26,
         'lines', jsonb_build_array(jsonb_build_object('ingredient_id', flour, 'quantity', 7, 'unit', 'kg'),
                                    jsonb_build_object('ingredient_id', water, 'quantity', 4800),
                                    jsonb_build_object('sub_recipe_id', pool, 'quantity', 6003),
                                    jsonb_build_object('ingredient_id', oil, 'quantity', 300),
                                    jsonb_build_object('ingredient_id', salt, 'quantity', 220),
                                    jsonb_build_object('ingredient_id', yeast, 'quantity', 50)),
         'steps', jsonb_build_array(jsonb_build_object('step_type', 'mix', 'instruction', 'Mix 3 min low, 4 min second', 'duration_min', 7),
                                    jsonb_build_object('step_type', 'BAKE', 'instruction', 'Deck with steam', 'duration_min', 22, 'temperature_f', 460))));
  ciab := (r -> 'recipe' ->> 'recipe_id')::bigint;
  c := r -> 'calc';
  INSERT INTO _v VALUES ('ciab', ciab), ('pool', pool), ('flour', flour), ('oil', oil);
  INSERT INTO _t VALUES ('dough code stored trimmed upper case', r -> 'recipe' ->> 'dough_code' = 'CIAPATA');
  INSERT INTO _t VALUES ('total dough 18,373 g', (c -> 'totals' ->> 'total_g')::numeric = 18373);
  INSERT INTO _t VALUES ('total flour counts the poolish flour: 10,000 g', (c -> 'totals' ->> 'flour_g')::numeric = 10000);
  INSERT INTO _t VALUES ('hydration 78.0% (water incl. poolish)', (c -> 'totals' ->> 'hydration_pct')::numeric = 78.0);
  INSERT INTO _t VALUES ('pre-fermented flour 30.0%', (c -> 'totals' ->> 'prefermented_flour_pct')::numeric = 30.0);
  INSERT INTO _t VALUES ('baker''s %: flour line 70%, poolish 60.03%, total 183.73%',
    (c -> 'lines' -> 0 ->> 'bakers_pct')::numeric = 70 AND (c -> 'lines' -> 2 ->> 'bakers_pct')::numeric = 60.03
    AND (c -> 'totals' ->> 'total_pct')::numeric = 183.73);
  INSERT INTO _t VALUES ('kg line converted to grams', (c -> 'lines' -> 0 ->> 'grams')::numeric = 7000);
  INSERT INTO _t VALUES ('pieces per batch after 2% loss: 105', (c -> 'totals' ->> 'base_pieces')::numeric = 105);
  INSERT INTO _t VALUES ('olive oil has no price: cost incomplete, 1 missing', (c -> 'cost' ->> 'missing_count')::int = 1
    AND NOT (c -> 'cost' ->> 'complete')::boolean AND c -> 'lines' -> 3 -> 'cost' = 'null'::jsonb);
  INSERT INTO _t VALUES ('allergens roll up from the poolish and flour: Wheat', c -> 'allergens' = '[{"code":"wheat","label":"Wheat"}]'::jsonb);
  INSERT INTO _t VALUES ('ingredient statement in descending weight',
    c ->> 'ingredient_statement' = 'zz Bread flour, zz Water, zz Olive oil, zz Salt, zz Instant yeast.');
  INSERT INTO _t VALUES ('make first: the poolish scaled to 6,003 g with its lines',
    jsonb_array_length(c -> 'make_first') = 1 AND (c -> 'make_first' -> 0 ->> 'scaled_qty')::numeric = 6003
    AND (c -> 'make_first' -> 0 -> 'lines' -> 0 ->> 'scaled_qty')::numeric = 3000);
  INSERT INTO _t VALUES ('used by items with dough type CIAPATA', jsonb_array_length(r -> 'used_by_items') > 0);
  INSERT INTO _t VALUES ('steps saved, type upper-cased', (SELECT count(*) FROM inv_recipe_steps WHERE recipe_id = ciab) = 2
    AND r -> 'recipe' -> 'steps' -> 0 ->> 'step_type' = 'MIX' AND (c ->> 'total_minutes')::int = 29);

  -- price for the oil -> complete cost
  PERFORM bps.inv_ingredient_save(t, jsonb_build_object('ingredient_id', oil, 'ingredient_name', 'zz Olive oil', 'cost_amount', 4, 'cost_unit', 'lb'));
  c := bps.inv_recipe_preview(t, (bps.inv_recipe_get(t, ciab) -> 'recipe'), '{}');
  v_cost := (10000 * 0.42 + 220 * 0.30 + 53 * 3.5 + 300 * 4) / 453.59237;
  INSERT INTO _t VALUES ('batch cost = all ingredients incl. the poolish''s, by weight x price',
    abs((c -> 'cost' ->> 'batch')::numeric - v_cost) < 0.001 AND (c -> 'cost' ->> 'complete')::boolean);
  INSERT INTO _t VALUES ('cost per piece = batch / 105', abs((c -> 'cost' ->> 'per_piece')::numeric - v_cost / 105) < 0.001);

  -- scaling
  c := bps.inv_recipe_preview(t, (bps.inv_recipe_get(t, ciab) -> 'recipe'), '{"mode":"DOUGH","value":36.746,"unit":"kg","out_unit":"kg"}');
  INSERT INTO _t VALUES ('scale by dough weight: 36.746 kg = factor 2, flour line 14 kg',
    (c ->> 'factor')::numeric = 2 AND (c -> 'lines' -> 0 ->> 'scaled_qty')::numeric = 14 AND (c -> 'totals' ->> 'total_qty')::numeric = 36.746);
  c := bps.inv_recipe_preview(t, (bps.inv_recipe_get(t, ciab) -> 'recipe'), '{"mode":"FLOUR","value":5,"unit":"kg"}');
  INSERT INTO _t VALUES ('scale by flour weight: 5 kg = factor 0.5, salt 110 g',
    (c ->> 'factor')::numeric = 0.5 AND (c -> 'lines' -> 4 ->> 'scaled_qty')::numeric = 110);
  c := bps.inv_recipe_preview(t, (bps.inv_recipe_get(t, ciab) -> 'recipe'), '{"mode":"PIECES","value":210}');
  INSERT INTO _t VALUES ('scale by pieces: 210 x 170 g after 2% loss', abs((c ->> 'factor')::numeric - 210 * 170 / (18373 * 0.98)) < 0.0001
    AND (c -> 'totals' ->> 'pieces')::numeric BETWEEN 209 AND 210);
  c := bps.inv_recipe_preview(t, (bps.inv_recipe_get(t, ciab) -> 'recipe'), '{"mode":"BATCHES","value":1,"out_unit":"lb"}');
  INSERT INTO _t VALUES ('output in lb: 18,373 g = 40.506 lb', (c -> 'totals' ->> 'total_qty')::numeric = 40.506);
  c := bps.inv_recipe_preview(t, (bps.inv_recipe_get(t, ciab) -> 'recipe'), '{"room_f":72,"flour_f":70,"preferment_f":70}');
  INSERT INTO _t VALUES ('water temperature with a pre-ferment: 76x4 - 72 - 70 - 26 - 70 = 66 °F',
    (c -> 'water' ->> 'water_f')::numeric = 66 AND (c -> 'water' ->> 'multiplier')::int = 4);
  BEGIN PERFORM bps.inv_recipe_preview(t, (bps.inv_recipe_get(t, pool) -> 'recipe') || '{"piece_weight":null}', '{"mode":"PIECES","value":5}'); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Give the recipe a scaling weight%'; END;
  INSERT INTO _t VALUES ('scale by pieces needs a piece weight', d);
  BEGIN PERFORM bps.inv_recipe_preview(t, '{"lines":[{"ingredient_id":1,"quantity":5}]}', '{}'); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE '%ingredient not found'; END;
  INSERT INTO _t VALUES ('preview refuses an unknown ingredient', d);

  -- versions and conflicts
  cia := (bps.inv_recipe_get(t, ciab) -> 'recipe');
  r := bps.inv_recipe_save(t, jsonb_set(cia, '{lines,4,quantity}', '200'), 'Salt 2.2% -> 2.0%');
  INSERT INTO _t VALUES ('save adds a version with the change note', (r -> 'recipe' ->> 'version_no')::int = 2
    AND jsonb_array_length(r -> 'versions') = 2 AND r -> 'versions' -> 0 ->> 'change_note' = 'Salt 2.2% -> 2.0%'
    AND (SELECT snapshot -> 'lines' -> 4 ->> 'quantity' FROM inv_recipe_versions WHERE recipe_id = ciab AND version_no = 1)::numeric = 220);
  BEGIN PERFORM bps.inv_recipe_save(t, cia, NULL); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'This recipe was saved by someone else%'; END;
  INSERT INTO _t VALUES ('saving an old version is refused', d);

  -- validation
  BEGIN PERFORM bps.inv_recipe_save(t, (bps.inv_recipe_get(t, pool) -> 'recipe') || jsonb_build_object('lines',
    jsonb_build_array(jsonb_build_object('sub_recipe_id', ciab, 'quantity', 100)))); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'A recipe cannot use itself%'; END;
  INSERT INTO _t VALUES ('a cycle through a sub-recipe is refused', d);
  BEGIN PERFORM bps.inv_recipe_save(t, jsonb_build_object('recipe_name', 'zz Other', 'dough_code', 'CIAPATA',
    'lines', jsonb_build_array(jsonb_build_object('ingredient_id', flour, 'quantity', 1)))); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Another recipe already has dough code%'; END;
  INSERT INTO _t VALUES ('dough codes are unique', d);
  BEGIN PERFORM bps.inv_recipe_save(t, jsonb_build_object('recipe_name', 'zz Empty', 'lines', '[]'::jsonb)); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'Add at least one ingredient'; END;
  INSERT INTO _t VALUES ('a recipe needs at least one line', d);
  BEGIN PERFORM bps.inv_recipe_save(t, jsonb_build_object('recipe_name', 'zz Neg',
    'lines', jsonb_build_array(jsonb_build_object('ingredient_id', flour, 'quantity', -1)))); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Line 1: enter a quantity%'; END;
  INSERT INTO _t VALUES ('negative quantity refused', d);

  -- lists
  INSERT INTO _t VALUES ('list shows both recipes with hydration', (SELECT count(*) FROM jsonb_array_elements(bps.inv_recipes_get(t)) x
    WHERE x ->> 'recipe_name' IN ('zz Poolish', 'zz Ciabatta') AND x ->> 'hydration_pct' IS NOT NULL) = 2);
  INSERT INTO _t VALUES ('ingredient list counts recipes', (SELECT (x ->> 'recipe_count')::int FROM jsonb_array_elements(bps.inv_ingredients_get(t)) x
    WHERE (x ->> 'ingredient_id')::bigint = flour) = 2);
  INSERT INTO _t VALUES ('editor options include ingredients, recipes and items', (SELECT jsonb_array_length(o -> 'ingredients') >= 5
    AND jsonb_array_length(o -> 'recipes') >= 2 AND jsonb_array_length(o -> 'items') > 0 FROM (SELECT bps.inv_recipe_options(t) o) z));

  -- deletes
  BEGIN PERFORM bps.inv_recipe_delete(t, pool); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'zz Poolish is used in zz Ciabatta%'; END;
  INSERT INTO _t VALUES ('a sub-recipe in use cannot be deleted', d);
  BEGIN PERFORM bps.inv_ingredient_delete(t, flour); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE '%Set it inactive instead.'; END;
  INSERT INTO _t VALUES ('an ingredient in use cannot be deleted', d);
  INSERT INTO _t VALUES ('recipe delete returns DELETED', bps.inv_recipe_delete(t, ciab) ->> 'result' = 'DELETED');
  INSERT INTO _t VALUES ('a recipe deletes with its lines, steps and versions', NOT EXISTS (SELECT 1 FROM inv_recipes WHERE recipe_id = ciab)
    AND NOT EXISTS (SELECT 1 FROM inv_recipe_lines WHERE recipe_id = ciab) AND NOT EXISTS (SELECT 1 FROM inv_recipe_versions WHERE recipe_id = ciab));
  INSERT INTO _t VALUES ('then the poolish can be deleted', bps.inv_recipe_delete(t, pool) ->> 'result' = 'DELETED');
  INSERT INTO _t VALUES ('an unused ingredient can be deleted', bps.inv_ingredient_delete(t, oil) ->> 'result' = 'DELETED');
  BEGIN PERFORM bps.inv_recipe_calc(t, '{}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('app users cannot call the internal calculation', d);
END $$;

-- 2) a staff user without Recipes access
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'none' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; d boolean;
BEGIN
  BEGIN PERFORM bps.inv_recipes_get(t); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'You do not have access%'; END;
  INSERT INTO _t VALUES ('no Recipes access: cannot list', d);
  BEGIN PERFORM bps.inv_ingredient_save(t, '{"ingredient_name":"zz nope"}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('no Recipes access: cannot add an ingredient', d);
  INSERT INTO _t VALUES ('no Recipes access: rows hidden by row security', (SELECT count(*) FROM inv_ingredients) = 0);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % recipes tests failed', bad, total; END IF;
  RAISE NOTICE 'all % recipes tests passed', total;
END $$;
ROLLBACK;
