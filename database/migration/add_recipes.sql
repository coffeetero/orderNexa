-- ============================================================
-- Inventory › Recipes: bakery formulas with baker's percentages, pre-ferments as sub-recipes, scaling, method,
-- cost and allergens. Quantities are stored for one BASE BATCH, each in the unit it was entered in (g, kg, oz, lb);
-- the database works out grams, baker's %, totals, hydration, pre-fermented flour, scaling, cost and allergens
-- (inv_recipe_calc). The website only shows the result.
--   inv_ingredients         the tenant's ingredient catalog: name, FLOUR / LIQUID / OTHER (for baker's % and hydration),
--                           purchase price per kg or lb (optional, for costing), Big 9 allergens.
--   inv_recipes             one recipe: name, type (DOUGH / PREFERMENT / OTHER), dough code (matches fnd_items.dough_type
--                           so the screen can list the items made from it), optional finished item and scaling weight per
--                           piece, dough loss %, DDT and friction factor, notes, version number, active flag.
--   inv_recipe_lines        the formula: each line is an ingredient OR another recipe (a pre-ferment, filling, topping).
--   inv_recipe_steps        the method: step type, instruction, minutes, °F.
--   inv_recipe_versions     a snapshot of the recipe at every save, with an optional change note.
-- Access area inventory.recipes (exists already, "Recipes"): R view/print, W edit (recipes and ingredients), D delete.
-- Then load: database/functions/inv_unit_grams.sql, inv_recipe_check.sql, inv_recipe_flat.sql, inv_recipe_calc.sql,
--   inv_recipe_json.sql, inv_recipes_get.sql, inv_recipe_get.sql, inv_recipe_preview.sql, inv_recipe_save.sql,
--   inv_recipe_options.sql, inv_recipe_delete.sql, inv_ingredients_get.sql, inv_ingredient_save.sql, inv_ingredient_delete.sql
-- ============================================================
SET search_path = bps, public;

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('inventory.recipes', 'Inventory', 'Recipes', 'TENANT', 403)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ---------- ingredient catalog ----------
CREATE TABLE IF NOT EXISTS bps.inv_ingredients (
  ingredient_id   bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  ingredient_name text   NOT NULL CONSTRAINT chk_inv_ingredients_name CHECK (btrim(ingredient_name) <> '' AND length(ingredient_name) <= 100),
  ingredient_role text   NOT NULL DEFAULT 'OTHER' CONSTRAINT chk_inv_ingredients_role CHECK (ingredient_role IN ('FLOUR', 'LIQUID', 'OTHER')),
  cost_amount     numeric(12,4) CONSTRAINT chk_inv_ingredients_cost CHECK (cost_amount >= 0),
  cost_unit       text   NOT NULL DEFAULT 'lb' CONSTRAINT chk_inv_ingredients_cost_unit CHECK (cost_unit IN ('kg', 'lb')),
  allergens       text[] NOT NULL DEFAULT '{}' CONSTRAINT chk_inv_ingredients_allergens CHECK (allergens <@ ARRAY['milk', 'egg', 'fish', 'shellfish', 'tree_nuts', 'peanuts', 'wheat', 'soy', 'sesame']::text[]),
  notes           text   CONSTRAINT chk_inv_ingredients_notes CHECK (length(notes) <= 500),
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      bigint,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      bigint
);
COMMENT ON TABLE bps.inv_ingredients IS 'Recipe ingredients of a tenant (flour, water, salt, butter...): role for baker''s %, purchase price, allergens.';
COMMENT ON COLUMN bps.inv_ingredients.ingredient_role IS 'FLOUR counts as flour (100% basis of baker''s percentages); LIQUID counts as water for hydration; OTHER neither.';
COMMENT ON COLUMN bps.inv_ingredients.cost_amount IS 'Purchase price per cost_unit (kg or lb). NULL = no price; recipes show the cost as incomplete.';
COMMENT ON COLUMN bps.inv_ingredients.allergens IS 'Big 9 allergen codes the ingredient contains (same codes as inv_item_nutrition).';
CREATE UNIQUE INDEX IF NOT EXISTS uq_inv_ingredients_name ON bps.inv_ingredients (tenant_id, lower(ingredient_name));

-- ---------- recipes ----------
CREATE TABLE IF NOT EXISTS bps.inv_recipes (
  recipe_id        bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id        bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  recipe_name      text   NOT NULL CONSTRAINT chk_inv_recipes_name CHECK (btrim(recipe_name) <> '' AND length(recipe_name) <= 100),
  recipe_type      text   NOT NULL DEFAULT 'DOUGH' CONSTRAINT chk_inv_recipes_type CHECK (recipe_type IN ('DOUGH', 'PREFERMENT', 'OTHER')),
  dough_code       text   CONSTRAINT chk_inv_recipes_dough_code CHECK (length(dough_code) <= 30),
  item_id          bigint REFERENCES bps.fnd_items(item_id) ON DELETE SET NULL,
  piece_weight     numeric(12,4) CONSTRAINT chk_inv_recipes_piece_weight CHECK (piece_weight > 0),
  piece_unit       text   NOT NULL DEFAULT 'g' CONSTRAINT chk_inv_recipes_piece_unit CHECK (piece_unit IN ('g', 'kg', 'oz', 'lb')),
  loss_pct         numeric(5,2) NOT NULL DEFAULT 0 CONSTRAINT chk_inv_recipes_loss CHECK (loss_pct >= 0 AND loss_pct < 50),
  ddt_f            numeric(5,1) CONSTRAINT chk_inv_recipes_ddt CHECK (ddt_f BETWEEN 40 AND 110),
  friction_f       numeric(5,1) CONSTRAINT chk_inv_recipes_friction CHECK (friction_f BETWEEN 0 AND 60),
  display_unit     text   NOT NULL DEFAULT 'g' CONSTRAINT chk_inv_recipes_display_unit CHECK (display_unit IN ('g', 'kg', 'oz', 'lb')),
  notes            text   CONSTRAINT chk_inv_recipes_notes CHECK (length(notes) <= 4000),
  version_no       integer NOT NULL DEFAULT 1,
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       bigint,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       bigint
);
COMMENT ON TABLE bps.inv_recipes IS 'Bakery recipe / formula. Line quantities are for one base batch; baker''s %, scaling and cost are computed (inv_recipe_calc).';
COMMENT ON COLUMN bps.inv_recipes.dough_code IS 'Matches fnd_items.dough_type: the items made from this dough are listed with the recipe.';
COMMENT ON COLUMN bps.inv_recipes.item_id IS 'Optional finished item the recipe produces.';
COMMENT ON COLUMN bps.inv_recipes.piece_weight IS 'Scaling (divide) weight of one piece, in piece_unit; gives pieces per batch and scaling by pieces.';
COMMENT ON COLUMN bps.inv_recipes.loss_pct IS 'Dough lost in mixing and dividing, % of the batch; taken off before pieces are counted.';
COMMENT ON COLUMN bps.inv_recipes.ddt_f IS 'Desired dough temperature (°F); with friction_f gives the water temperature on the batch sheet.';
COMMENT ON COLUMN bps.inv_recipes.friction_f IS 'Mixer friction factor (°F) for the water temperature calculation.';
COMMENT ON COLUMN bps.inv_recipes.display_unit IS 'Unit the recipe is shown and printed in by default.';
COMMENT ON COLUMN bps.inv_recipes.version_no IS 'Goes up by one at every save; inv_recipe_versions keeps each version.';
CREATE UNIQUE INDEX IF NOT EXISTS uq_inv_recipes_name ON bps.inv_recipes (tenant_id, lower(recipe_name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_inv_recipes_dough_code ON bps.inv_recipes (tenant_id, upper(dough_code)) WHERE dough_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inv_recipes_item ON bps.inv_recipes (item_id);

CREATE TABLE IF NOT EXISTS bps.inv_recipe_lines (
  recipe_line_id  bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  recipe_id       bigint NOT NULL REFERENCES bps.inv_recipes(recipe_id) ON DELETE CASCADE,
  line_no         integer NOT NULL,
  ingredient_id   bigint REFERENCES bps.inv_ingredients(ingredient_id),
  sub_recipe_id   bigint REFERENCES bps.inv_recipes(recipe_id),
  quantity        numeric(14,4) NOT NULL CONSTRAINT chk_inv_recipe_lines_qty CHECK (quantity > 0),
  unit            text   NOT NULL DEFAULT 'g' CONSTRAINT chk_inv_recipe_lines_unit CHECK (unit IN ('g', 'kg', 'oz', 'lb')),
  note            text   CONSTRAINT chk_inv_recipe_lines_note CHECK (length(note) <= 200),
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      bigint,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      bigint,
  CONSTRAINT chk_inv_recipe_lines_source CHECK ((ingredient_id IS NULL) <> (sub_recipe_id IS NULL)),
  CONSTRAINT chk_inv_recipe_lines_self CHECK (sub_recipe_id IS DISTINCT FROM recipe_id),
  CONSTRAINT uq_inv_recipe_lines_no UNIQUE (recipe_id, line_no)
);
COMMENT ON TABLE bps.inv_recipe_lines IS 'Formula line of a recipe: an ingredient or a sub-recipe (pre-ferment...), quantity for one base batch.';
CREATE INDEX IF NOT EXISTS idx_inv_recipe_lines_ingredient ON bps.inv_recipe_lines (ingredient_id);
CREATE INDEX IF NOT EXISTS idx_inv_recipe_lines_sub ON bps.inv_recipe_lines (sub_recipe_id);

CREATE TABLE IF NOT EXISTS bps.inv_recipe_steps (
  recipe_step_id  bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  recipe_id       bigint NOT NULL REFERENCES bps.inv_recipes(recipe_id) ON DELETE CASCADE,
  step_no         integer NOT NULL,
  step_type       text   NOT NULL DEFAULT 'OTHER' CONSTRAINT chk_inv_recipe_steps_type CHECK (step_type IN
                    ('PREP', 'MIX', 'BULK', 'DIVIDE', 'SHAPE', 'PROOF', 'BAKE', 'COOL', 'FINISH', 'OTHER')),
  instruction     text   NOT NULL CONSTRAINT chk_inv_recipe_steps_text CHECK (btrim(instruction) <> '' AND length(instruction) <= 1000),
  duration_min    integer CONSTRAINT chk_inv_recipe_steps_minutes CHECK (duration_min >= 0 AND duration_min <= 10080),
  temperature_f   numeric(5,1) CONSTRAINT chk_inv_recipe_steps_temp CHECK (temperature_f BETWEEN -40 AND 700),
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      bigint,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      bigint,
  CONSTRAINT uq_inv_recipe_steps_no UNIQUE (recipe_id, step_no)
);
COMMENT ON TABLE bps.inv_recipe_steps IS 'Method step of a recipe: type, instruction, time (minutes) and temperature (°F).';

CREATE TABLE IF NOT EXISTS bps.inv_recipe_versions (
  recipe_version_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id         bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  recipe_id         bigint NOT NULL REFERENCES bps.inv_recipes(recipe_id) ON DELETE CASCADE,
  version_no        integer NOT NULL,
  change_note       text   CONSTRAINT chk_inv_recipe_versions_note CHECK (length(change_note) <= 500),
  snapshot          jsonb  NOT NULL,
  saved_at          timestamptz NOT NULL DEFAULT now(),
  saved_by          bigint,
  CONSTRAINT uq_inv_recipe_versions UNIQUE (recipe_id, version_no)
);
COMMENT ON TABLE bps.inv_recipe_versions IS 'Every saved version of a recipe (fields, lines and steps as JSON) with who saved it and why.';

DO $$
DECLARE tbl text; pk text;
BEGIN
  FOR tbl, pk IN VALUES ('inv_ingredients', 'ingredient_id'), ('inv_recipes', 'recipe_id'), ('inv_recipe_lines', 'recipe_line_id'),
                        ('inv_recipe_steps', 'recipe_step_id') LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_set_updated ON bps.%I', tbl, tbl);
    EXECUTE format('CREATE TRIGGER trg_%s_set_updated BEFORE UPDATE ON bps.%I FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only()', tbl, tbl);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_audit ON bps.%I', tbl, tbl);
    EXECUTE format('CREATE TRIGGER trg_%s_audit AFTER INSERT OR DELETE OR UPDATE ON bps.%I FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log(%L)', tbl, tbl, pk);
  END LOOP;
END $$;

-- ---------- row security (the inv_recipe* functions are SECURITY DEFINER and check access themselves) ----------
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['inv_ingredients', 'inv_recipes', 'inv_recipe_lines', 'inv_recipe_steps', 'inv_recipe_versions'] LOOP
    EXECUTE format('ALTER TABLE bps.%I ENABLE ROW LEVEL SECURITY', tbl);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON bps.%I TO authenticated', tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_read ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_read ON bps.%I FOR SELECT TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.recipes', 'R'))))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_insert ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_insert ON bps.%I FOR INSERT TO authenticated WITH CHECK (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.recipes', 'W'))))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_update ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_update ON bps.%I FOR UPDATE TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.recipes', 'W'))))
      WITH CHECK ((SELECT bps.fnd_is_trusted()) OR tenant_id = (SELECT bps.fnd_active_tenant_id()))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_delete ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_delete ON bps.%I FOR DELETE TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('inventory.recipes', 'W'))))$p$, tbl, tbl);
  END LOOP;
END $$;
