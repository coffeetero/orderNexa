-- ============================================================
-- inv_nutrition_label_build
-- Works out a Nutrition Facts label from a profile, without saving anything (used for the live preview, the stored profile and
-- printing). Rounding and % Daily Values follow 21 CFR 101.9 (see inv_nutrient_round / inv_nutrient_dv_pct).
-- p_payload: { serving_size_text, serving_size_g, servings_per_container, label_format STANDARD|TABULAR|LINEAR, is_dual_column,
--              nutrients: {<nutrient_code>: amount per serving, unrounded}, ingredient_statement,
--              allergens: {milk, egg, fish, shellfish, tree_nuts, peanuts, wheat, soy, sesame}, fish_species, shellfish_species,
--              tree_nut_types, may_contain_text }
-- Returns { label_format, is_dual_column, columns: ['Per serving', 'Per container'] (dual only), servings_text, serving_size_text,
--           calories: [..], nutrients: [{code, label, indent, amounts: [..], dv: [..]}], vitamins: [...same...], footnote,
--           ingredient_statement, contains_statement, may_contain_text, issues: [..] }
-- Mandatory nutrients left blank print as 0 and are listed in issues; an approved label must have no issues.
-- Optional nutrients appear only when a value is given. Per-container amounts = per-serving amount x servings, then rounded.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_nutrition_label_build(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  p        jsonb := COALESCE(p_payload, '{}'::jsonb);
  v_in     jsonb := COALESCE(p_payload -> 'nutrients', '{}'::jsonb);
  v_al     jsonb := COALESCE(p_payload -> 'allergens', '{}'::jsonb);
  v_format text  := COALESCE(NULLIF(upper(btrim(p ->> 'label_format')), ''), 'STANDARD');
  v_dual   boolean;
  v_srv    numeric;
  v_srv_g  numeric;
  v_srv_r  numeric;
  v_mult   numeric[];
  v_amt    jsonb := '{}'::jsonb;  -- code -> unrounded amount per serving (numbers only)
  v_issues text[] := ARRAY[]::text[];
  v_cal    jsonb := '[]'::jsonb;
  v_rows   jsonb := '[]'::jsonb;
  v_vits   jsonb := '[]'::jsonb;
  v_row    jsonb;
  v_amts   jsonb;
  v_dvs    jsonb;
  v_a      numeric;
  v_x      numeric;
  v_pct    integer;
  v_raw    text;
  v_parts  text[] := ARRAY[]::text[];
  v_srv_txt text;
  v_size_txt text;
  n        record;
  m        numeric;
  f        numeric;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.labels', 'R') THEN RAISE EXCEPTION 'You do not have access to nutrition labels'; END IF;
  IF jsonb_typeof(v_in) <> 'object' THEN RAISE EXCEPTION 'nutrients must be an object'; END IF;
  IF v_format NOT IN ('STANDARD', 'TABULAR', 'LINEAR') THEN RAISE EXCEPTION 'Label format must be Standard, Tabular or Linear'; END IF;

  -- numbers
  BEGIN
    v_srv   := NULLIF(btrim(p ->> 'servings_per_container'), '')::numeric;
    v_srv_g := NULLIF(btrim(p ->> 'serving_size_g'), '')::numeric;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Serving size and servings per container must be numbers';
  END;
  IF v_srv IS NOT NULL AND v_srv <= 0 OR v_srv_g IS NOT NULL AND v_srv_g <= 0 THEN
    RAISE EXCEPTION 'Serving size and servings per container must be more than zero';
  END IF;
  FOR n IN SELECT * FROM inv_nutrients WHERE is_active ORDER BY display_order LOOP
    v_raw := NULLIF(btrim(v_in ->> n.nutrient_code), '');
    IF v_raw IS NOT NULL THEN
      BEGIN v_a := v_raw::numeric;
      EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION '% must be a number', n.label_name;
      END;
      IF v_a < 0 THEN RAISE EXCEPTION '% cannot be negative', n.label_name; END IF;
      v_amt := v_amt || jsonb_build_object(n.nutrient_code, v_a);
    ELSIF n.is_mandatory THEN
      v_issues := v_issues || (n.label_name || ' is missing');
    END IF;
  END LOOP;

  v_dual := COALESCE((p ->> 'is_dual_column')::boolean, false);
  IF v_dual AND v_format <> 'STANDARD' THEN RAISE EXCEPTION 'A dual-column label uses the Standard format'; END IF;
  IF v_dual AND v_srv IS NULL THEN RAISE EXCEPTION 'A dual-column label needs servings per container'; END IF;
  v_mult := CASE WHEN v_dual THEN ARRAY[1, v_srv] ELSE ARRAY[1::numeric] END;

  -- servings per container: nearest whole, except 2-5 (and under 2) to the nearest 0.5; "About" when that is not exact (101.9(b)(8))
  IF v_srv IS NOT NULL THEN
    v_srv_r := CASE WHEN v_srv <= 5 THEN round(v_srv * 2) / 2 ELSE round(v_srv) END;
    IF v_srv_r = 0 THEN v_srv_r := 0.5; END IF;
    v_srv_txt := CASE WHEN v_srv_r <> v_srv THEN 'About ' ELSE '' END || trim_scale(v_srv_r)::text
                 || CASE WHEN v_srv_r = 1 THEN ' serving per container' ELSE ' servings per container' END;
  ELSE
    v_issues := v_issues || 'Servings per container is missing'::text;
  END IF;
  IF NULLIF(btrim(p ->> 'serving_size_text'), '') IS NULL OR v_srv_g IS NULL THEN
    v_issues := v_issues || 'Serving size (household measure and grams) is missing'::text;
  END IF;
  v_size_txt := btrim(concat_ws(' ', NULLIF(btrim(p ->> 'serving_size_text'), ''),
                      CASE WHEN v_srv_g IS NOT NULL THEN '(' || trim_scale(CASE WHEN v_srv_g < 2 THEN round(v_srv_g, 1) ELSE round(v_srv_g) END)::text || 'g)' END));

  -- rows
  FOR n IN SELECT * FROM inv_nutrients WHERE is_active ORDER BY display_order LOOP
    IF NOT (n.is_mandatory OR v_amt ? n.nutrient_code) THEN CONTINUE; END IF;
    v_a := COALESCE((v_amt ->> n.nutrient_code)::numeric, 0);
    v_amts := '[]'::jsonb; v_dvs := '[]'::jsonb;
    FOREACH m IN ARRAY v_mult LOOP
      v_x := v_a * m;
      v_pct := bps.inv_nutrient_dv_pct(n.rounding_rule, v_x, n.daily_value, n.is_vitamin_mineral);
      IF n.is_vitamin_mineral AND v_pct = 0 THEN
        v_amts := v_amts || to_jsonb('0' || n.unit);   -- under 2% DV may be declared as zero
      ELSE
        v_amts := v_amts || to_jsonb(bps.inv_nutrient_display(n.rounding_rule, v_x, n.unit));
      END IF;
      v_dvs := v_dvs || COALESCE(to_jsonb(v_pct), 'null'::jsonb);
    END LOOP;
    IF n.nutrient_code = 'calories' THEN v_cal := v_amts; CONTINUE; END IF;
    v_row := jsonb_build_object('code', n.nutrient_code, 'label', n.label_name, 'indent', n.indent_level, 'amounts', v_amts, 'dv', v_dvs);
    IF n.is_vitamin_mineral THEN v_vits := v_vits || v_row; ELSE v_rows := v_rows || v_row; END IF;
  END LOOP;

  -- consistency checks (unrounded amounts)
  f := 0.05;
  IF COALESCE((v_amt ->> 'saturated_fat')::numeric, 0) + COALESCE((v_amt ->> 'trans_fat')::numeric, 0)
     + COALESCE((v_amt ->> 'polyunsaturated_fat')::numeric, 0) + COALESCE((v_amt ->> 'monounsaturated_fat')::numeric, 0)
     > COALESCE((v_amt ->> 'total_fat')::numeric, 0) + f THEN
    v_issues := v_issues || 'Saturated, trans, poly- and monounsaturated fat add up to more than total fat'::text;
  END IF;
  IF COALESCE((v_amt ->> 'dietary_fiber')::numeric, 0) + COALESCE((v_amt ->> 'total_sugars')::numeric, 0)
     + COALESCE((v_amt ->> 'sugar_alcohol')::numeric, 0) > COALESCE((v_amt ->> 'total_carbohydrate')::numeric, 0) + f THEN
    v_issues := v_issues || 'Fiber, sugars and sugar alcohol add up to more than total carbohydrate'::text;
  END IF;
  IF COALESCE((v_amt ->> 'added_sugars')::numeric, 0) > COALESCE((v_amt ->> 'total_sugars')::numeric, 0) + f THEN
    v_issues := v_issues || 'Added sugars are more than total sugars'::text;
  END IF;
  IF COALESCE((v_amt ->> 'soluble_fiber')::numeric, 0) + COALESCE((v_amt ->> 'insoluble_fiber')::numeric, 0)
     > COALESCE((v_amt ->> 'dietary_fiber')::numeric, 0) + f THEN
    v_issues := v_issues || 'Soluble and insoluble fiber add up to more than dietary fiber'::text;
  END IF;

  -- allergens: "Contains" statement (FALCPA + FASTER Act); fish, shellfish and tree nuts must be named
  IF COALESCE((v_al ->> 'milk')::boolean, false)      THEN v_parts := v_parts || 'Milk'::text; END IF;
  IF COALESCE((v_al ->> 'egg')::boolean, false)       THEN v_parts := v_parts || 'Egg'::text; END IF;
  IF COALESCE((v_al ->> 'fish')::boolean, false) THEN
    v_parts := v_parts || ('Fish' || COALESCE(' (' || NULLIF(btrim(p ->> 'fish_species'), '') || ')', ''));
    IF NULLIF(btrim(p ->> 'fish_species'), '') IS NULL THEN v_issues := v_issues || 'Name the fish species'::text; END IF;
  END IF;
  IF COALESCE((v_al ->> 'shellfish')::boolean, false) THEN
    v_parts := v_parts || ('Shellfish' || COALESCE(' (' || NULLIF(btrim(p ->> 'shellfish_species'), '') || ')', ''));
    IF NULLIF(btrim(p ->> 'shellfish_species'), '') IS NULL THEN v_issues := v_issues || 'Name the crustacean shellfish species'::text; END IF;
  END IF;
  IF COALESCE((v_al ->> 'tree_nuts')::boolean, false) THEN
    v_parts := v_parts || ('Tree Nuts' || COALESCE(' (' || NULLIF(btrim(p ->> 'tree_nut_types'), '') || ')', ''));
    IF NULLIF(btrim(p ->> 'tree_nut_types'), '') IS NULL THEN v_issues := v_issues || 'Name the tree nut(s)'::text; END IF;
  END IF;
  IF COALESCE((v_al ->> 'peanuts')::boolean, false)   THEN v_parts := v_parts || 'Peanuts'::text; END IF;
  IF COALESCE((v_al ->> 'wheat')::boolean, false)     THEN v_parts := v_parts || 'Wheat'::text; END IF;
  IF COALESCE((v_al ->> 'soy')::boolean, false)       THEN v_parts := v_parts || 'Soy'::text; END IF;
  IF COALESCE((v_al ->> 'sesame')::boolean, false)    THEN v_parts := v_parts || 'Sesame'::text; END IF;
  IF NULLIF(btrim(p ->> 'ingredient_statement'), '') IS NULL THEN v_issues := v_issues || 'Ingredient statement is missing'::text; END IF;

  RETURN jsonb_build_object(
    'label_format', v_format,
    'is_dual_column', v_dual,
    'columns', CASE WHEN v_dual THEN '["Per serving", "Per container"]'::jsonb END,
    'servings_text', v_srv_txt,
    'serving_size_text', NULLIF(v_size_txt, ''),
    'calories', v_cal,
    'nutrients', v_rows,
    'vitamins', v_vits,
    'footnote', 'The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.',
    'ingredient_statement', NULLIF(btrim(p ->> 'ingredient_statement'), ''),
    'contains_statement', CASE WHEN cardinality(v_parts) > 0 THEN 'Contains: ' || array_to_string(v_parts, ', ') END,
    'may_contain_text', NULLIF(btrim(p ->> 'may_contain_text'), ''),
    'issues', to_jsonb(v_issues));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_nutrition_label_build(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_nutrition_label_build(bigint, jsonb) TO authenticated, service_role, bps_dev;
