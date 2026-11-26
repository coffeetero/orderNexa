-- ============================================================
-- po_vendor_item_save
-- Creates or updates one vendor item. A new or changed pack price is added to the price history (po_vendor_item_prices)
-- with its date (today when not given). Marking an item preferred clears the preferred flag of the other items of the
-- same ingredient. Returns the item as po_vendor_items_get lists it.
-- p_item: { vendor_item_id (omit for new), vendor_id, item_kind INGREDIENT|PACKAGING|SUPPLY, ingredient_id, vendor_sku,
--   description, pack_qty, pack_unit g|kg|oz|lb|ml|l|fl_oz|gal|ea, pack_label, pack_price (blank = no price),
--   price_date (YYYY-MM-DD), min_order_qty, is_preferred, notes, is_active }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_vendor_item_save(p_tenant_id bigint, p_item jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user   bigint := bps.fnd_current_user_id();
  v_id     bigint := NULLIF(p_item ->> 'vendor_item_id', '')::bigint;
  v_vendor bigint := NULLIF(p_item ->> 'vendor_id', '')::bigint;
  v_kind   text := upper(COALESCE(NULLIF(p_item ->> 'item_kind', ''), 'INGREDIENT'));
  v_ing    bigint := NULLIF(p_item ->> 'ingredient_id', '')::bigint;
  v_sku    text := NULLIF(btrim(p_item ->> 'vendor_sku'), '');
  v_desc   text := NULLIF(btrim(p_item ->> 'description'), '');
  v_qty    numeric := NULLIF(btrim(p_item ->> 'pack_qty'), '')::numeric;
  v_unit   text := lower(COALESCE(NULLIF(p_item ->> 'pack_unit', ''), 'ea'));
  v_label  text := NULLIF(btrim(p_item ->> 'pack_label'), '');
  v_price  numeric := NULLIF(btrim(p_item ->> 'pack_price'), '')::numeric;
  v_pdate  date := NULLIF(btrim(p_item ->> 'price_date'), '')::date;
  v_minq   numeric := NULLIF(btrim(p_item ->> 'min_order_qty'), '')::numeric;
  v_pref   boolean := COALESCE((p_item ->> 'is_preferred')::boolean, false);
  v_notes  text := NULLIF(btrim(p_item ->> 'notes'), '');
  v_act    boolean := COALESCE((p_item ->> 'is_active')::boolean, true);
  v_old    po_vendor_items;
  v_today  date := (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date;
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'W');
  IF v_id IS NOT NULL THEN
    SELECT * INTO v_old FROM po_vendor_items WHERE tenant_id = p_tenant_id AND vendor_item_id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vendor item not found'; END IF;
  END IF;
  IF v_vendor IS NULL OR NOT EXISTS (SELECT 1 FROM po_vendors WHERE tenant_id = p_tenant_id AND vendor_id = v_vendor) THEN
    RAISE EXCEPTION 'Pick the vendor';
  END IF;
  IF v_kind NOT IN ('INGREDIENT', 'PACKAGING', 'SUPPLY') THEN RAISE EXCEPTION 'Unknown item kind %', v_kind; END IF;
  IF v_ing IS NOT NULL AND v_kind <> 'INGREDIENT' THEN RAISE EXCEPTION 'Only ingredient items link to a recipe ingredient'; END IF;
  IF v_ing IS NOT NULL AND NOT EXISTS (SELECT 1 FROM inv_ingredients WHERE tenant_id = p_tenant_id AND ingredient_id = v_ing) THEN
    RAISE EXCEPTION 'Ingredient not found';
  END IF;
  IF v_desc IS NULL THEN RAISE EXCEPTION 'Describe the item'; END IF;
  IF length(v_desc) > 150 THEN RAISE EXCEPTION 'The description is limited to 150 characters'; END IF;
  IF length(v_sku) > 50 THEN RAISE EXCEPTION 'The vendor SKU is limited to 50 characters'; END IF;
  IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Enter how much one pack holds'; END IF;
  IF bps.po_unit_base(v_unit) IS NULL THEN RAISE EXCEPTION 'Unknown pack unit %', v_unit; END IF;
  IF length(v_label) > 30 THEN RAISE EXCEPTION 'The pack name is limited to 30 characters'; END IF;
  IF v_price < 0 THEN RAISE EXCEPTION 'The price cannot be negative'; END IF;
  IF v_minq <= 0 THEN RAISE EXCEPTION 'The minimum order is above 0'; END IF;
  IF v_pref AND v_ing IS NULL THEN RAISE EXCEPTION 'Link an ingredient to make this its preferred source'; END IF;
  IF length(v_notes) > 500 THEN RAISE EXCEPTION 'Notes are limited to 500 characters'; END IF;
  IF v_sku IS NOT NULL AND EXISTS (SELECT 1 FROM po_vendor_items WHERE vendor_id = v_vendor AND lower(vendor_sku) = lower(v_sku) AND vendor_item_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'This vendor already has an item with SKU %', v_sku;
  END IF;

  -- The price date follows the price: today for a new or changed price unless one is given; kept when the price is unchanged.
  IF v_price IS NULL THEN v_pdate := NULL;
  ELSIF v_pdate IS NULL THEN
    v_pdate := CASE WHEN v_id IS NOT NULL AND v_old.pack_price IS NOT DISTINCT FROM v_price THEN v_old.price_date ELSE v_today END;
  END IF;

  IF v_pref AND v_act THEN
    UPDATE po_vendor_items SET is_preferred = false, updated_by = v_user
     WHERE tenant_id = p_tenant_id AND ingredient_id = v_ing AND is_preferred AND vendor_item_id IS DISTINCT FROM v_id;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO po_vendor_items (tenant_id, vendor_id, item_kind, ingredient_id, vendor_sku, description, pack_qty, pack_unit, pack_label,
                                 pack_price, price_date, min_order_qty, is_preferred, notes, is_active, created_by, updated_by)
    VALUES (p_tenant_id, v_vendor, v_kind, v_ing, v_sku, v_desc, v_qty, v_unit, v_label, v_price, v_pdate, v_minq, v_pref, v_notes, v_act, v_user, v_user)
    RETURNING vendor_item_id INTO v_id;
  ELSE
    UPDATE po_vendor_items SET vendor_id = v_vendor, item_kind = v_kind, ingredient_id = v_ing, vendor_sku = v_sku, description = v_desc,
                               pack_qty = v_qty, pack_unit = v_unit, pack_label = v_label, pack_price = v_price, price_date = v_pdate,
                               min_order_qty = v_minq, is_preferred = v_pref, notes = v_notes, is_active = v_act, updated_by = v_user
     WHERE vendor_item_id = v_id;
  END IF;

  IF v_price IS NOT NULL AND (v_old.vendor_item_id IS NULL OR v_old.pack_price IS DISTINCT FROM v_price OR v_old.price_date IS DISTINCT FROM v_pdate) THEN
    INSERT INTO po_vendor_item_prices (tenant_id, vendor_item_id, pack_price, effective_date, price_source, created_by)
    VALUES (p_tenant_id, v_id, v_price, v_pdate, 'MANUAL', v_user);
  END IF;

  RETURN (SELECT x FROM jsonb_array_elements(bps.po_vendor_items_get(p_tenant_id, v_vendor)) x WHERE (x ->> 'vendor_item_id')::bigint = v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_vendor_item_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_vendor_item_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
