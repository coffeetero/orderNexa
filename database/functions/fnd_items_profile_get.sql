-- ============================================================
-- fnd_items_profile_get
--
-- Two modes controlled by p_item_id:
--
--   p_item_id IS NULL  → slim list (id, number, name, is_active)
--                         used to populate the search combobox on mount
--
--   p_item_id IS NOT NULL → full detail for one item (all fnd_items columns)
--                           used when a user selects an item in the UI
--
-- Prerequisites: fnd_items.sql
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
        -- Prep options (JSONB text arrays)
        'allowed_prep_options', i.allowed_prep_options,
        'default_prep_options', i.default_prep_options,
        -- Product characteristics
        'dough_type',           i.dough_type,
        'shape',                i.shape,
        'packing',              i.packing,
        -- Production settings
        'machine_setting',      i.machine_setting,
        'sheeter_setting',      i.sheeter_setting,
        'weight_adjuster',      COALESCE(i.weight_adjuster, 0),
        'scale_weight',         COALESCE(i.scale_weight, 0),
        'scale_qty',            COALESCE(i.scale_qty, 0)
    )
      INTO v_result
      FROM fnd_items i
     WHERE i.tenant_id = p_tenant_id
       AND i.item_id   = p_item_id
     LIMIT 1;

    RETURN COALESCE(v_result, 'null'::JSONB);
END;
$$;
