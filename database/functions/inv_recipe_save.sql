-- ============================================================
-- inv_recipe_save
-- Creates or updates a recipe from Inventory › Recipes and returns it (inv_recipe_get, unscaled).
-- p_recipe (inv_recipe_json shape): { recipe_id (omit for new), version_no (the version being edited; required on update),
--   recipe_name, recipe_type DOUGH|PREFERMENT|OTHER, dough_code, item_id, piece_weight, piece_unit, loss_pct, ddt_f,
--   friction_f, display_unit, notes, is_active, lines [{ingredient_id | sub_recipe_id, quantity, unit, note}],
--   steps [{step_type, instruction, duration_min, temperature_f}] }
-- Lines and steps are replaced as given. A save that would make a recipe use itself (directly or through sub-recipes)
-- is refused. Every save adds one to version_no and stores a snapshot with p_change_note in inv_recipe_versions.
-- If someone else saved the recipe since it was opened (version_no differs) the save is refused.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_save(p_tenant_id bigint, p_recipe jsonb, p_change_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user    bigint := bps.fnd_current_user_id();
  v_id      bigint := NULLIF(p_recipe ->> 'recipe_id', '')::bigint;
  v_cur     bps.inv_recipes;
  v_name    text := NULLIF(btrim(p_recipe ->> 'recipe_name'), '');
  v_type    text := upper(COALESCE(NULLIF(p_recipe ->> 'recipe_type', ''), 'DOUGH'));
  v_code    text := upper(NULLIF(btrim(p_recipe ->> 'dough_code'), ''));
  v_item    bigint := NULLIF(p_recipe ->> 'item_id', '')::bigint;
  v_piece   numeric := NULLIF(p_recipe ->> 'piece_weight', '')::numeric;
  v_punit   text := lower(COALESCE(NULLIF(p_recipe ->> 'piece_unit', ''), 'g'));
  v_loss    numeric := COALESCE(NULLIF(p_recipe ->> 'loss_pct', '')::numeric, 0);
  v_ddt     numeric := NULLIF(p_recipe ->> 'ddt_f', '')::numeric;
  v_fric    numeric := NULLIF(p_recipe ->> 'friction_f', '')::numeric;
  v_dunit   text := lower(COALESCE(NULLIF(p_recipe ->> 'display_unit', ''), 'g'));
  v_notes   text := NULLIF(btrim(p_recipe ->> 'notes'), '');
  v_active  boolean := COALESCE((p_recipe ->> 'is_active')::boolean, true);
  v_note    text := NULLIF(btrim(p_change_note), '');
  v_lines   jsonb := COALESCE(p_recipe -> 'lines', '[]'::jsonb);
  v_steps   jsonb := COALESCE(p_recipe -> 'steps', '[]'::jsonb);
  v_version int;
  v_e       jsonb;
  v_ord     bigint;
  v_cycle   text;
BEGIN
  PERFORM bps.inv_recipe_check(p_tenant_id, NULL, 'W');
  IF v_id IS NOT NULL THEN
    v_cur := bps.inv_recipe_check(p_tenant_id, v_id, 'W');
    IF NULLIF(p_recipe ->> 'version_no', '')::int IS DISTINCT FROM v_cur.version_no THEN
      RAISE EXCEPTION 'This recipe was saved by someone else (now version %). Reload it and make your change again.', v_cur.version_no;
    END IF;
  END IF;

  -- Fields
  IF v_name IS NULL THEN RAISE EXCEPTION 'Give the recipe a name'; END IF;
  IF length(v_name) > 100 THEN RAISE EXCEPTION 'The recipe name is limited to 100 characters'; END IF;
  IF v_type NOT IN ('DOUGH', 'PREFERMENT', 'OTHER') THEN RAISE EXCEPTION 'Unknown recipe type %', v_type; END IF;
  IF length(v_code) > 30 THEN RAISE EXCEPTION 'The dough code is limited to 30 characters'; END IF;
  IF v_item IS NOT NULL AND NOT EXISTS (SELECT 1 FROM fnd_items WHERE tenant_id = p_tenant_id AND item_id = v_item) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;
  IF v_piece IS NOT NULL AND v_piece <= 0 THEN RAISE EXCEPTION 'The weight per piece must be above 0'; END IF;
  IF v_punit NOT IN ('g', 'kg', 'oz', 'lb') OR v_dunit NOT IN ('g', 'kg', 'oz', 'lb') THEN RAISE EXCEPTION 'Units are g, kg, oz or lb'; END IF;
  IF v_loss < 0 OR v_loss >= 50 THEN RAISE EXCEPTION 'Dough loss must be between 0 and 50%%'; END IF;
  IF v_ddt IS NOT NULL AND (v_ddt < 40 OR v_ddt > 110) THEN RAISE EXCEPTION 'Desired dough temperature must be between 40 and 110 °F'; END IF;
  IF v_fric IS NOT NULL AND (v_fric < 0 OR v_fric > 60) THEN RAISE EXCEPTION 'Friction factor must be between 0 and 60 °F'; END IF;
  IF length(v_notes) > 4000 THEN RAISE EXCEPTION 'Notes are limited to 4,000 characters'; END IF;
  IF length(v_note) > 500 THEN RAISE EXCEPTION 'The change note is limited to 500 characters'; END IF;
  IF EXISTS (SELECT 1 FROM inv_recipes WHERE tenant_id = p_tenant_id AND lower(recipe_name) = lower(v_name) AND recipe_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'Another recipe is already called %', v_name;
  END IF;
  IF v_code IS NOT NULL AND EXISTS (SELECT 1 FROM inv_recipes WHERE tenant_id = p_tenant_id AND upper(dough_code) = v_code AND recipe_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'Another recipe already has dough code %', v_code;
  END IF;

  -- Lines: at least one; the calculation checks every ingredient, recipe, quantity and unit.
  IF jsonb_typeof(v_lines) <> 'array' OR jsonb_array_length(v_lines) = 0 THEN RAISE EXCEPTION 'Add at least one ingredient'; END IF;
  IF jsonb_array_length(v_lines) > 200 THEN RAISE EXCEPTION 'A recipe can have at most 200 lines'; END IF;
  PERFORM bps.inv_recipe_calc(p_tenant_id, p_recipe);
  IF v_id IS NOT NULL THEN
    WITH RECURSIVE d(recipe_id) AS (
      SELECT NULLIF(e ->> 'sub_recipe_id', '')::bigint FROM jsonb_array_elements(v_lines) e WHERE NULLIF(e ->> 'sub_recipe_id', '') IS NOT NULL
      UNION
      SELECT l.sub_recipe_id FROM d JOIN inv_recipe_lines l ON l.recipe_id = d.recipe_id WHERE l.sub_recipe_id IS NOT NULL
    )
    SELECT 'x' INTO v_cycle FROM d WHERE d.recipe_id = v_id LIMIT 1;
    IF v_cycle IS NOT NULL THEN RAISE EXCEPTION 'A recipe cannot use itself, also not through another recipe'; END IF;
  END IF;
  FOR v_e, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(v_lines) WITH ORDINALITY LOOP
    IF length(v_e ->> 'note') > 200 THEN RAISE EXCEPTION 'Line %: the note is limited to 200 characters', v_ord; END IF;
  END LOOP;

  -- Steps
  IF jsonb_typeof(v_steps) <> 'array' THEN RAISE EXCEPTION 'Steps must be a list'; END IF;
  FOR v_e, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(v_steps) WITH ORDINALITY LOOP
    IF NULLIF(btrim(v_e ->> 'instruction'), '') IS NULL THEN RAISE EXCEPTION 'Step %: write what to do', v_ord; END IF;
    IF length(v_e ->> 'instruction') > 1000 THEN RAISE EXCEPTION 'Step %: limited to 1,000 characters', v_ord; END IF;
    IF upper(COALESCE(NULLIF(v_e ->> 'step_type', ''), 'OTHER')) NOT IN ('PREP', 'MIX', 'BULK', 'DIVIDE', 'SHAPE', 'PROOF', 'BAKE', 'COOL', 'FINISH', 'OTHER') THEN
      RAISE EXCEPTION 'Step %: unknown step type', v_ord;
    END IF;
    IF NULLIF(v_e ->> 'duration_min', '')::numeric < 0 OR NULLIF(v_e ->> 'duration_min', '')::numeric > 10080 THEN
      RAISE EXCEPTION 'Step %: minutes must be between 0 and 10,080', v_ord;
    END IF;
    IF NULLIF(v_e ->> 'temperature_f', '')::numeric NOT BETWEEN -40 AND 700 THEN RAISE EXCEPTION 'Step %: temperature must be between -40 and 700 °F', v_ord; END IF;
  END LOOP;

  -- Write
  IF v_id IS NULL THEN
    INSERT INTO inv_recipes (tenant_id, recipe_name, recipe_type, dough_code, item_id, piece_weight, piece_unit, loss_pct, ddt_f, friction_f,
                             display_unit, notes, version_no, is_active, created_by, updated_by)
    VALUES (p_tenant_id, v_name, v_type, v_code, v_item, v_piece, v_punit, v_loss, v_ddt, v_fric, v_dunit, v_notes, 1, v_active, v_user, v_user)
    RETURNING recipe_id, version_no INTO v_id, v_version;
  ELSE
    UPDATE inv_recipes SET recipe_name = v_name, recipe_type = v_type, dough_code = v_code, item_id = v_item, piece_weight = v_piece,
                           piece_unit = v_punit, loss_pct = v_loss, ddt_f = v_ddt, friction_f = v_fric, display_unit = v_dunit,
                           notes = v_notes, is_active = v_active, version_no = version_no + 1, updated_by = v_user
     WHERE recipe_id = v_id RETURNING version_no INTO v_version;
    DELETE FROM inv_recipe_lines WHERE recipe_id = v_id;
    DELETE FROM inv_recipe_steps WHERE recipe_id = v_id;
  END IF;

  INSERT INTO inv_recipe_lines (tenant_id, recipe_id, line_no, ingredient_id, sub_recipe_id, quantity, unit, note, created_by, updated_by)
  SELECT p_tenant_id, v_id, e.ordinality, NULLIF(e.value ->> 'ingredient_id', '')::bigint, NULLIF(e.value ->> 'sub_recipe_id', '')::bigint,
         (e.value ->> 'quantity')::numeric, lower(COALESCE(NULLIF(e.value ->> 'unit', ''), 'g')), NULLIF(btrim(e.value ->> 'note'), ''), v_user, v_user
    FROM jsonb_array_elements(v_lines) WITH ORDINALITY e;

  INSERT INTO inv_recipe_steps (tenant_id, recipe_id, step_no, step_type, instruction, duration_min, temperature_f, created_by, updated_by)
  SELECT p_tenant_id, v_id, e.ordinality, upper(COALESCE(NULLIF(e.value ->> 'step_type', ''), 'OTHER')), btrim(e.value ->> 'instruction'),
         round(NULLIF(e.value ->> 'duration_min', '')::numeric)::int, NULLIF(e.value ->> 'temperature_f', '')::numeric, v_user, v_user
    FROM jsonb_array_elements(v_steps) WITH ORDINALITY e;

  INSERT INTO inv_recipe_versions (tenant_id, recipe_id, version_no, change_note, snapshot, saved_by)
  VALUES (p_tenant_id, v_id, v_version, COALESCE(v_note, CASE WHEN v_version = 1 THEN 'Created' END), bps.inv_recipe_json(p_tenant_id, v_id), v_user);

  RETURN bps.inv_recipe_get(p_tenant_id, v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_save(bigint, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_save(bigint, jsonb, text) TO authenticated, service_role, bps_dev;
