-- ============================================================
-- om_get_items_for_order
-- Returns the active item catalogue for a tenant with:
--   - bps_items preparation capabilities and defaults
--   - effective unit_price from the customer's active pricebook
--     (lowest min_quantity tier; NULL when no pricebook is found)
--
-- Prerequisites: add_order_entry_fields.sql (is_scoreable, default_scored)
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_get_items_for_order(
    p_tenant_id   BIGINT,
    p_customer_id BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_pricebook_id BIGINT;
    v_result       JSONB;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- Resolve customer's active pricebook (PRIMARY preferred, then first active)
    IF p_customer_id IS NOT NULL THEN
        SELECT cp.pricebook_id
          INTO v_pricebook_id
          FROM fnd_customer_pricebooks cp
         WHERE cp.customer_id         = p_customer_id
           AND cp.tenant_id           = p_tenant_id
           AND cp.is_active           = TRUE
           AND cp.effective_start_date <= CURRENT_DATE
           AND (cp.effective_end_date IS NULL OR cp.effective_end_date >= CURRENT_DATE)
         ORDER BY
               CASE WHEN cp.assignment_type = 'PRIMARY' THEN 0 ELSE 1 END,
               cp.effective_start_date DESC
         LIMIT 1;
    END IF;

    SELECT jsonb_agg(row_data ORDER BY (row_data->>'item_number'))
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'item_id',        i.item_id,
            'item_number',    COALESCE(i.item_number, ''),
            'item_name',      i.item_name,
            'category',       i.category,
            'unit_of_sale',   i.unit_of_sale,
            -- Prep capabilities
            'is_sliceable',   COALESCE(b.is_sliceable,   FALSE),
            'is_wrappable',   COALESCE(b.is_wrappable,   FALSE),
            'is_coverable',   COALESCE(b.is_coverable,   FALSE),
            -- is_scoreable / default_scored require add_order_entry_fields.sql to be run first;
            -- hardcoded to FALSE until that migration is deployed.
            'is_scoreable',   FALSE,
            -- Prep defaults (applied to new order line on item select)
            'default_sliced', COALESCE(b.default_sliced, FALSE),
            'default_wrapped',COALESCE(b.default_wrapped,FALSE),
            'default_covered',COALESCE(b.default_covered,FALSE),
            'default_scored', FALSE,
            -- Effective price (NULL when no pricebook resolved)
            'unit_price',     pi.item_price
        ) AS row_data
          FROM fnd_items i
          LEFT JOIN bps_items b ON b.item_id = i.item_id
          LEFT JOIN LATERAL (
                SELECT p.item_price
                  FROM fnd_pricebook_items p
                 WHERE p.item_id      = i.item_id
                   AND p.pricebook_id = v_pricebook_id
                   AND p.is_active    = TRUE
                   AND p.tenant_id    = p_tenant_id
                 ORDER BY p.min_quantity ASC
                 LIMIT 1
               ) pi ON TRUE
         WHERE i.tenant_id  = p_tenant_id
           AND i.is_active  = TRUE
         LIMIT 2000
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
