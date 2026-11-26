-- ============================================================
-- Purchasing (proof of concept, 2026-11-26): vendors and what we buy from them. Purchase orders and receiving come later
-- (po_orders, po_order_lines, po_receipts, po_receipt_lines). Prefix po_ = everything about buying from vendors.
--   po_vendors             who we buy from: code, name, our account number with them, terms, lead time, delivery days,
--                          minimum order, currency. Contacts, phones, emails and addresses use fnd_contacts /
--                          fnd_contact_points with source_table 'po_vendors' (no contact columns here).
--   po_vendor_items        what we buy from a vendor: their SKU, description, kind (INGREDIENT / PACKAGING / SUPPLY),
--                          optional recipe ingredient, pack (50 lb bag = pack_qty 50, pack_unit lb, pack_label bag),
--                          current pack price, minimum order, preferred source for its ingredient.
--   po_vendor_item_prices  price history: every price change of a vendor item, with its date and source (MANUAL now,
--                          RECEIPT once receiving exists).
-- Cost per lb / kg / l / gal / each is worked out from the pack price by the database (po_vendor_items_get).
-- Access area purchasing.vendors (module Inventory while Purchasing sits in the Inventory menu): R view, W edit, D delete.
-- Then load: database/functions/po_unit_base.sql, po_check.sql, po_vendors_get.sql, po_vendor_save.sql, po_vendor_delete.sql,
--   po_vendor_items_get.sql, po_vendor_item_save.sql, po_vendor_item_delete.sql, po_vendor_item_prices_get.sql, po_options_get.sql
-- ============================================================
SET search_path = bps, public;

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('purchasing.vendors', 'Inventory', 'Purchasing: Vendors and Vendor Items', 'TENANT', 410)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ---------- vendors ----------
CREATE TABLE IF NOT EXISTS bps.po_vendors (
  vendor_id        bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id        bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  vendor_code      text   NOT NULL CONSTRAINT chk_po_vendors_code CHECK (vendor_code ~ '^[A-Z0-9][A-Z0-9_-]{0,19}$'),
  vendor_name      text   NOT NULL CONSTRAINT chk_po_vendors_name CHECK (btrim(vendor_name) <> '' AND length(vendor_name) <= 100),
  account_number   text   CONSTRAINT chk_po_vendors_account CHECK (length(account_number) <= 50),
  payment_terms    text   CONSTRAINT chk_po_vendors_terms CHECK (length(payment_terms) <= 50),
  lead_time_days   integer CONSTRAINT chk_po_vendors_lead CHECK (lead_time_days BETWEEN 0 AND 90),
  delivery_days    text[] NOT NULL DEFAULT '{}' CONSTRAINT chk_po_vendors_days CHECK (delivery_days <@ ARRAY['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']::text[]),
  min_order_amount numeric(12,2) CONSTRAINT chk_po_vendors_min CHECK (min_order_amount >= 0),
  currency_code    text   NOT NULL DEFAULT 'USD' CONSTRAINT chk_po_vendors_currency CHECK (currency_code ~ '^[A-Z]{3}$'),
  website          text   CONSTRAINT chk_po_vendors_website CHECK (length(website) <= 200),
  notes            text   CONSTRAINT chk_po_vendors_notes CHECK (length(notes) <= 2000),
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       bigint,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       bigint
);
COMMENT ON TABLE bps.po_vendors IS 'Vendors (suppliers) a tenant buys from. Contacts and addresses are fnd_contacts rows with source_table = ''po_vendors''.';
COMMENT ON COLUMN bps.po_vendors.vendor_code IS 'Short code, upper case (GIUSTO, SYSCO-NJ); unique per tenant.';
COMMENT ON COLUMN bps.po_vendors.account_number IS 'Our customer/account number with the vendor (goes on purchase orders).';
COMMENT ON COLUMN bps.po_vendors.lead_time_days IS 'Days from ordering to delivery.';
COMMENT ON COLUMN bps.po_vendors.delivery_days IS 'Days of the week the vendor delivers (MON..SUN).';
COMMENT ON COLUMN bps.po_vendors.min_order_amount IS 'Minimum order value in currency_code, if the vendor has one.';
CREATE UNIQUE INDEX IF NOT EXISTS uq_po_vendors_code ON bps.po_vendors (tenant_id, vendor_code);
CREATE UNIQUE INDEX IF NOT EXISTS uq_po_vendors_name ON bps.po_vendors (tenant_id, lower(vendor_name));

-- ---------- vendor items ----------
CREATE TABLE IF NOT EXISTS bps.po_vendor_items (
  vendor_item_id  bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  vendor_id       bigint NOT NULL REFERENCES bps.po_vendors(vendor_id),
  item_kind       text   NOT NULL DEFAULT 'INGREDIENT' CONSTRAINT chk_po_vendor_items_kind CHECK (item_kind IN ('INGREDIENT', 'PACKAGING', 'SUPPLY')),
  ingredient_id   bigint REFERENCES bps.inv_ingredients(ingredient_id) ON DELETE SET NULL,
  vendor_sku      text   CONSTRAINT chk_po_vendor_items_sku CHECK (length(vendor_sku) <= 50),
  description     text   NOT NULL CONSTRAINT chk_po_vendor_items_desc CHECK (btrim(description) <> '' AND length(description) <= 150),
  pack_qty        numeric(12,4) NOT NULL DEFAULT 1 CONSTRAINT chk_po_vendor_items_pack_qty CHECK (pack_qty > 0),
  pack_unit       text   NOT NULL DEFAULT 'ea' CONSTRAINT chk_po_vendor_items_pack_unit CHECK (pack_unit IN ('g', 'kg', 'oz', 'lb', 'ml', 'l', 'fl_oz', 'gal', 'ea')),
  pack_label      text   CONSTRAINT chk_po_vendor_items_pack_label CHECK (length(pack_label) <= 30),
  pack_price      numeric(12,4) CONSTRAINT chk_po_vendor_items_price CHECK (pack_price >= 0),
  price_date      date,
  min_order_qty   numeric(12,2) CONSTRAINT chk_po_vendor_items_min CHECK (min_order_qty > 0),
  is_preferred    boolean NOT NULL DEFAULT false,
  notes           text   CONSTRAINT chk_po_vendor_items_notes CHECK (length(notes) <= 500),
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      bigint,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      bigint,
  CONSTRAINT chk_po_vendor_items_ingredient CHECK (ingredient_id IS NULL OR item_kind = 'INGREDIENT'),
  CONSTRAINT chk_po_vendor_items_preferred CHECK (NOT is_preferred OR ingredient_id IS NOT NULL)
);
COMMENT ON TABLE bps.po_vendor_items IS 'What a tenant buys from a vendor: SKU, pack and price. Ingredient items may point to the recipe ingredient they supply.';
COMMENT ON COLUMN bps.po_vendor_items.item_kind IS 'INGREDIENT (food, may link to inv_ingredients), PACKAGING (bags, boxes, labels), SUPPLY (cleaning, paper...).';
COMMENT ON COLUMN bps.po_vendor_items.pack_qty IS 'How much one pack holds, in pack_unit (a 50 lb bag = 50 lb; a case of 500 bags = 500 ea).';
COMMENT ON COLUMN bps.po_vendor_items.pack_label IS 'What the pack is called (bag, case, pail, box).';
COMMENT ON COLUMN bps.po_vendor_items.pack_price IS 'Current price of one pack in the vendor''s currency. NULL = no price yet. Changes are kept in po_vendor_item_prices.';
COMMENT ON COLUMN bps.po_vendor_items.price_date IS 'Date the current pack price took effect.';
COMMENT ON COLUMN bps.po_vendor_items.is_preferred IS 'The preferred source of its ingredient (at most one active preferred item per ingredient).';
CREATE INDEX IF NOT EXISTS ix_po_vendor_items_vendor ON bps.po_vendor_items (vendor_id);
CREATE INDEX IF NOT EXISTS ix_po_vendor_items_ingredient ON bps.po_vendor_items (ingredient_id) WHERE ingredient_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_po_vendor_items_sku ON bps.po_vendor_items (vendor_id, lower(vendor_sku)) WHERE vendor_sku IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_po_vendor_items_preferred ON bps.po_vendor_items (tenant_id, ingredient_id) WHERE is_preferred AND is_active;

-- ---------- price history ----------
CREATE TABLE IF NOT EXISTS bps.po_vendor_item_prices (
  vendor_item_price_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  vendor_item_id  bigint NOT NULL REFERENCES bps.po_vendor_items(vendor_item_id) ON DELETE CASCADE,
  pack_price      numeric(12,4) NOT NULL CONSTRAINT chk_po_vendor_item_prices_price CHECK (pack_price >= 0),
  effective_date  date   NOT NULL,
  price_source    text   NOT NULL DEFAULT 'MANUAL' CONSTRAINT chk_po_vendor_item_prices_source CHECK (price_source IN ('MANUAL', 'RECEIPT')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      bigint
);
COMMENT ON TABLE bps.po_vendor_item_prices IS 'Every price a vendor item has had: pack price, the date it took effect and where it came from.';
CREATE INDEX IF NOT EXISTS ix_po_vendor_item_prices_item ON bps.po_vendor_item_prices (vendor_item_id, effective_date DESC);

DO $$
DECLARE tbl text; pk text;
BEGIN
  FOR tbl, pk IN VALUES ('po_vendors', 'vendor_id'), ('po_vendor_items', 'vendor_item_id') LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_set_updated ON bps.%I', tbl, tbl);
    EXECUTE format('CREATE TRIGGER trg_%s_set_updated BEFORE UPDATE ON bps.%I FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only()', tbl, tbl);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_audit ON bps.%I', tbl, tbl);
    EXECUTE format('CREATE TRIGGER trg_%s_audit AFTER INSERT OR DELETE OR UPDATE ON bps.%I FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log(%L)', tbl, tbl, pk);
  END LOOP;
END $$;

-- ---------- row security (the po_* functions are SECURITY DEFINER and check access themselves) ----------
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['po_vendors', 'po_vendor_items', 'po_vendor_item_prices'] LOOP
    EXECUTE format('ALTER TABLE bps.%I ENABLE ROW LEVEL SECURITY', tbl);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON bps.%I TO authenticated', tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_read ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_read ON bps.%I FOR SELECT TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('purchasing.vendors', 'R'))))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_insert ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_insert ON bps.%I FOR INSERT TO authenticated WITH CHECK (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('purchasing.vendors', 'W'))))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_update ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_update ON bps.%I FOR UPDATE TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('purchasing.vendors', 'W'))))
      WITH CHECK ((SELECT bps.fnd_is_trusted()) OR tenant_id = (SELECT bps.fnd_active_tenant_id()))$p$, tbl, tbl);
    EXECUTE format('DROP POLICY IF EXISTS pol_%s_delete ON bps.%I', tbl, tbl);
    EXECUTE format($p$CREATE POLICY pol_%s_delete ON bps.%I FOR DELETE TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('purchasing.vendors', 'D'))))$p$, tbl, tbl);
  END LOOP;
END $$;
