-- ============================================================
-- SQL tests for Inventory › Nutrition Labels: FDA rounding (21 CFR 101.9(c)), % Daily Value, label build (servings text,
-- dual column, Contains statement, issues), save / approve / copy / delete, and access. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/nutrition_labels_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator). Creates a staff user with no role
-- ("zz nutrition none") inside the transaction.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v text);
GRANT ALL ON _t, _v TO PUBLIC;

-- 1) rounding, display and %DV (pure functions)
INSERT INTO _t
SELECT 'round ' || r || ' ' || a || ' -> ' || e, bps.inv_nutrient_round(r, a) = e
  FROM (VALUES ('CALORIES', 4.9, 0), ('CALORIES', 47, 45), ('CALORIES', 47.5, 50), ('CALORIES', 50, 50), ('CALORIES', 52, 50), ('CALORIES', 236, 240),
               ('FAT', 0.49, 0), ('FAT', 0.5, 0.5), ('FAT', 2.24, 2), ('FAT', 2.25, 2.5), ('FAT', 4.74, 4.5), ('FAT', 4.8, 5), ('FAT', 5.5, 6), ('FAT', 13.4, 13),
               ('CHOLESTEROL', 1.9, 0), ('CHOLESTEROL', 3, 5), ('CHOLESTEROL', 7.4, 5), ('CHOLESTEROL', 7.5, 10), ('CHOLESTEROL', 33, 35),
               ('SODIUM', 4.9, 0), ('SODIUM', 7, 5), ('SODIUM', 138, 140), ('SODIUM', 140, 140), ('SODIUM', 144, 140), ('SODIUM', 146, 150), ('SODIUM', 421, 420),
               ('GRAM', 0.4, 0), ('GRAM', 0.6, 1), ('GRAM', 1.4, 1), ('GRAM', 1.5, 2), ('GRAM', 37.5, 38),
               ('TENTH', 1.26, 1.3), ('TENTH', 0.04, 0), ('TEN', 264, 260), ('TEN', 265, 270), ('TEN', 4, 0)) x(r, a, e);

INSERT INTO _t
SELECT 'display ' || r || ' ' || a || ' -> ' || e, bps.inv_nutrient_display(r, a, u) = e
  FROM (VALUES ('GRAM', 0.6, 'g', '<1g'), ('GRAM', 0.3, 'g', '0g'), ('CHOLESTEROL', 3, 'mg', '<5mg'), ('FAT', 2.3, 'g', '2.5g'),
               ('FAT', 6, 'g', '6g'), ('CALORIES', 233, 'kcal', '230'), ('TENTH', 2, 'mcg', '2mcg'), ('TENTH', 1.25, 'mg', '1.3mg'),
               ('SODIUM', 422, 'mg', '420mg')) x(r, a, u, e);

INSERT INTO _t
SELECT 'dv ' || r || ' ' || a || '/' || d || ' -> ' || COALESCE(e::text, 'null'), bps.inv_nutrient_dv_pct(r, a, d, vm) IS NOT DISTINCT FROM e
  FROM (VALUES ('FAT', 8::numeric, 78::numeric, false, 10), ('FAT', 0.4, 78, false, 0), ('FAT', 1, 20, false, 5),
               ('SODIUM', 160, 2300, false, 7), ('GRAM', 37, 275, false, 13), ('GRAM', 4, 28, false, 14), ('GRAM', 12, 50, false, 24),
               ('CHOLESTEROL', 3, 300, false, 1), ('GRAM', 3, NULL, false, NULL),
               ('TENTH', 2, 20, true, 10),        -- vitamin D 10%   -> nearest 2  = 10
               ('TEN', 260, 1300, true, 20),      -- calcium 20%
               ('TENTH', 8, 18, true, 45),        -- iron 44.4%      -> nearest 5  = 45
               ('TEN', 240, 4700, true, 6),       -- potassium 5.1%  -> nearest 2  = 6
               ('TENTH', 0.1, 18, true, 0),       -- iron 0.6%       -> 0
               ('TENTH', 11, 18, true, 60),       -- iron 61%        -> nearest 10 = 60
               ('TEN', 150, 1300, true, 10)) x(r, a, d, vm, e);  -- calcium 11.5% -> nearest 5 = 10

-- 2) label build (trusted, as supabase_admin)
DO $$
DECLARE
  t bigint := 200000000002; l jsonb; d jsonb; e boolean;
  base jsonb := jsonb_build_object(
    'serving_size_text', '1 roll', 'serving_size_g', 55, 'servings_per_container', 8,
    'nutrients', jsonb_build_object('calories', 233, 'total_fat', 2.3, 'saturated_fat', 0.4, 'trans_fat', 0, 'cholesterol', 3,
                   'sodium', 422, 'total_carbohydrate', 37.4, 'dietary_fiber', 0.7, 'total_sugars', 3.2, 'added_sugars', 2.6,
                   'protein', 7.6, 'vitamin_d', 0, 'calcium', 260, 'iron', 2.4, 'potassium', 95),
    'ingredient_statement', 'Enriched wheat flour, water, sugar, yeast, salt, sesame seeds.',
    'allergens', jsonb_build_object('wheat', true, 'sesame', true, 'tree_nuts', true), 'tree_nut_types', 'Almonds',
    'may_contain_text', 'Made in a facility that also processes peanuts.');
BEGIN
  l := bps.inv_nutrition_label_build(t, base);
  INSERT INTO _t VALUES ('servings text: 8 servings per container', l ->> 'servings_text' = '8 servings per container');
  INSERT INTO _t VALUES ('serving size text: 1 roll (55g)', l ->> 'serving_size_text' = '1 roll (55g)');
  INSERT INTO _t VALUES ('calories 233 -> 230', l -> 'calories' = '["230"]');
  INSERT INTO _t VALUES ('total fat 2.3g -> 2.5g, 3%', (SELECT x -> 'amounts' = '["2.5g"]' AND x -> 'dv' = '[3]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'total_fat'));
  INSERT INTO _t VALUES ('saturated fat 0.4g -> 0g, 0%', (SELECT x -> 'amounts' = '["0g"]' AND x -> 'dv' = '[0]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'saturated_fat'));
  INSERT INTO _t VALUES ('trans fat has no %DV', (SELECT x -> 'dv' = '[null]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'trans_fat'));
  INSERT INTO _t VALUES ('cholesterol 3mg -> <5mg, 1%', (SELECT x -> 'amounts' = '["<5mg"]' AND x -> 'dv' = '[1]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'cholesterol'));
  INSERT INTO _t VALUES ('sodium 422mg -> 420mg, 18%', (SELECT x -> 'amounts' = '["420mg"]' AND x -> 'dv' = '[18]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'sodium'));
  INSERT INTO _t VALUES ('fiber 0.7g -> <1g, 3%', (SELECT x -> 'amounts' = '["<1g"]' AND x -> 'dv' = '[3]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'dietary_fiber'));
  INSERT INTO _t VALUES ('added sugars 2.6g -> 3g, 5%', (SELECT x -> 'amounts' = '["3g"]' AND x -> 'dv' = '[5]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'added_sugars'));
  INSERT INTO _t VALUES ('protein 7.6g -> 8g without %DV', (SELECT x -> 'amounts' = '["8g"]' AND x -> 'dv' = '[null]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'protein'));
  INSERT INTO _t VALUES ('optional nutrients without a value are left off', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'polyunsaturated_fat'));
  INSERT INTO _t VALUES ('vitamin D 0 -> 0mcg 0%; potassium 95mg (2%) -> 100mg 2%',
    (SELECT x -> 'amounts' = '["0mcg"]' AND x -> 'dv' = '[0]' FROM jsonb_array_elements(l -> 'vitamins') x WHERE x ->> 'code' = 'vitamin_d')
    AND (SELECT x -> 'amounts' = '["100mg"]' AND x -> 'dv' = '[2]' FROM jsonb_array_elements(l -> 'vitamins') x WHERE x ->> 'code' = 'potassium'));
  INSERT INTO _t VALUES ('iron 2.4mg -> 2.4mg 15% (13.3% nearest 5)', (SELECT x -> 'amounts' = '["2.4mg"]' AND x -> 'dv' = '[15]' FROM jsonb_array_elements(l -> 'vitamins') x WHERE x ->> 'code' = 'iron'));
  INSERT INTO _t VALUES ('contains statement in FALCPA order with nut type', l ->> 'contains_statement' = 'Contains: Tree Nuts (Almonds), Wheat, Sesame');
  INSERT INTO _t VALUES ('complete label has no issues', jsonb_array_length(l -> 'issues') = 0);

  l := bps.inv_nutrition_label_build(t, base || '{"servings_per_container": 2.3}');
  INSERT INTO _t VALUES ('2.3 servings -> About 2.5 servings', l ->> 'servings_text' = 'About 2.5 servings per container');
  l := bps.inv_nutrition_label_build(t, base || '{"servings_per_container": 1}');
  INSERT INTO _t VALUES ('1 serving per container (singular)', l ->> 'servings_text' = '1 serving per container');
  l := bps.inv_nutrition_label_build(t, base || '{"servings_per_container": 9.6}');
  INSERT INTO _t VALUES ('9.6 servings -> About 10', l ->> 'servings_text' = 'About 10 servings per container');

  d := bps.inv_nutrition_label_build(t, base || '{"servings_per_container": 3, "is_dual_column": true}');
  INSERT INTO _t VALUES ('dual column: per container calories 233x3=699 -> 700', d -> 'calories' = '["230", "700"]' AND d -> 'columns' = '["Per serving", "Per container"]');
  INSERT INTO _t VALUES ('dual column: sodium 422x3=1266 -> 1270mg, 55%',
    (SELECT x -> 'amounts' = '["420mg", "1270mg"]' AND x -> 'dv' = '[18, 55]' FROM jsonb_array_elements(d -> 'nutrients') x WHERE x ->> 'code' = 'sodium'));
  BEGIN PERFORM bps.inv_nutrition_label_build(t, base || '{"is_dual_column": true, "label_format": "LINEAR"}'); e := false; EXCEPTION WHEN OTHERS THEN e := true; END;
  INSERT INTO _t VALUES ('dual column needs the standard format', e);
  BEGIN PERFORM bps.inv_nutrition_label_build(t, jsonb_set(base, '{nutrients,sodium}', '"abc"')); e := false; EXCEPTION WHEN OTHERS THEN e := SQLERRM = 'Sodium must be a number'; END;
  INSERT INTO _t VALUES ('a non-number is refused with the nutrient name', e);
  BEGIN PERFORM bps.inv_nutrition_label_build(t, jsonb_set(base, '{nutrients,sodium}', '-1')); e := false; EXCEPTION WHEN OTHERS THEN e := true; END;
  INSERT INTO _t VALUES ('a negative amount is refused', e);

  l := bps.inv_nutrition_label_build(t, (base #- '{nutrients,protein}') || '{"tree_nut_types": "", "ingredient_statement": ""}'
                                        || jsonb_build_object('nutrients', (base -> 'nutrients') - 'protein' || '{"added_sugars": 5}'));
  INSERT INTO _t VALUES ('issues: missing protein, ingredients, nut type, added > total sugars',
    l -> 'issues' @> '["Protein is missing", "Ingredient statement is missing", "Name the tree nut(s)", "Added sugars are more than total sugars"]');
  INSERT INTO _t VALUES ('a missing mandatory nutrient prints as 0', (SELECT x -> 'amounts' = '["0g"]' FROM jsonb_array_elements(l -> 'nutrients') x WHERE x ->> 'code' = 'protein'));

  INSERT INTO _v VALUES ('base', base::text);
  INSERT INTO _v SELECT 'item' || rn, item_id FROM (SELECT item_id, row_number() OVER (ORDER BY item_number) rn FROM fnd_items WHERE tenant_id = t AND is_active) x WHERE rn <= 2;
END $$;

-- 3) save / approve / copy / delete as the Company Administrator
DO $$
DECLARE u3 bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, 'aaaaaaaa-0000-4000-8000-000000000071', 'zz nutrition none', 'TENANCY_USER') RETURNING user_id INTO u3;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, u3);
END $$;
CREATE TEMP TABLE _as (k text PRIMARY KEY, auth uuid);
GRANT ALL ON _as TO PUBLIC;
INSERT INTO _as VALUES ('one', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'), ('none', 'aaaaaaaa-0000-4000-8000-000000000071');

SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; r jsonb; e boolean;
  base jsonb := (SELECT v::jsonb FROM _v WHERE k = 'base');
  i1 bigint := (SELECT v::bigint FROM _v WHERE k = 'item1');
  i2 bigint := (SELECT v::bigint FROM _v WHERE k = 'item2');
BEGIN
  r := bps.inv_item_nutrition_save(t, base || jsonb_build_object('item_id', i1, 'source_note', 'Lab report 42'));
  INSERT INTO _t VALUES ('save creates a DRAFT profile', r -> 'profile' ->> 'status' = 'DRAFT' AND r -> 'profile' ->> 'source_note' = 'Lab report 42');
  INSERT INTO _t VALUES ('saved amounts are stored unrounded', (r -> 'profile' -> 'nutrients' ->> 'total_fat')::numeric = 2.3
                                                                AND (SELECT count(*) FROM inv_item_nutrient_values v JOIN inv_item_nutrition n USING (item_nutrition_id) WHERE n.item_id = i1) = 15);
  INSERT INTO _t VALUES ('get returns the computed label', r -> 'label' -> 'calories' = '["230"]');
  INSERT INTO _t VALUES ('list shows the item as DRAFT', (SELECT x ->> 'status' FROM jsonb_array_elements(bps.inv_item_nutrition_list_get(t)) x WHERE (x ->> 'item_id')::bigint = i1) = 'DRAFT');

  r := bps.inv_item_nutrition_approve(t, i1, true);
  INSERT INTO _t VALUES ('approve sets APPROVED with approver', r -> 'profile' ->> 'status' = 'APPROVED' AND r -> 'profile' ->> 'approved_by_name' IS NOT NULL);
  r := bps.inv_item_nutrition_save(t, jsonb_set(base, '{nutrients,polyunsaturated_fat}', '0.6') || jsonb_build_object('item_id', i1));
  INSERT INTO _t VALUES ('editing an approved label puts it back to DRAFT', r -> 'profile' ->> 'status' = 'DRAFT' AND r -> 'profile' ->> 'approved_at' IS NULL);
  r := bps.inv_item_nutrition_save(t, base || jsonb_build_object('item_id', i1));
  INSERT INTO _t VALUES ('a blanked optional nutrient is removed', NOT (r -> 'profile' -> 'nutrients' ? 'polyunsaturated_fat'));

  r := bps.inv_item_nutrition_copy(t, i1, i2);
  INSERT INTO _t VALUES ('copy makes a DRAFT with the same values', r -> 'profile' ->> 'status' = 'DRAFT'
                         AND r -> 'profile' -> 'nutrients' = bps.inv_item_nutrition_payload(t, i1) -> 'nutrients'
                         AND r -> 'profile' ->> 'source_note' LIKE 'Copied from %');
  BEGIN PERFORM bps.inv_item_nutrition_save(t, jsonb_set(base, '{nutrients,protein}', 'null') || jsonb_build_object('item_id', i2));
        PERFORM bps.inv_item_nutrition_approve(t, i2, true); e := false;
  EXCEPTION WHEN OTHERS THEN e := SQLERRM LIKE 'Cannot approve: Protein is missing%'; END;
  INSERT INTO _t VALUES ('an incomplete label cannot be approved', e);
  INSERT INTO _t VALUES ('labels_get returns both labels in item order', jsonb_array_length(bps.inv_nutrition_labels_get(t, ARRAY[i2, i1])) = 2
                         AND (bps.inv_nutrition_labels_get(t, ARRAY[i2, i1]) -> 0 ->> 'item_id')::bigint = i1);
  PERFORM bps.inv_item_nutrition_delete(t, i2);
  INSERT INTO _t VALUES ('delete removes the profile and its amounts', bps.inv_item_nutrition_payload(t, i2) IS NULL
                         AND NOT EXISTS (SELECT 1 FROM inv_item_nutrient_values v WHERE NOT EXISTS (SELECT 1 FROM inv_item_nutrition n WHERE n.item_nutrition_id = v.item_nutrition_id)));
  BEGIN PERFORM bps.inv_item_nutrition_list_get(200000000001); e := false; EXCEPTION WHEN OTHERS THEN e := true; END;
  INSERT INTO _t VALUES ('another tenant is refused', e);
END $$;
RESET ROLE;

-- 4) a staff user without the area
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'none' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE e boolean; i1 bigint := (SELECT v::bigint FROM _v WHERE k = 'item1');
BEGIN
  BEGIN PERFORM bps.inv_item_nutrition_list_get(200000000002); e := false; EXCEPTION WHEN OTHERS THEN e := true; END;
  INSERT INTO _t VALUES ('a user without Nutrition Labels access cannot list', e);
  BEGIN PERFORM bps.inv_item_nutrition_save(200000000002, jsonb_build_object('item_id', i1)); e := false; EXCEPTION WHEN OTHERS THEN e := true; END;
  INSERT INTO _t VALUES ('... nor save', e);
  INSERT INTO _t VALUES ('... nor read the table', (SELECT count(*) FROM inv_item_nutrition) = 0);
END $$;
RESET ROLE;

SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % nutrition label tests failed', bad, total; END IF;
  RAISE NOTICE 'all % nutrition label tests passed', total;
END $$;
ROLLBACK;
