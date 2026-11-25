-- ============================================================
-- inv_item_nutrition_save
-- Creates or replaces an item's nutrition profile. p_payload: { item_id, source_note, serving_size_text, serving_size_g,
-- servings_per_container, label_format, is_dual_column, nutrients: {code: amount per serving}, ingredient_statement,
-- allergens: {milk, egg, fish, shellfish, tree_nuts, peanuts, wheat, soy, sesame}, fish_species, shellfish_species,
-- tree_nut_types, may_contain_text, effective_date }
-- Numbers are checked by inv_nutrition_label_build. A draft may be incomplete. Any save puts an approved label back to DRAFT.
-- Nutrients left blank are removed. Returns inv_item_nutrition_get.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_item_nutrition_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user  bigint := bps.fnd_current_user_id();
  v_item  bigint := NULLIF(p_payload ->> 'item_id', '')::bigint;
  v_al    jsonb  := COALESCE(p_payload -> 'allergens', '{}'::jsonb);
  v_nut   jsonb  := COALESCE(p_payload -> 'nutrients', '{}'::jsonb);
  v_id    bigint;
  v_eff   date;
  v_label jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.labels', 'W') THEN RAISE EXCEPTION 'You do not have access to edit nutrition labels'; END IF;
  IF v_item IS NULL OR NOT EXISTS (SELECT 1 FROM fnd_items WHERE tenant_id = p_tenant_id AND item_id = v_item) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;
  v_label := bps.inv_nutrition_label_build(p_tenant_id, p_payload);   -- raises on bad numbers / format
  BEGIN v_eff := NULLIF(btrim(p_payload ->> 'effective_date'), '')::date;
  EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Effective date is not a valid date';
  END;

  INSERT INTO inv_item_nutrition AS t (
    tenant_id, item_id, value_source, source_note, serving_size_text, serving_size_g, servings_per_container, label_format, is_dual_column,
    ingredient_statement, is_allergen_milk, is_allergen_egg, is_allergen_fish, is_allergen_shellfish, is_allergen_tree_nuts,
    is_allergen_peanuts, is_allergen_wheat, is_allergen_soy, is_allergen_sesame, fish_species, shellfish_species, tree_nut_types,
    may_contain_text, effective_date, status, approved_at, approved_by, created_by, updated_by)
  VALUES (
    p_tenant_id, v_item, 'ENTERED', NULLIF(btrim(p_payload ->> 'source_note'), ''), NULLIF(btrim(p_payload ->> 'serving_size_text'), ''),
    NULLIF(btrim(p_payload ->> 'serving_size_g'), '')::numeric, NULLIF(btrim(p_payload ->> 'servings_per_container'), '')::numeric,
    v_label ->> 'label_format', (v_label ->> 'is_dual_column')::boolean,
    NULLIF(btrim(p_payload ->> 'ingredient_statement'), ''),
    COALESCE((v_al ->> 'milk')::boolean, false), COALESCE((v_al ->> 'egg')::boolean, false), COALESCE((v_al ->> 'fish')::boolean, false),
    COALESCE((v_al ->> 'shellfish')::boolean, false), COALESCE((v_al ->> 'tree_nuts')::boolean, false),
    COALESCE((v_al ->> 'peanuts')::boolean, false), COALESCE((v_al ->> 'wheat')::boolean, false),
    COALESCE((v_al ->> 'soy')::boolean, false), COALESCE((v_al ->> 'sesame')::boolean, false),
    NULLIF(btrim(p_payload ->> 'fish_species'), ''), NULLIF(btrim(p_payload ->> 'shellfish_species'), ''),
    NULLIF(btrim(p_payload ->> 'tree_nut_types'), ''), NULLIF(btrim(p_payload ->> 'may_contain_text'), ''), v_eff,
    'DRAFT', NULL, NULL, v_user, v_user)
  ON CONFLICT ON CONSTRAINT uq_inv_item_nutrition_item DO UPDATE SET
    value_source = EXCLUDED.value_source, source_note = EXCLUDED.source_note, serving_size_text = EXCLUDED.serving_size_text,
    serving_size_g = EXCLUDED.serving_size_g, servings_per_container = EXCLUDED.servings_per_container,
    label_format = EXCLUDED.label_format, is_dual_column = EXCLUDED.is_dual_column, ingredient_statement = EXCLUDED.ingredient_statement,
    is_allergen_milk = EXCLUDED.is_allergen_milk, is_allergen_egg = EXCLUDED.is_allergen_egg, is_allergen_fish = EXCLUDED.is_allergen_fish,
    is_allergen_shellfish = EXCLUDED.is_allergen_shellfish, is_allergen_tree_nuts = EXCLUDED.is_allergen_tree_nuts,
    is_allergen_peanuts = EXCLUDED.is_allergen_peanuts, is_allergen_wheat = EXCLUDED.is_allergen_wheat,
    is_allergen_soy = EXCLUDED.is_allergen_soy, is_allergen_sesame = EXCLUDED.is_allergen_sesame,
    fish_species = EXCLUDED.fish_species, shellfish_species = EXCLUDED.shellfish_species, tree_nut_types = EXCLUDED.tree_nut_types,
    may_contain_text = EXCLUDED.may_contain_text, effective_date = EXCLUDED.effective_date,
    status = 'DRAFT', approved_at = NULL, approved_by = NULL, updated_at = now(), updated_by = v_user
  RETURNING item_nutrition_id INTO v_id;

  -- amounts: keep the given ones, drop the rest
  DELETE FROM inv_item_nutrient_values v
   WHERE v.item_nutrition_id = v_id AND NULLIF(btrim(v_nut ->> v.nutrient_code), '') IS NULL;
  INSERT INTO inv_item_nutrient_values AS t (tenant_id, item_nutrition_id, nutrient_code, amount, created_by, updated_by)
  SELECT p_tenant_id, v_id, n.nutrient_code, btrim(e.value)::numeric, v_user, v_user
    FROM jsonb_each_text(v_nut) e
    JOIN inv_nutrients n ON n.nutrient_code = e.key AND n.is_active
   WHERE NULLIF(btrim(e.value), '') IS NOT NULL
  ON CONFLICT ON CONSTRAINT uq_inv_item_nutrient_values DO UPDATE SET amount = EXCLUDED.amount, updated_at = now(), updated_by = v_user
   WHERE t.amount IS DISTINCT FROM EXCLUDED.amount;

  RETURN bps.inv_item_nutrition_get(p_tenant_id, v_item);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_item_nutrition_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_item_nutrition_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
