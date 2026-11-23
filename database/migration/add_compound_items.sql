-- Compound items: an item made from other items (e.g. a gift basket). Two levels only: a compound item holds simple items.
-- New column: fnd_items.is_compound. Components live in the existing fnd_item_bom (parent_item_id, item_id, quantity).
-- Run, then load database/functions/fnd_items_profile_get.sql and fnd_items_profile_save.sql (they now carry is_compound).
SET search_path = bps, public;

-- Also fnd_items.last_ordered_date: the latest production date of an order with this item, refreshed nightly (health check) by
-- fnd_items_last_ordered_refresh; the Item list's Stale filter reads it.
ALTER TABLE bps.fnd_items ADD COLUMN is_compound boolean NOT NULL DEFAULT false, ADD COLUMN last_ordered_date date;

-- Items that already have components are compound.
UPDATE bps.fnd_items SET is_compound = true WHERE item_id IN (SELECT parent_item_id FROM bps.fnd_item_bom);

-- A component row needs a compound parent and a simple component, in the same company.
CREATE OR REPLACE FUNCTION bps.fnd_item_bom_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_items WHERE item_id = NEW.parent_item_id AND tenant_id = NEW.tenant_id AND is_compound) THEN
    RAISE EXCEPTION 'Only a compound item can have components';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_items WHERE item_id = NEW.item_id AND tenant_id = NEW.tenant_id AND NOT is_compound) THEN
    RAISE EXCEPTION 'A component must be a simple item, not another compound item';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_item_bom_guard() FROM PUBLIC, anon;
CREATE TRIGGER trg_fnd_item_bom_guard BEFORE INSERT OR UPDATE ON bps.fnd_item_bom
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_item_bom_guard();

-- Keeps the two levels intact when the flag changes.
CREATE OR REPLACE FUNCTION bps.fnd_items_compound_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  IF OLD.is_compound AND NOT NEW.is_compound AND EXISTS (SELECT 1 FROM bps.fnd_item_bom WHERE parent_item_id = NEW.item_id) THEN
    RAISE EXCEPTION 'Remove this item''s components before turning off Compound item';
  END IF;
  IF NEW.is_compound AND NOT OLD.is_compound AND EXISTS (SELECT 1 FROM bps.fnd_item_bom WHERE item_id = NEW.item_id) THEN
    RAISE EXCEPTION 'This item is a component of a compound item, so it cannot be compound itself';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_items_compound_guard() FROM PUBLIC, anon;
CREATE TRIGGER trg_fnd_items_compound_guard BEFORE UPDATE OF is_compound ON bps.fnd_items
  FOR EACH ROW WHEN (OLD.is_compound IS DISTINCT FROM NEW.is_compound) EXECUTE FUNCTION bps.fnd_items_compound_guard();

-- Components of a compound item.
CREATE OR REPLACE FUNCTION bps.fnd_item_components_get(p_tenant_id bigint, p_item_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('item_id', c.item_id, 'item_number', COALESCE(c.item_number, ''), 'item_name', c.item_name,
      'is_active', c.is_active, 'quantity', b.quantity) ORDER BY c.item_number)
    FROM bps.fnd_item_bom b JOIN bps.fnd_items c ON c.item_id = b.item_id
   WHERE b.tenant_id = p_tenant_id AND b.parent_item_id = p_item_id), '[]'::jsonb);
END $$;

-- p_entries: [{item_id, quantity}], the full list: components not listed are removed.
CREATE OR REPLACE FUNCTION bps.fnd_item_components_set(p_tenant_id bigint, p_item_id bigint, p_entries jsonb) RETURNS integer
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE e jsonb; n int := 0; v_item bigint; v_qty numeric; v_ids bigint[] := '{}';
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_items WHERE item_id = p_item_id AND tenant_id = p_tenant_id) THEN RAISE EXCEPTION 'Item not found'; END IF;
  FOR e IN SELECT * FROM jsonb_array_elements(COALESCE(p_entries, '[]'::jsonb)) LOOP
    v_item := (e ->> 'item_id')::bigint;
    v_qty := NULLIF(btrim(e ->> 'quantity'), '')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Every component needs a quantity above 0'; END IF;
    IF v_item = p_item_id THEN RAISE EXCEPTION 'An item cannot be its own component'; END IF;
    IF v_item = ANY (v_ids) THEN RAISE EXCEPTION 'Each component can be listed only once'; END IF;
    v_ids := v_ids || v_item;
    UPDATE bps.fnd_item_bom SET quantity = v_qty WHERE tenant_id = p_tenant_id AND parent_item_id = p_item_id AND item_id = v_item;
    IF NOT FOUND THEN
      INSERT INTO bps.fnd_item_bom (tenant_id, parent_item_id, item_id, quantity) VALUES (p_tenant_id, p_item_id, v_item, v_qty);
    END IF;
    n := n + 1;
  END LOOP;
  DELETE FROM bps.fnd_item_bom WHERE tenant_id = p_tenant_id AND parent_item_id = p_item_id AND NOT (item_id = ANY (v_ids));
  RETURN n;
END $$;

REVOKE EXECUTE ON FUNCTION bps.fnd_item_components_get(bigint, bigint), bps.fnd_item_components_set(bigint, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_item_components_get(bigint, bigint), bps.fnd_item_components_set(bigint, bigint, jsonb) TO authenticated, service_role, bps_dev;

-- Sets each item's last_ordered_date from the order lines. One pass; meant to run nightly. Returns how many items changed.
CREATE OR REPLACE FUNCTION bps.fnd_items_last_ordered_refresh(p_tenant_id bigint) RETURNS integer
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE n integer;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  WITH used AS (
    SELECT l.item_id, max(o.production_date) AS d
      FROM bps.om_order_lines l JOIN bps.om_orders o ON o.order_id = l.order_id
     WHERE o.tenant_id = p_tenant_id
     GROUP BY l.item_id)
  UPDATE bps.fnd_items i SET last_ordered_date = u.d
    FROM (SELECT it.item_id, used.d FROM bps.fnd_items it LEFT JOIN used ON used.item_id = it.item_id WHERE it.tenant_id = p_tenant_id) u
   WHERE i.item_id = u.item_id AND i.last_ordered_date IS DISTINCT FROM u.d;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_items_last_ordered_refresh(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_items_last_ordered_refresh(bigint) TO authenticated, service_role, bps_dev;

-- First fill for every company.
SELECT bps.fnd_items_last_ordered_refresh(tenant_id) FROM bps.fnd_tenants;
