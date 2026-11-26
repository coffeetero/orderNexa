-- ============================================================
-- inv_recipe_calc
-- Internal: every figure Inventory › Recipes shows, for a recipe given as JSON (inv_recipe_json shape; saved or unsaved).
-- p_recipe: { recipe_id?, loss_pct, piece_weight, piece_unit, ddt_f, friction_f, display_unit,
--             lines [{ingredient_id | sub_recipe_id, quantity, unit, note}], steps [...] }
-- p_scale:  { mode BATCHES (default) | DOUGH | FLOUR | PIECES, value (default 1), unit (of value for DOUGH / FLOUR),
--             out_unit (g | kg | oz | lb; default the recipe's display_unit), room_f, flour_f, preferment_f }
-- Rules:
--   grams        quantity in its unit -> grams (inv_unit_grams).
--   total flour  FLOUR ingredients, counting the flour inside sub-recipes in proportion (BBGA overall formula).
--   baker's %    line grams / total flour x 100 (NULL when there is no flour). Total % = total dough / total flour.
--   hydration    LIQUID grams (incl. sub-recipes) / total flour x 100.
--   pre-fermented flour  flour inside PREFERMENT sub-recipes / total flour x 100.
--   factor       BATCHES: value; DOUGH: value / total dough; FLOUR: value / total flour;
--                PIECES: value x piece weight / (total dough x (1 - loss %)).
--   pieces       floor(total dough x factor x (1 - loss %) / piece weight).
--   cost         grams x price per gram (cost_amount / cost_unit); sub-recipe lines in proportion to their own cost.
--                Lines without a full price have cost NULL and are counted in cost.missing_count.
--   water temp   DDT x 3 - room - flour - friction; with a pre-ferment DDT x 4 - ... - pre-ferment temperature.
--   make_first   each sub-recipe scaled to what this batch needs (nested ones listed before the ones that use them).
-- Raises on unknown ingredients/recipes and impossible scaling. Not callable by app users (inv_recipe_preview / _get are).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_calc(p_tenant_id bigint, p_recipe jsonb, p_scale jsonb DEFAULT '{}'::jsonb, p_depth integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_self      bigint := NULLIF(p_recipe ->> 'recipe_id', '')::bigint;
  v_loss      numeric := COALESCE(NULLIF(p_recipe ->> 'loss_pct', '')::numeric, 0);
  v_piece_g   numeric := bps.inv_unit_grams(NULLIF(p_recipe ->> 'piece_weight', '')::numeric, COALESCE(NULLIF(p_recipe ->> 'piece_unit', ''), 'g'));
  v_ddt       numeric := NULLIF(p_recipe ->> 'ddt_f', '')::numeric;
  v_friction  numeric := NULLIF(p_recipe ->> 'friction_f', '')::numeric;
  v_mode      text := upper(COALESCE(NULLIF(p_scale ->> 'mode', ''), 'BATCHES'));
  v_value     numeric := COALESCE(NULLIF(p_scale ->> 'value', '')::numeric, 1);
  v_vunit     text := COALESCE(NULLIF(p_scale ->> 'unit', ''), 'g');
  v_out       text := lower(COALESCE(NULLIF(p_scale ->> 'out_unit', ''), NULLIF(p_recipe ->> 'display_unit', ''), 'g'));
  v_room      numeric := NULLIF(p_scale ->> 'room_f', '')::numeric;
  v_flour_t   numeric := NULLIF(p_scale ->> 'flour_f', '')::numeric;
  v_pf_t      numeric := NULLIF(p_scale ->> 'preferment_f', '')::numeric;
  v_unit_g    numeric;
  v_dec       int;
  v_e         jsonb;
  v_ord       bigint;
  v_ing       bps.inv_ingredients;
  v_sub       bps.inv_recipes;
  v_ing_id    bigint;
  v_sub_id    bigint;
  v_qty       numeric;
  v_unit      text;
  v_g         numeric;
  v_lflour    numeric;
  v_lliquid   numeric;
  v_lcost     numeric;
  v_lmissing  int;
  v_lalg      text[];
  s_total     numeric; s_flour numeric; s_liquid numeric; s_cost numeric; s_missing int; s_alg text[];
  v_raw       jsonb := '[]'::jsonb;
  v_total     numeric := 0;
  v_flour     numeric := 0;
  v_liquid    numeric := 0;
  v_pf_flour  numeric := 0;
  v_has_pf    boolean := false;
  v_cost      numeric := 0;
  v_missing   int := 0;
  v_alg       text[] := '{}';
  v_stmt      jsonb := '{}'::jsonb;
  v_factor    numeric;
  v_lines     jsonb := '[]'::jsonb;
  v_make      jsonb := '[]'::jsonb;
  v_issues    jsonb := '[]'::jsonb;
  v_after     numeric;
  v_pieces    numeric;
  v_water     numeric;
  v_mult      int;
  v_subs      record;
  v_sub_calc  jsonb;
  r           record;
BEGIN
  IF p_depth > 10 THEN RAISE EXCEPTION 'Sub-recipes are nested too deeply'; END IF;
  IF v_out NOT IN ('g', 'kg', 'oz', 'lb') THEN RAISE EXCEPTION 'Unknown unit %', v_out; END IF;
  v_unit_g := bps.inv_unit_grams(1, v_out);
  v_dec := CASE v_out WHEN 'g' THEN 1 WHEN 'oz' THEN 2 ELSE 3 END;

  -- Pass 1: each line's grams, flour, liquid, cost and allergens.
  FOR v_e, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_recipe -> 'lines', '[]'::jsonb)) WITH ORDINALITY LOOP
    v_ing_id := NULLIF(v_e ->> 'ingredient_id', '')::bigint;
    v_sub_id := NULLIF(v_e ->> 'sub_recipe_id', '')::bigint;
    v_qty := NULLIF(v_e ->> 'quantity', '')::numeric;
    v_unit := lower(COALESCE(NULLIF(v_e ->> 'unit', ''), 'g'));
    IF (v_ing_id IS NULL) = (v_sub_id IS NULL) THEN RAISE EXCEPTION 'Line %: pick an ingredient or a recipe', v_ord; END IF;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Line %: enter a quantity above 0', v_ord; END IF;
    IF v_unit NOT IN ('g', 'kg', 'oz', 'lb') THEN RAISE EXCEPTION 'Line %: unknown unit %', v_ord, v_unit; END IF;
    v_g := bps.inv_unit_grams(v_qty, v_unit);

    IF v_ing_id IS NOT NULL THEN
      SELECT * INTO v_ing FROM inv_ingredients i WHERE i.tenant_id = p_tenant_id AND i.ingredient_id = v_ing_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'Line %: ingredient not found', v_ord; END IF;
      v_lflour := CASE WHEN v_ing.ingredient_role = 'FLOUR' THEN v_g ELSE 0 END;
      v_lliquid := CASE WHEN v_ing.ingredient_role = 'LIQUID' THEN v_g ELSE 0 END;
      v_lcost := v_g * v_ing.cost_amount / bps.inv_unit_grams(1, v_ing.cost_unit);
      v_lmissing := CASE WHEN v_ing.cost_amount IS NULL THEN 1 ELSE 0 END;
      v_lalg := v_ing.allergens;
      v_stmt := jsonb_set(v_stmt, ARRAY[v_ing_id::text], to_jsonb(COALESCE((v_stmt ->> v_ing_id::text)::numeric, 0) + v_g));
      v_raw := v_raw || jsonb_build_object('line_no', v_ord, 'kind', 'INGREDIENT', 'ingredient_id', v_ing_id, 'sub_recipe_id', NULL,
                 'name', v_ing.ingredient_name, 'role', v_ing.ingredient_role, 'recipe_type', NULL,
                 'quantity', v_qty, 'unit', v_unit, 'note', NULLIF(btrim(v_e ->> 'note'), ''),
                 'grams', v_g, 'cost', v_lcost, 'allergens', to_jsonb(v_lalg));
    ELSE
      IF v_sub_id = v_self THEN RAISE EXCEPTION 'Line %: a recipe cannot use itself', v_ord; END IF;
      SELECT * INTO v_sub FROM inv_recipes r2 WHERE r2.tenant_id = p_tenant_id AND r2.recipe_id = v_sub_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'Line %: recipe not found', v_ord; END IF;
      SELECT sum(f.grams), COALESCE(sum(f.grams) FILTER (WHERE i.ingredient_role = 'FLOUR'), 0),
             COALESCE(sum(f.grams) FILTER (WHERE i.ingredient_role = 'LIQUID'), 0),
             COALESCE(sum(f.grams * i.cost_amount / bps.inv_unit_grams(1, i.cost_unit)), 0),
             count(*) FILTER (WHERE i.cost_amount IS NULL),
             COALESCE((SELECT array_agg(DISTINCT a) FROM inv_recipe_flat(p_tenant_id, v_sub_id) f2
                         JOIN inv_ingredients i2 ON i2.ingredient_id = f2.ingredient_id, unnest(i2.allergens) a), '{}')
        INTO s_total, s_flour, s_liquid, s_cost, s_missing, s_alg
        FROM inv_recipe_flat(p_tenant_id, v_sub_id) f JOIN inv_ingredients i ON i.ingredient_id = f.ingredient_id;
      IF COALESCE(s_total, 0) = 0 THEN RAISE EXCEPTION 'Line %: recipe % has no ingredients yet', v_ord, v_sub.recipe_name; END IF;
      v_lflour := v_g * s_flour / s_total;
      v_lliquid := v_g * s_liquid / s_total;
      v_lcost := CASE WHEN s_missing > 0 THEN NULL ELSE v_g * s_cost / s_total END;
      v_lmissing := s_missing;
      v_lalg := s_alg;
      IF v_sub.recipe_type = 'PREFERMENT' THEN v_pf_flour := v_pf_flour + v_lflour; v_has_pf := true; END IF;
      FOR r IN SELECT f.ingredient_id, f.grams FROM inv_recipe_flat(p_tenant_id, v_sub_id) f LOOP
        v_stmt := jsonb_set(v_stmt, ARRAY[r.ingredient_id::text],
                            to_jsonb(COALESCE((v_stmt ->> r.ingredient_id::text)::numeric, 0) + v_g * r.grams / s_total));
      END LOOP;
      v_raw := v_raw || jsonb_build_object('line_no', v_ord, 'kind', 'RECIPE', 'ingredient_id', NULL, 'sub_recipe_id', v_sub_id,
                 'name', v_sub.recipe_name, 'role', NULL, 'recipe_type', v_sub.recipe_type,
                 'quantity', v_qty, 'unit', v_unit, 'note', NULLIF(btrim(v_e ->> 'note'), ''),
                 'grams', v_g, 'cost', v_lcost, 'allergens', to_jsonb(v_lalg));
    END IF;
    v_total := v_total + v_g;
    v_flour := v_flour + v_lflour;
    v_liquid := v_liquid + v_lliquid;
    v_cost := v_cost + COALESCE(v_lcost, 0);
    v_missing := v_missing + v_lmissing;
    v_alg := v_alg || v_lalg;
  END LOOP;

  -- Scale factor.
  IF v_mode NOT IN ('BATCHES', 'DOUGH', 'FLOUR', 'PIECES') THEN RAISE EXCEPTION 'Unknown scaling %', v_mode; END IF;
  IF v_value <= 0 THEN RAISE EXCEPTION 'Enter an amount above 0 to scale by'; END IF;
  IF v_mode <> 'BATCHES' AND v_vunit NOT IN ('g', 'kg', 'oz', 'lb') THEN RAISE EXCEPTION 'Unknown unit %', v_vunit; END IF;
  IF v_total = 0 THEN
    v_factor := CASE WHEN v_mode = 'BATCHES' THEN v_value ELSE 1 END;
  ELSIF v_mode = 'BATCHES' THEN
    v_factor := v_value;
  ELSIF v_mode = 'DOUGH' THEN
    v_factor := bps.inv_unit_grams(v_value, v_vunit) / v_total;
  ELSIF v_mode = 'FLOUR' THEN
    IF v_flour = 0 THEN RAISE EXCEPTION 'This recipe has no flour to scale by'; END IF;
    v_factor := bps.inv_unit_grams(v_value, v_vunit) / v_flour;
  ELSE
    IF v_piece_g IS NULL THEN RAISE EXCEPTION 'Give the recipe a scaling weight per piece to scale by pieces'; END IF;
    v_factor := v_value * v_piece_g / (v_total * (1 - v_loss / 100));
  END IF;

  -- Pass 2: baker's %, scaled quantity and cost per line.
  SELECT COALESCE(jsonb_agg(x.j || jsonb_build_object(
           'grams', round((x.j ->> 'grams')::numeric, 2),
           'bakers_pct', CASE WHEN v_flour > 0 THEN round((x.j ->> 'grams')::numeric / v_flour * 100, 2) END,
           'scaled_qty', round((x.j ->> 'grams')::numeric * v_factor / v_unit_g, v_dec),
           'cost', round((x.j ->> 'cost')::numeric, 4),
           'scaled_cost', round((x.j ->> 'cost')::numeric * v_factor, 4)) ORDER BY (x.j ->> 'line_no')::int), '[]'::jsonb)
    INTO v_lines FROM jsonb_array_elements(v_raw) x(j);

  -- Sub-recipes to make first, scaled to what this batch needs.
  FOR v_subs IN
    SELECT (j ->> 'sub_recipe_id')::bigint AS sub_id, sum((j ->> 'grams')::numeric) AS g, min((j ->> 'line_no')::int) AS first_line
      FROM jsonb_array_elements(v_raw) j WHERE j ->> 'kind' = 'RECIPE' GROUP BY 1 ORDER BY 3
  LOOP
    v_sub_calc := bps.inv_recipe_calc(p_tenant_id, bps.inv_recipe_json(p_tenant_id, v_subs.sub_id),
                    jsonb_build_object('mode', 'DOUGH', 'value', v_subs.g * v_factor, 'unit', 'g', 'out_unit', v_out), p_depth + 1);
    v_make := v_make || COALESCE(v_sub_calc -> 'make_first', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'recipe_id', v_subs.sub_id,
      'recipe_name', (SELECT recipe_name FROM inv_recipes WHERE recipe_id = v_subs.sub_id),
      'recipe_type', (SELECT recipe_type FROM inv_recipes WHERE recipe_id = v_subs.sub_id),
      'scaled_qty', round(v_subs.g * v_factor / v_unit_g, v_dec),
      'hydration_pct', v_sub_calc -> 'totals' -> 'hydration_pct',
      'lines', v_sub_calc -> 'lines',
      'steps', COALESCE((SELECT jsonb_agg(s) FROM jsonb_array_elements(bps.inv_recipe_json(p_tenant_id, v_subs.sub_id) -> 'steps') s), '[]'::jsonb)));
  END LOOP;

  -- Yield, water temperature, issues.
  v_after := v_total * v_factor * (1 - v_loss / 100);
  v_pieces := CASE WHEN v_piece_g > 0 THEN floor(v_after / v_piece_g) END;
  v_mult := CASE WHEN v_has_pf THEN 4 ELSE 3 END;
  IF v_ddt IS NOT NULL AND v_friction IS NOT NULL AND v_room IS NOT NULL AND v_flour_t IS NOT NULL AND (NOT v_has_pf OR v_pf_t IS NOT NULL) THEN
    v_water := v_ddt * v_mult - v_room - v_flour_t - v_friction - CASE WHEN v_has_pf THEN v_pf_t ELSE 0 END;
  END IF;
  IF v_total > 0 AND v_flour = 0 THEN
    v_issues := v_issues || to_jsonb('No ingredient is marked as flour, so there are no baker''s percentages.'::text);
  END IF;
  IF v_missing > 0 THEN
    v_issues := v_issues || to_jsonb(format('%s ingredient%s no price, so the cost is incomplete.', v_missing, CASE WHEN v_missing = 1 THEN ' has' ELSE 's have' END)::text);
  END IF;

  RETURN jsonb_build_object(
    'mode', v_mode, 'factor', round(v_factor, 4), 'out_unit', v_out,
    'lines', v_lines,
    'totals', jsonb_build_object(
      'total_g', round(v_total, 2), 'total_qty', round(v_total * v_factor / v_unit_g, v_dec),
      'flour_g', round(v_flour, 2), 'flour_qty', round(v_flour * v_factor / v_unit_g, v_dec),
      'liquid_g', round(v_liquid, 2), 'liquid_qty', round(v_liquid * v_factor / v_unit_g, v_dec),
      'total_pct', CASE WHEN v_flour > 0 THEN round(v_total / v_flour * 100, 2) END,
      'hydration_pct', CASE WHEN v_flour > 0 THEN round(v_liquid / v_flour * 100, 1) END,
      'prefermented_flour_pct', CASE WHEN v_flour > 0 AND v_has_pf THEN round(v_pf_flour / v_flour * 100, 1) END,
      'loss_pct', v_loss,
      'after_loss_qty', round(v_after / v_unit_g, v_dec),
      'piece_weight_g', round(v_piece_g, 2), 'piece_weight_qty', round(v_piece_g / v_unit_g, v_dec + 1),
      'pieces', v_pieces,
      'base_pieces', CASE WHEN v_piece_g > 0 THEN floor(v_total * (1 - v_loss / 100) / v_piece_g) END),
    'cost', jsonb_build_object(
      'batch', round(v_cost * v_factor, 4),
      'base_batch', round(v_cost, 4),
      'per_kg', CASE WHEN v_total > 0 THEN round(v_cost / v_total * 1000, 4) END,
      'per_lb', CASE WHEN v_total > 0 THEN round(v_cost / v_total * 453.59237, 4) END,
      'per_piece', CASE WHEN v_pieces > 0 THEN round(v_cost * v_factor / v_pieces, 4) END,
      'missing_count', v_missing, 'complete', v_missing = 0),
    'allergens', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', a.code, 'label', a.label) ORDER BY a.ord)
                             FROM (VALUES ('milk', 'Milk', 1), ('egg', 'Egg', 2), ('fish', 'Fish', 3), ('shellfish', 'Crustacean shellfish', 4),
                                          ('tree_nuts', 'Tree nuts', 5), ('peanuts', 'Peanuts', 6), ('wheat', 'Wheat', 7), ('soy', 'Soy', 8),
                                          ('sesame', 'Sesame', 9)) a(code, label, ord)
                            WHERE a.code = ANY (v_alg)), '[]'::jsonb),
    'ingredient_statement', (SELECT string_agg(i.ingredient_name, ', ' ORDER BY s.value::numeric DESC, lower(i.ingredient_name)) || '.'
                               FROM jsonb_each_text(v_stmt) s JOIN inv_ingredients i ON i.ingredient_id = s.key::bigint),
    'water', jsonb_build_object('ddt_f', v_ddt, 'friction_f', v_friction, 'multiplier', v_mult, 'has_preferment', v_has_pf,
                                'room_f', v_room, 'flour_f', v_flour_t, 'preferment_f', v_pf_t, 'water_f', round(v_water, 0)),
    'make_first', v_make,
    'steps', COALESCE(p_recipe -> 'steps', '[]'::jsonb),
    'total_minutes', (SELECT sum(NULLIF(s ->> 'duration_min', '')::int) FROM jsonb_array_elements(COALESCE(p_recipe -> 'steps', '[]'::jsonb)) s),
    'issues', v_issues);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_calc(bigint, jsonb, jsonb, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_calc(bigint, jsonb, jsonb, integer) TO service_role, bps_dev;
