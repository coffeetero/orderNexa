-- ============================================================
-- po_vendor_items_get
-- Vendor items with their vendor, ingredient and cost per unit worked out from the pack price:
--   weights  cost_per_lb, cost_per_kg      volumes  cost_per_l, cost_per_gal      each  cost_per_ea
-- p_vendor_id NULL = every vendor's items (Purchasing › Vendor Items); otherwise one vendor's (its Items tab).
-- Ordered by vendor, then description.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_vendor_items_get(p_tenant_id bigint, p_vendor_id bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'R');
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'vendor_item_id', i.vendor_item_id, 'vendor_id', i.vendor_id, 'vendor_code', v.vendor_code, 'vendor_name', v.vendor_name,
             'vendor_active', v.is_active, 'item_kind', i.item_kind, 'ingredient_id', i.ingredient_id, 'ingredient_name', g.ingredient_name,
             'vendor_sku', i.vendor_sku, 'description', i.description, 'pack_qty', i.pack_qty, 'pack_unit', i.pack_unit,
             'pack_label', i.pack_label, 'pack_price', i.pack_price, 'price_date', to_char(i.price_date, 'MM/DD/YYYY'),
             'price_date_iso', i.price_date, 'min_order_qty', i.min_order_qty, 'is_preferred', i.is_preferred, 'notes', i.notes,
             'is_active', i.is_active, 'currency_code', v.currency_code,
             'cost_per_lb',  CASE WHEN i.pack_unit IN ('g','kg','oz','lb') THEN round(i.pack_price / (i.pack_qty * po_unit_base(i.pack_unit) / 453.59237), 4) END,
             'cost_per_kg',  CASE WHEN i.pack_unit IN ('g','kg','oz','lb') THEN round(i.pack_price / (i.pack_qty * po_unit_base(i.pack_unit) / 1000), 4) END,
             'cost_per_l',   CASE WHEN i.pack_unit IN ('ml','l','fl_oz','gal') THEN round(i.pack_price / (i.pack_qty * po_unit_base(i.pack_unit) / 1000), 4) END,
             'cost_per_gal', CASE WHEN i.pack_unit IN ('ml','l','fl_oz','gal') THEN round(i.pack_price / (i.pack_qty * po_unit_base(i.pack_unit) / 3785.411784), 4) END,
             'cost_per_ea',  CASE WHEN i.pack_unit = 'ea' THEN round(i.pack_price / i.pack_qty, 4) END,
             'price_changes', (SELECT count(*) FROM po_vendor_item_prices p WHERE p.vendor_item_id = i.vendor_item_id))
           ORDER BY lower(v.vendor_name), lower(i.description))
      FROM po_vendor_items i
      JOIN po_vendors v ON v.vendor_id = i.vendor_id
      LEFT JOIN inv_ingredients g ON g.ingredient_id = i.ingredient_id
     WHERE i.tenant_id = p_tenant_id AND (p_vendor_id IS NULL OR i.vendor_id = p_vendor_id)), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_vendor_items_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_vendor_items_get(bigint, bigint) TO authenticated, service_role, bps_dev;
