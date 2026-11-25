-- ============================================================
-- Inventory › Nutrition Labels: an FDA Nutrition Facts profile per item (21 CFR 101.9, 2016 format).
-- Values are ENTERED per item (from a lab or a nutrition tool), per serving, unrounded. The database rounds them and works out
-- the % Daily Values (inv_nutrition_label_build); the website only draws the result.
--   inv_nutrients             FDA reference list: one row per nutrient (unit, daily value, rounding rule, label order). Not per tenant.
--   inv_item_nutrition        one profile per item: serving, label format, ingredient statement, allergens, status/approval.
--   inv_item_nutrient_values  the profile's amounts per serving, one row per nutrient.
-- Later, calculation from recipes (fnd_item_bom) can fill inv_item_nutrient_values from ingredient values stored with the same
-- nutrient codes and set inv_item_nutrition.value_source = 'CALCULATED'.
-- Access area inventory.labels (exists already, "Nutrition Labels"): R view/print, W edit, A approve, D delete.
-- Then load: database/functions/inv_nutrient_round.sql, inv_nutrient_display.sql, inv_nutrient_dv_pct.sql,
--   inv_nutrition_label_build.sql, inv_item_nutrition_payload.sql, inv_item_nutrition_list_get.sql, inv_item_nutrition_get.sql,
--   inv_item_nutrition_save.sql, inv_item_nutrition_approve.sql, inv_item_nutrition_copy.sql, inv_item_nutrition_delete.sql,
--   inv_nutrition_labels_get.sql
-- ============================================================
SET search_path = bps, public;

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('inventory.labels', 'Inventory', 'Nutrition Labels', 'TENANT', 407)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ---------- reference list of nutrients ----------
CREATE TABLE IF NOT EXISTS bps.inv_nutrients (
  nutrient_code  text PRIMARY KEY CONSTRAINT chk_inv_nutrients_code CHECK (nutrient_code ~ '^[a-z_]+$'),
  label_name     text NOT NULL,
  unit           text NOT NULL CONSTRAINT chk_inv_nutrients_unit CHECK (unit IN ('kcal', 'g', 'mg', 'mcg')),
  daily_value    numeric(10,2),           -- FDA DV for adults and children 4+ (101.9(c)(8)(iv), (c)(9)); NULL = no %DV shown
  rounding_rule  text NOT NULL CONSTRAINT chk_inv_nutrients_rule CHECK (rounding_rule IN
                   ('CALORIES', 'FAT', 'CHOLESTEROL', 'SODIUM', 'GRAM', 'TENTH', 'TEN')),
  is_mandatory   boolean NOT NULL DEFAULT false,
  is_vitamin_mineral boolean NOT NULL DEFAULT false,
  indent_level   smallint NOT NULL DEFAULT 0,
  display_order  integer NOT NULL,
  is_active      boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE bps.inv_nutrients IS 'FDA Nutrition Facts nutrients: unit, daily value, rounding rule and label order. Shared by every tenant.';

INSERT INTO bps.inv_nutrients (nutrient_code, label_name, unit, daily_value, rounding_rule, is_mandatory, is_vitamin_mineral, indent_level, display_order) VALUES
  ('calories',          'Calories',            'kcal', NULL,  'CALORIES',    true,  false, 0,  10),
  ('total_fat',         'Total Fat',           'g',    78,    'FAT',         true,  false, 0,  20),
  ('saturated_fat',     'Saturated Fat',       'g',    20,    'FAT',         true,  false, 1,  30),
  ('trans_fat',         'Trans Fat',           'g',    NULL,  'FAT',         true,  false, 1,  40),
  ('polyunsaturated_fat','Polyunsaturated Fat','g',    NULL,  'FAT',         false, false, 1,  50),
  ('monounsaturated_fat','Monounsaturated Fat','g',    NULL,  'FAT',         false, false, 1,  60),
  ('cholesterol',       'Cholesterol',         'mg',   300,   'CHOLESTEROL', true,  false, 0,  70),
  ('sodium',            'Sodium',              'mg',   2300,  'SODIUM',      true,  false, 0,  80),
  ('total_carbohydrate','Total Carbohydrate',  'g',    275,   'GRAM',        true,  false, 0,  90),
  ('dietary_fiber',     'Dietary Fiber',       'g',    28,    'GRAM',        true,  false, 1, 100),
  ('soluble_fiber',     'Soluble Fiber',       'g',    NULL,  'GRAM',        false, false, 2, 110),
  ('insoluble_fiber',   'Insoluble Fiber',     'g',    NULL,  'GRAM',        false, false, 2, 120),
  ('total_sugars',      'Total Sugars',        'g',    NULL,  'GRAM',        true,  false, 1, 130),
  ('added_sugars',      'Added Sugars',        'g',    50,    'GRAM',        true,  false, 2, 140),
  ('sugar_alcohol',     'Sugar Alcohol',       'g',    NULL,  'GRAM',        false, false, 1, 150),
  ('protein',           'Protein',             'g',    NULL,  'GRAM',        true,  false, 0, 160),
  ('vitamin_d',         'Vitamin D',           'mcg',  20,    'TENTH',       true,  true,  0, 200),
  ('calcium',           'Calcium',             'mg',   1300,  'TEN',         true,  true,  0, 210),
  ('iron',              'Iron',                'mg',   18,    'TENTH',       true,  true,  0, 220),
  ('potassium',         'Potassium',           'mg',   4700,  'TEN',         true,  true,  0, 230),
  ('vitamin_a',         'Vitamin A',           'mcg',  900,   'TEN',         false, true,  0, 240),
  ('vitamin_c',         'Vitamin C',           'mg',   90,    'TENTH',       false, true,  0, 250)
ON CONFLICT (nutrient_code) DO NOTHING;

ALTER TABLE bps.inv_nutrients ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON bps.inv_nutrients TO authenticated;
DROP POLICY IF EXISTS pol_inv_nutrients_read ON bps.inv_nutrients;
CREATE POLICY pol_inv_nutrients_read ON bps.inv_nutrients FOR SELECT TO authenticated USING (true);

-- ---------- one profile per item ----------
CREATE TABLE IF NOT EXISTS bps.inv_item_nutrition (
  item_nutrition_id      bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id              bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  item_id                bigint NOT NULL REFERENCES bps.fnd_items(item_id) ON DELETE CASCADE,
  value_source           text   NOT NULL DEFAULT 'ENTERED' CONSTRAINT chk_inv_item_nutrition_source CHECK (value_source IN ('ENTERED', 'CALCULATED')),
  source_note            text   CONSTRAINT chk_inv_item_nutrition_source_note CHECK (length(source_note) <= 500),
  serving_size_text      text   CONSTRAINT chk_inv_item_nutrition_serving_text CHECK (length(serving_size_text) <= 100),
  serving_size_g         numeric(10,2) CONSTRAINT chk_inv_item_nutrition_serving_g CHECK (serving_size_g > 0),
  servings_per_container numeric(10,2) CONSTRAINT chk_inv_item_nutrition_servings CHECK (servings_per_container > 0),
  label_format           text   NOT NULL DEFAULT 'STANDARD' CONSTRAINT chk_inv_item_nutrition_format CHECK (label_format IN ('STANDARD', 'TABULAR', 'LINEAR')),
  is_dual_column         boolean NOT NULL DEFAULT false,
  ingredient_statement   text   CONSTRAINT chk_inv_item_nutrition_ingredients CHECK (length(ingredient_statement) <= 4000),
  is_allergen_milk       boolean NOT NULL DEFAULT false,
  is_allergen_egg        boolean NOT NULL DEFAULT false,
  is_allergen_fish       boolean NOT NULL DEFAULT false,
  is_allergen_shellfish  boolean NOT NULL DEFAULT false,
  is_allergen_tree_nuts  boolean NOT NULL DEFAULT false,
  is_allergen_peanuts    boolean NOT NULL DEFAULT false,
  is_allergen_wheat      boolean NOT NULL DEFAULT false,
  is_allergen_soy        boolean NOT NULL DEFAULT false,
  is_allergen_sesame     boolean NOT NULL DEFAULT false,
  fish_species           text   CONSTRAINT chk_inv_item_nutrition_fish CHECK (length(fish_species) <= 200),
  shellfish_species      text   CONSTRAINT chk_inv_item_nutrition_shellfish CHECK (length(shellfish_species) <= 200),
  tree_nut_types         text   CONSTRAINT chk_inv_item_nutrition_nuts CHECK (length(tree_nut_types) <= 200),
  may_contain_text       text   CONSTRAINT chk_inv_item_nutrition_may_contain CHECK (length(may_contain_text) <= 500),
  status                 text   NOT NULL DEFAULT 'DRAFT' CONSTRAINT chk_inv_item_nutrition_status CHECK (status IN ('DRAFT', 'APPROVED')),
  approved_at            timestamptz,
  approved_by            bigint REFERENCES bps.fnd_users(user_id),
  effective_date         date,
  created_at             timestamptz NOT NULL DEFAULT now(),
  created_by             bigint,
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             bigint,
  CONSTRAINT uq_inv_item_nutrition_item UNIQUE (tenant_id, item_id),
  CONSTRAINT chk_inv_item_nutrition_dual CHECK (NOT is_dual_column OR label_format = 'STANDARD'),
  CONSTRAINT chk_inv_item_nutrition_approved CHECK ((status = 'APPROVED') = (approved_at IS NOT NULL))
);
COMMENT ON TABLE bps.inv_item_nutrition IS 'Nutrition Facts profile of an item: serving, label format, ingredient statement, Big 9 allergens, approval.';
COMMENT ON COLUMN bps.inv_item_nutrition.value_source IS 'ENTERED (lab or tool values typed in) or CALCULATED (reserved for calculation from recipes).';
COMMENT ON COLUMN bps.inv_item_nutrition.source_note IS 'Where the values came from, e.g. lab report number or tool name.';
COMMENT ON COLUMN bps.inv_item_nutrition.serving_size_text IS 'Household measure, e.g. "1 roll" or "1/8 loaf".';
COMMENT ON COLUMN bps.inv_item_nutrition.is_dual_column IS 'Adds a per-container column (FDA dual-column label for packages of 2-3 servings).';
COMMENT ON COLUMN bps.inv_item_nutrition.ingredient_statement IS 'Ingredients in descending order of weight (21 CFR 101.4), as printed.';
COMMENT ON COLUMN bps.inv_item_nutrition.tree_nut_types IS 'Required when tree nuts are flagged: the nut(s) by name, e.g. "Almonds, Pecans".';
COMMENT ON COLUMN bps.inv_item_nutrition.may_contain_text IS 'Voluntary advisory statement, e.g. "Made in a facility that also processes peanuts."';
COMMENT ON COLUMN bps.inv_item_nutrition.effective_date IS 'Optional date the approved label is used from.';
CREATE INDEX IF NOT EXISTS idx_inv_item_nutrition_item ON bps.inv_item_nutrition (item_id);

CREATE TABLE IF NOT EXISTS bps.inv_item_nutrient_values (
  item_nutrient_value_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id              bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  item_nutrition_id      bigint NOT NULL REFERENCES bps.inv_item_nutrition(item_nutrition_id) ON DELETE CASCADE,
  nutrient_code          text   NOT NULL REFERENCES bps.inv_nutrients(nutrient_code),
  amount                 numeric(12,4) NOT NULL CONSTRAINT chk_inv_item_nutrient_values_amount CHECK (amount >= 0),
  created_at             timestamptz NOT NULL DEFAULT now(),
  created_by             bigint,
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             bigint,
  CONSTRAINT uq_inv_item_nutrient_values UNIQUE (item_nutrition_id, nutrient_code)
);
COMMENT ON TABLE bps.inv_item_nutrient_values IS 'Amount per serving (unrounded, in the nutrient''s unit) of each nutrient in an item''s nutrition profile.';
CREATE INDEX IF NOT EXISTS idx_inv_item_nutrient_values_tenant ON bps.inv_item_nutrient_values (tenant_id);

DROP TRIGGER IF EXISTS trg_inv_item_nutrition_set_updated ON bps.inv_item_nutrition;
CREATE TRIGGER trg_inv_item_nutrition_set_updated BEFORE UPDATE ON bps.inv_item_nutrition FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_inv_item_nutrition_audit ON bps.inv_item_nutrition;
CREATE TRIGGER trg_inv_item_nutrition_audit AFTER INSERT OR DELETE OR UPDATE ON bps.inv_item_nutrition FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('item_nutrition_id');
DROP TRIGGER IF EXISTS trg_inv_item_nutrient_values_set_updated ON bps.inv_item_nutrient_values;
CREATE TRIGGER trg_inv_item_nutrient_values_set_updated BEFORE UPDATE ON bps.inv_item_nutrient_values FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_inv_item_nutrient_values_audit ON bps.inv_item_nutrient_values;
CREATE TRIGGER trg_inv_item_nutrient_values_audit AFTER INSERT OR DELETE OR UPDATE ON bps.inv_item_nutrient_values FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('item_nutrient_value_id');

-- ---------- row security ----------
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['inv_item_nutrition', 'inv_item_nutrient_values'] LOOP
    EXECUTE format('ALTER TABLE bps.%I ENABLE ROW LEVEL SECURITY', tbl);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON bps.%I TO authenticated', tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_read ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_read ON bps.%I FOR SELECT TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.labels', 'R'))))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_insert ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_insert ON bps.%I FOR INSERT TO authenticated WITH CHECK (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.labels', 'W'))))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_update ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_update ON bps.%I FOR UPDATE TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.labels', 'W'))))
      WITH CHECK ((SELECT bps.fnd_is_trusted()) OR tenant_id = (SELECT bps.fnd_active_tenant_id()))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_delete ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_delete ON bps.%I FOR DELETE TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.labels', 'W'))))$p$, tbl, tbl);
  END LOOP;
END $$;
