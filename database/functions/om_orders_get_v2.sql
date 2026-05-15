-- ============================================================
-- om_orders_get_v2
-- Fetches order data for the order entry / management screens.
--
-- Modes:
--   Detail (p_order_id set):
--     Returns a single order with or without lines.
--
--   Department/Event suggestions (p_department_events_only = true):
--     Returns distinct department_event values for the combobox.
--     All orders are included regardless of department_event value —
--     the old filter on non-null department_event was removed because
--     orders defaulted to 'ORDER' and departments now always get a
--     department_event value from om_orders_save.
--
--   List (neither of the above):
--     Returns up to 500 order headers matching the filters.
--
-- Customer type: DEPARTMENT customers are looked up via their parent.
-- (LOCATION is no longer used — superseded by DEPARTMENT.)
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_orders_get_v2(
    p_tenant_id              bigint,
    p_order_id               bigint  DEFAULT NULL,
    p_customer_id            bigint  DEFAULT NULL,
    p_production_date_from   date    DEFAULT NULL,
    p_production_date_to     date    DEFAULT NULL,
    p_production_code        text    DEFAULT NULL,
    p_return_headers_only    boolean DEFAULT true,
    p_return_actives_only    boolean DEFAULT true,
    p_department_events_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_result                   JSONB;
    v_lookup_customer_id       BIGINT;
    v_production_code          TEXT;
    v_default_department_event TEXT := 'ORDER';
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── Detail mode: single order ─────────────────────────────────────────
    IF p_order_id IS NOT NULL THEN
        IF p_return_headers_only THEN
            SELECT jsonb_build_object(
                'order_id',         o.order_id,
                'order_number',     o.order_number,
                'order_date',       o.order_date,
                'production_date',  o.production_date,
                'production_code',  o.production_code,
                'delivery_amount',  0,
                'department_event', o.department_event,
                'amount',           o.amount,
                'total_quantity',   o.quantity,
                'discount_amount',  o.discount_amount,
                'customer_id',      o.customer_id,
                'customer_name',    COALESCE(o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', ''),
                'snapshot_data',    o.snapshot_data,
                'lines',            '[]'::JSONB
            ) INTO v_result
            FROM om_orders o
            LEFT JOIN fnd_customers c
                   ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
            LEFT JOIN fnd_customers top_c
                   ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
            WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id
              AND (NOT p_return_actives_only OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)));
        ELSE
            SELECT jsonb_build_object(
                'order_id',         o.order_id,
                'order_number',     o.order_number,
                'order_date',       o.order_date,
                'production_date',  o.production_date,
                'production_code',  o.production_code,
                'delivery_amount',  0,
                'department_event', o.department_event,
                'amount',           o.amount,
                'total_quantity',   o.quantity,
                'discount_amount',  o.discount_amount,
                'customer_id',      o.customer_id,
                'customer_name',    COALESCE(o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', ''),
                'snapshot_data',    o.snapshot_data,
                'lines',            COALESCE(lines_agg.lines, '[]'::JSONB)
            ) INTO v_result
            FROM om_orders o
            LEFT JOIN fnd_customers c
                   ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
            LEFT JOIN fnd_customers top_c
                   ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
            LEFT JOIN LATERAL (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'order_id',             l.order_id,
                        'order_line_id',        l.order_line_id,
                        'item_id',              l.item_id,
                        'item_number',          COALESCE(i.item_number, ''),
                        'item_description',     l.item_description,
                        'quantity',             l.quantity,
                        'unit_price',           COALESCE(l.unit_price, 0),
                        'unit_discount',        l.unit_discount,
                        'extended_amount',      COALESCE(l.extended_amount, 0),
                        'allowed_prep_options', COALESCE(prep_allowed.allowed_prep_options, '[]'::JSONB),
                        'prep_options',         COALESCE(l.prep_options, '[]'::JSONB),
                        'is_scored',            FALSE,
                        'can_score',            FALSE
                    ) ORDER BY l.order_line_id
                ) AS lines
                FROM om_order_lines l
                LEFT JOIN fnd_items i ON i.item_id = l.item_id
                LEFT JOIN LATERAL (
                    SELECT COALESCE(
                        jsonb_agg(jsonb_build_object('value', vv.value, 'label', vv.label) ORDER BY vv.display_order, vv.label),
                        '[]'::JSONB
                    ) AS allowed_prep_options
                    FROM jsonb_array_elements_text(COALESCE(i.allowed_prep_options, '[]'::JSONB)) opt(value)
                    JOIN fnd_valuesets vs
                      ON vs.tenant_id = i.tenant_id AND vs.valueset_code = 'ITEMPREP' AND vs.is_active = TRUE
                    JOIN fnd_valueset_values vv
                      ON vv.tenant_id = vs.tenant_id AND vv.valueset_id = vs.valueset_id
                     AND vv.value = opt.value AND vv.is_disabled = FALSE
                ) prep_allowed ON TRUE
                WHERE l.order_id = o.order_id AND l.tenant_id = o.tenant_id
            ) lines_agg ON TRUE
            WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id
              AND (NOT p_return_actives_only OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)));
        END IF;
        RETURN COALESCE(v_result, 'null'::JSONB);
    END IF;

    -- ── Resolve lookup customer + default department_event ────────────────
    v_lookup_customer_id := p_customer_id;
    v_production_code    := NULLIF(UPPER(TRIM(p_production_code)), '');

    IF p_customer_id IS NOT NULL THEN
        SELECT
            CASE WHEN UPPER(TRIM(customer_type)) = 'DEPARTMENT' AND customer_parent_id IS NOT NULL
                 THEN customer_parent_id ELSE customer_id END,
            CASE WHEN UPPER(TRIM(customer_type)) = 'DEPARTMENT'
                 THEN UPPER(TRIM(customer_name)) ELSE 'ORDER' END
          INTO v_lookup_customer_id, v_default_department_event
          FROM fnd_customers
         WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id;
    END IF;

    -- ── Department/Event suggestions ──────────────────────────────────────
    -- Returns distinct department_event values for the combobox.
    -- No filter on null/blank department_event — all orders are included.
    IF p_department_events_only THEN
        SELECT jsonb_agg(jsonb_build_object('department_event', department_event) ORDER BY department_event)
          INTO v_result
          FROM (
              SELECT DISTINCT UPPER(TRIM(o.department_event)) AS department_event
                FROM om_orders o
                LEFT JOIN fnd_customers c
                       ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
                LEFT JOIN fnd_customers top_c
                       ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
               WHERE o.tenant_id  = p_tenant_id
                 AND v_lookup_customer_id IS NOT NULL
                 AND o.customer_id = v_lookup_customer_id
                 AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
                 AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
                 AND (NOT p_return_actives_only OR o.customer_id IS NULL
                      OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)))
          ) suggestions;
        RETURN COALESCE(v_result, '[]'::JSONB);
    END IF;

    -- ── Order headers list ────────────────────────────────────────────────
    SELECT jsonb_agg(row_data ORDER BY customer_name_sort ASC, department_event_sort ASC, order_id_sort DESC)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'order_id',         o.order_id,
            'order_number',     o.order_number,
            'order_date',       o.order_date,
            'production_date',  o.production_date,
            'production_code',  o.production_code,
            'department_event', o.department_event,
            'amount',           o.amount,
            'customer_id',      o.customer_id,
            'customer_name',    o.customer_name
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
$function$;
