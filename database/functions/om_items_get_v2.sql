-- ============================================================
-- om_items_get_v2 — RLS-respecting version (no SECURITY DEFINER)
-- Returns the item catalogue for a tenant with:
--   - JSONB item prep allowed/default options
--   - effective unit_price from the customer's active pricebook
--     (lowest min_quantity tier; NULL when no pricebook is found)
--   - active-only filtering by default, with an opt-out parameter
--
-- Prerequisites: add_order_entry_fields.sql (is_scoreable, default_scored)
-- ============================================================

DROP FUNCTION IF EXISTS bps.om_items_get_v2(BIGINT, BIGINT, BOOLEAN);

CREATE OR REPLACE FUNCTION bps.om_items_get_v2(
    p_tenant_id   BIGINT,
    p_customer_id BIGINT DEFAULT NULL,
    p_return_actives_only BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
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
            'allowed_prep_options', COALESCE(prep_allowed.allowed_prep_options, '[]'::JSONB),
            'default_prep_options', COALESCE(prep_default.default_prep_options, '[]'::JSONB),
            -- is_scoreable / default_scored require add_order_entry_fields.sql to be run first;
            -- hardcoded to FALSE until that migration is deployed.
            'is_scoreable',   FALSE,
            'default_scored', FALSE,
            -- Effective price (NULL when no pricebook resolved)
            'unit_price',     pi.item_price
        ) AS row_data
          FROM fnd_items i
          LEFT JOIN LATERAL (
                SELECT COALESCE(
                    jsonb_agg(
                        jsonb_build_object(
                            'value', vv.value,
                            'label', vv.label
                        )
                        ORDER BY vv.display_order, vv.label
                    ),
                    '[]'::JSONB
                ) AS allowed_prep_options
                  FROM jsonb_array_elements_text(COALESCE(i.allowed_prep_options, '[]'::JSONB)) opt(value)
                  JOIN fnd_valuesets vs
                    ON vs.tenant_id = i.tenant_id
                   AND vs.valueset_code = 'ITEMPREP'
                   AND vs.is_active = TRUE
                  JOIN fnd_valueset_values vv
                    ON vv.tenant_id = vs.tenant_id
                   AND vv.valueset_id = vs.valueset_id
                   AND vv.value = opt.value
                   AND vv.is_disabled = FALSE
              ) prep_allowed ON TRUE
          LEFT JOIN LATERAL (
                SELECT COALESCE(
                    jsonb_agg(
                        jsonb_build_object(
                            'value', vv.value,
                            'label', vv.label
                        )
                        ORDER BY vv.display_order, vv.label
                    ),
                    '[]'::JSONB
                ) AS default_prep_options
                  FROM jsonb_array_elements_text(COALESCE(i.default_prep_options, '[]'::JSONB)) opt(value)
                  JOIN fnd_valuesets vs
                    ON vs.tenant_id = i.tenant_id
                   AND vs.valueset_code = 'ITEMPREP'
                   AND vs.is_active = TRUE
                  JOIN fnd_valueset_values vv
                    ON vv.tenant_id = vs.tenant_id
                   AND vv.valueset_id = vs.valueset_id
                   AND vv.value = opt.value
                   AND vv.is_disabled = FALSE
              ) prep_default ON TRUE
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
           AND (NOT p_return_actives_only OR i.is_active = TRUE)
         LIMIT 2000
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
