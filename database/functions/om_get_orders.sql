-- ============================================================
-- om_get_orders
-- Fetches order data for the order entry / management screens.
--
--   p_order_id = NULL  → list mode: returns array of order headers
--                         (filtered by customer and/or delivery date range)
--   p_order_id = <id>  → detail mode: returns single order object with
--                         lines array (for editing)
--
-- Prerequisites: add_order_entry_fields.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_get_orders(
    p_tenant_id          BIGINT,
    p_order_id           BIGINT  DEFAULT NULL,
    p_customer_id        BIGINT  DEFAULT NULL,
    p_delivery_date_from DATE    DEFAULT NULL,
    p_delivery_date_to   DATE    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── Detail mode: single order + lines ─────────────────────────────────
    IF p_order_id IS NOT NULL THEN

        SELECT jsonb_build_object(
            'order_id',        o.order_id,
            'order_number',    o.order_number,
            'order_date',      o.order_date,
            'delivery_date',   o.delivery_date,
            'delivery_window', o.delivery_window,
            'delivery_amount', COALESCE(o.delivery_amount, 0),
            'amount',          o.amount,
            'discount_amount', o.discount_amount,
            'customer_id',     o.customer_id,
            'customer_name',   COALESCE(c.customer_name,
                                        o.snapshot_data->>'cus_name', ''),
            'snapshot_data',   o.snapshot_data,
            'lines',           COALESCE(lines_agg.lines, '[]'::JSONB)
        )
          INTO v_result
          FROM om_orders o
          LEFT JOIN fnd_customers c
                 ON c.customer_id = o.customer_id
                AND c.tenant_id   = o.tenant_id
          LEFT JOIN LATERAL (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'order_line_id',   l.order_line_id,
                        'item_id',         l.item_id,
                        'item_number',     COALESCE(i.item_number, ''),
                        'item_description',l.item_description,
                        'quantity',        l.quantity,
                        'unit_price',      COALESCE(l.unit_price, 0),
                        'unit_discount',   l.unit_discount,
                        'extended_amount', COALESCE(l.extended_amount, 0),
                        'is_sliced',       COALESCE(l.is_sliced,  FALSE),
                        'is_wrapped',      COALESCE(l.is_wrapped, FALSE),
                        'is_covered',      COALESCE(l.is_covered, FALSE),
                        'is_scored',       COALESCE(l.is_scored,  FALSE),
                        -- Capabilities from bps_items for UI checkbox enabling
                        'can_slice',       COALESCE(b.is_sliceable, FALSE),
                        'can_wrap',        COALESCE(b.is_wrappable,  FALSE),
                        'can_cover',       COALESCE(b.is_coverable,  FALSE),
                        'can_score',       COALESCE(b.is_scoreable,  FALSE)
                    )
                    ORDER BY l.order_line_id
                ) AS lines
                  FROM om_order_lines l
                  LEFT JOIN fnd_items  i ON i.item_id = l.item_id
                  LEFT JOIN bps_items  b ON b.item_id = l.item_id
                 WHERE l.order_id  = o.order_id
                   AND l.tenant_id = o.tenant_id
               ) lines_agg ON TRUE
         WHERE o.order_id  = p_order_id
           AND o.tenant_id = p_tenant_id;

        RETURN COALESCE(v_result, 'null'::JSONB);
    END IF;

    -- ── List mode: order headers (no lines) ───────────────────────────────
    SELECT jsonb_agg(row_data ORDER BY o.delivery_date DESC, o.order_id DESC)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'order_id',        o.order_id,
            'order_number',    o.order_number,
            'order_date',      o.order_date,
            'delivery_date',   o.delivery_date,
            'delivery_window', o.delivery_window,
            'delivery_amount', COALESCE(o.delivery_amount, 0),
            'amount',          o.amount,
            'discount_amount', o.discount_amount,
            'customer_id',     o.customer_id,
            'customer_name',   COALESCE(c.customer_name,
                                        o.snapshot_data->>'cus_name', '')
        ) AS row_data
          FROM om_orders o
          LEFT JOIN fnd_customers c
                 ON c.customer_id = o.customer_id
                AND c.tenant_id   = o.tenant_id
         WHERE o.tenant_id = p_tenant_id
           AND (p_customer_id        IS NULL OR o.customer_id   = p_customer_id)
           AND (p_delivery_date_from IS NULL OR o.delivery_date >= p_delivery_date_from)
           AND (p_delivery_date_to   IS NULL OR o.delivery_date <= p_delivery_date_to)
         ORDER BY o.delivery_date DESC, o.order_id DESC
         LIMIT 500
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
