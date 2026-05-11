-- ============================================================
-- om_orders_get_v2 — RLS-respecting version (no SECURITY DEFINER)
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
--   p_department_events_only = TRUE
--                      → returns distinct Department/Event suggestions for the
--                        selected customer/date range.
--
-- Scoring fields are intentionally returned as FALSE until the item/order-line
-- scoring columns are added to the deployed schema.
-- ============================================================

DROP FUNCTION IF EXISTS bps.om_orders_get_v2(BIGINT, BIGINT, BIGINT, DATE, DATE, TEXT, BOOLEAN, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION bps.om_orders_get_v2(
    p_tenant_id               BIGINT,
    p_order_id                BIGINT   DEFAULT NULL,
    p_customer_id             BIGINT   DEFAULT NULL,
    p_production_date_from    DATE     DEFAULT NULL,
    p_production_date_to      DATE     DEFAULT NULL,
    p_production_code         TEXT     DEFAULT NULL,
    p_return_headers_only     BOOLEAN  DEFAULT TRUE,
    p_return_actives_only     BOOLEAN  DEFAULT TRUE,
    p_department_events_only  BOOLEAN  DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = bps, public
AS $$
DECLARE
    v_result JSONB;
    v_lookup_customer_id BIGINT;
    v_production_code TEXT;
    v_default_department_event TEXT := 'ORDER';
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
                'total_quantity',  o.quantity,
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
                'total_quantity',  o.quantity,
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
                            'allowed_prep_options', COALESCE(prep_allowed.allowed_prep_options, '[]'::JSONB),
                            'prep_options',    COALESCE(l.prep_options, '[]'::JSONB),
                            'is_scored',       FALSE,
                            'can_score',       FALSE
                        )
                        ORDER BY l.order_line_id
                    ) AS lines
                      FROM om_order_lines l
                      LEFT JOIN fnd_items  i ON i.item_id = l.item_id
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

    -- ── Shared customer lookup for list modes ─────────────────────────────
    v_lookup_customer_id := p_customer_id;
    v_production_code := NULLIF(UPPER(TRIM(p_production_code)), '');

    IF p_customer_id IS NOT NULL THEN
        SELECT CASE
                   WHEN UPPER(TRIM(customer_type)) IN ('DEPARTMENT', 'LOCATION')
                    AND customer_parent_id IS NOT NULL
                   THEN customer_parent_id
                   ELSE customer_id
               END,
               CASE
                   WHEN UPPER(TRIM(customer_type)) IN ('DEPARTMENT', 'LOCATION')
                   THEN UPPER(TRIM(customer_name))
                   ELSE 'ORDER'
               END
          INTO v_lookup_customer_id,
               v_default_department_event
          FROM fnd_customers
         WHERE tenant_id = p_tenant_id
           AND customer_id = p_customer_id;
    END IF;

    -- ── Department/Event history mode ─────────────────────────────────────
    IF p_department_events_only THEN
        SELECT jsonb_agg(
                   jsonb_build_object('department_event', department_event)
                   ORDER BY department_event
               )
          INTO v_result
          FROM (
              SELECT DISTINCT UPPER(TRIM(o.department_event)) AS department_event
                FROM om_orders o
                LEFT JOIN fnd_customers c
                       ON c.customer_id = o.customer_id
                      AND c.tenant_id   = o.tenant_id
                LEFT JOIN fnd_customers top_c
                       ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id)
                      AND top_c.tenant_id   = o.tenant_id
               WHERE o.tenant_id = p_tenant_id
                 AND v_lookup_customer_id IS NOT NULL
                 AND o.customer_id = v_lookup_customer_id
                 AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
                 AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
                 AND NULLIF(TRIM(o.department_event), '') IS NOT NULL
                 AND (
                     NOT p_return_actives_only
                     OR o.customer_id IS NULL
                     OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE))
                 )
          ) suggestions;

        RETURN COALESCE(v_result, '[]'::JSONB);
    END IF;

    -- ── List mode: order headers (no lines) ───────────────────────────────
    SELECT jsonb_agg(row_data ORDER BY customer_name_sort ASC, department_event_sort ASC, order_id_sort DESC)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'order_id',        o.order_id,
            'order_number',    o.order_number,
            'order_date',      o.order_date,
            'production_date', o.production_date,
            'production_code',   o.production_code,
            'department_event',  o.department_event,
            'amount',          o.amount,
            'customer_id',     o.customer_id,
            'customer_name',   o.customer_name
        ) AS row_data,
        o.order_id AS order_id_sort,
        COALESCE(o.customer_name, '') AS customer_name_sort,
        COALESCE(o.department_event, '') AS department_event_sort
          FROM om_orders o
         WHERE o.tenant_id = p_tenant_id
           AND (v_lookup_customer_id IS NULL OR o.customer_id = v_lookup_customer_id)
           AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
           AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
           AND (v_production_code IS NULL OR o.production_code = v_production_code)
         ORDER BY customer_name_sort ASC, department_event_sort ASC, o.order_id DESC
         LIMIT 500
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;
