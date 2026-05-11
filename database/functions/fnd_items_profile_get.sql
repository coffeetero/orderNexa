-- ============================================================
-- fnd_items_profile_get
--
-- Two modes controlled by p_item_id:
--
--   p_item_id IS NULL  → slim list (id, number, name, is_active)
--                         used to populate the search combobox on mount
--
--   p_item_id IS NOT NULL → full detail for one item
--                           joins fnd_items + bps_items
--                           used when a user selects an item in the UI
--
-- Prerequisites: fnd_items.sql, bps_items.sql
-- ============================================================

DROP FUNCTION IF EXISTS bps.fnd_items_profile_get(BIGINT, BOOLEAN, BIGINT);

CREATE OR REPLACE FUNCTION bps.fnd_items_profile_get(
    p_tenant_id     BIGINT,
    p_inactive_only BOOLEAN DEFAULT FALSE,
    p_item_id       BIGINT  DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = bps, public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- --------------------------------------------------------
    -- Slim list mode: combobox population on page load
    -- --------------------------------------------------------
    IF p_item_id IS NULL THEN
        SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'item_number')), '[]'::JSONB)
          INTO v_result
          FROM (
            SELECT jsonb_build_object(
                'item_id',     i.item_id,
                'item_number', COALESCE(i.item_number, ''),
                'item_name',   i.item_name,
                'is_active',   i.is_active
            ) AS row_data
              FROM fnd_items i
             WHERE i.tenant_id = p_tenant_id
               AND (
                    (p_inactive_only AND i.is_active = FALSE)
                 OR (NOT p_inactive_only)
               )
        ) sub;

        RETURN v_result;
    END IF;

    -- --------------------------------------------------------
    -- Detail mode: full profile for a single item
    -- --------------------------------------------------------
    SELECT jsonb_build_object(
        -- Identity
        'item_id',              i.item_id,
        'item_number',          COALESCE(i.item_number, ''),
        'item_name',            i.item_name,
        'item_description',     i.item_description,
        -- Classification
        'category',             i.category,
        'unit_of_sale',         i.unit_of_sale,
        -- Weight
        'item_weight',          i.item_weight,
        'weight_uom',           i.weight_uom,
        -- Box / packaging
        'box_qty_per_box',      i.box_qty_per_box,
        'box_capacity_weight',  i.box_capacity_weight,
        'box_capacity_optimal', i.box_capacity_optimal,
        -- Sales
        'sales_terms_apply',    i.sales_terms_apply,
        'is_active',            i.is_active,
        -- Prep options (stored as JSONB text arrays in fnd_items)
        'allowed_prep_options', i.allowed_prep_options,
        'default_prep_options', i.default_prep_options,
        -- bps_items: product characteristics
        'dough_type',           b.dough_type,
        'shape',                b.shape,
        'packing',              b.packing,
        -- bps_items: production settings
        'machine_setting',      b.machine_setting,
        'sheeter_setting',      b.sheeter_setting,
        'weight_adjuster',      COALESCE(b.weight_adjuster, 0),
        'scale_weight',         COALESCE(b.scale_weight, 0),
        'scale_qty',            COALESCE(b.scale_qty, 0)
    )
      INTO v_result
      FROM fnd_items i
      LEFT JOIN bps_items b ON b.item_id = i.item_id
     WHERE i.tenant_id = p_tenant_id
       AND i.item_id   = p_item_id
     LIMIT 1;

    RETURN COALESCE(v_result, 'null'::JSONB);
END;
$$;
