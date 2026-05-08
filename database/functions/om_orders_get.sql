-- ============================================================
-- om_orders_get
-- Fetches order data for the order entry / management screens.
--
--   p_order_id = NULL  → list mode: returns array of order headers
--                         (filtered by customer, optional production date range,
--                         optional production_code / production time).
--                         List payload is always headers-only; p_return_headers_only
--                         is ignored in this branch.
--   p_order_id = <id>  → detail mode: returns single order object.
--                         When p_return_headers_only is TRUE, lines is '[]'::jsonb
--                         and line aggregation is skipped. When FALSE, lines are
--                         populated as today.
--
-- Scoring fields are intentionally returned as FALSE until the item/order-line
-- scoring columns are added to the deployed schema.
-- ============================================================

DROP FUNCTION IF EXISTS bps.om_orders_get(BIGINT, BIGINT, BIGINT, DATE, DATE, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS bps.om_orders_get(BIGINT, BIGINT, BIGINT, DATE, DATE, TEXT, BOOLEAN, BOOLEAN);
DROP FUNCTION IF EXISTS bps.om_orders_get(BIGINT, BIGINT, BIGINT, DATE, DATE);

CREATE OR REPLACE FUNCTION bps.om_orders_get(
    p_tenant_id               BIGINT,
    p_order_id                BIGINT   DEFAULT NULL,
    p_customer_id             BIGINT   DEFAULT NULL,
    p_production_date_from    DATE     DEFAULT NULL,
    p_production_date_to      DATE     DEFAULT NULL,
    p_production_code         TEXT     DEFAULT NULL,
    p_return_headers_only     BOOLEAN  DEFAULT TRUE,
    p_return_actives_only     BOOLEAN  DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_result JSONB;
    v_lookup_customer_id BIGINT;
    v_production_code TEXT;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── Detail mode: single order (+ lines unless headers-only) ───────────
    IF p_order_id IS NOT NULL THEN

        IF p_return_headers_only THEN
            SELECT jsonb_build_object(
                'order_id',        o.order_id,
                'order_number',    o.order_number,
                'order_date',      o.order_date,
                'production_date', o.production_date,
                'production_code', o.production_code,
                'delivery_amount', 0,
                'department_event',  o.department_event,
                'amount',          o.amount,
                'discount_amount', o.discount_amount,
                'customer_id',     o.customer_id,
                'customer_name',   COALESCE(o.customer_name, c.customer_name,
                                            o.snapshot_data->>'cus_name', ''),
                'snapshot_data',   o.snapshot_data,
                'lines',           '[]'::JSONB
            )
              INTO v_result
              FROM om_orders o
              LEFT JOIN fnd_customers c
                     ON c.customer_id = o.customer_id
                    AND c.tenant_id   = o.tenant_id
              LEFT JOIN fnd_customers top_c
                     ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id)
                    AND top_c.tenant_id   = o.tenant_id
             WHERE o.order_id  = p_order_id
               AND o.tenant_id = p_tenant_id
               AND (
                   NOT p_return_actives_only
                   OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE))
               );
        ELSE
            SELECT jsonb_build_object(
                'order_id',        o.order_id,
                'order_number',    o.order_number,
                'order_date',      o.order_date,
                'production_date', o.production_date,
                'production_code', o.production_code,
                'delivery_amount', 0,
                'department_event',  o.department_event,
                'amount',          o.amount,
                'discount_amount', o.discount_amount,
                'customer_id',     o.customer_id,
                'customer_name',   COALESCE(o.customer_name, c.customer_name,
                                            o.snapshot_data->>'cus_name', ''),
                'snapshot_data',   o.snapshot_data,
                'lines',           COALESCE(lines_agg.lines, '[]'::JSONB)
            )
              INTO v_result
              FROM om_orders o
              LEFT JOIN fnd_customers c
                     ON c.customer_id = o.customer_id
                    AND c.tenant_id   = o.tenant_id
              LEFT JOIN fnd_customers top_c
                     ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id)
                    AND top_c.tenant_id   = o.tenant_id
              LEFT JOIN LATERAL (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'order_id',        l.order_id,
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
                            'is_scored',       FALSE,
                            -- Capabilities from bps_items for UI checkbox enabling
                            'can_slice',       COALESCE(b.is_sliceable, FALSE),
                            'can_wrap',        COALESCE(b.is_wrappable,  FALSE),
                            'can_cover',       COALESCE(b.is_coverable,  FALSE),
                            'can_score',       FALSE
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
               AND o.tenant_id = p_tenant_id
               AND (
                   NOT p_return_actives_only
                   OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE))
               );
        END IF;

        RETURN COALESCE(v_result, 'null'::JSONB);
    END IF;

    -- ── List mode: order headers (no lines) ───────────────────────────────
    v_lookup_customer_id := p_customer_id;
    v_production_code := NULLIF(UPPER(TRIM(p_production_code)), '');

    IF p_customer_id IS NOT NULL THEN
        SELECT CASE
                   WHEN UPPER(TRIM(customer_type)) = 'LOCATION'
                    AND customer_parent_id IS NOT NULL
                   THEN customer_parent_id
                   ELSE customer_id
               END
          INTO v_lookup_customer_id
          FROM fnd_customers
         WHERE tenant_id = p_tenant_id
           AND customer_id = p_customer_id;
    END IF;

    SELECT jsonb_agg(row_data ORDER BY top_customer_name_sort ASC, department_event_sort ASC, order_id_sort DESC)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'order_id',        o.order_id,
            'order_number',    o.order_number,
            'order_date',      o.order_date,
            'production_date', o.production_date,
            'production_code',   o.production_code,
            'delivery_amount', 0,
            'department_event',  o.department_event,
            'amount',          o.amount,
            'discount_amount', o.discount_amount,
            'customer_id',     o.customer_id,
            'customer_number', c.customer_number,
            'customer_name',   COALESCE(o.customer_name, c.customer_name,
                                        o.snapshot_data->>'cus_name', ''),
            'top_customer_id', COALESCE(c.top_customer_id, c.customer_id),
            'top_customer_name', COALESCE(top_c.customer_name, c.customer_name, o.snapshot_data->>'cus_name', '')
        ) AS row_data,
        o.production_date AS production_date_sort,
        o.order_id AS order_id_sort,
        COALESCE(top_c.customer_name, o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', '') AS top_customer_name_sort,
        COALESCE(o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', '') || ' - ' || COALESCE(o.department_event, '') AS department_event_sort
          FROM om_orders o
          LEFT JOIN fnd_customers c
                 ON c.customer_id = o.customer_id
                AND c.tenant_id   = o.tenant_id
          LEFT JOIN fnd_customers top_c
                 ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id)
                AND top_c.tenant_id   = o.tenant_id
         WHERE o.tenant_id = p_tenant_id
           AND (v_lookup_customer_id IS NULL OR o.customer_id = v_lookup_customer_id)
           AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
           AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
           AND (v_production_code IS NULL OR o.production_code = v_production_code)
           AND (
               NOT p_return_actives_only
               OR o.customer_id IS NULL
               OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE))
           )
         ORDER BY top_customer_name_sort ASC, department_event_sort ASC, o.order_id DESC
         LIMIT 500
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
