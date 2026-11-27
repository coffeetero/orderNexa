-- ============================================================
-- om_post_standing_orders_list
-- Posting candidates for every production date from p_date_from to p_date_to (each date uses its own day of the
-- week) and the given production codes: one row per standing-order customer + date + code, with the same filters and
-- order lookup as om_standing_orders_post.
--   status NEW            nothing posted yet and no order with the customer's name as department/event
--          POSTED         posted before (om_standing_order_postings) or an order already exists; posting again only
--                         adds standing order items missing from that order
--          POSTED_TO_AR   its order is on an invoice with a number; posting leaves it alone
--          ORDER_DELETED  posted before but the order was deleted; posting leaves it alone
--   already_posted = status <> NEW.
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- ============================================================

DROP FUNCTION IF EXISTS bps.om_post_standing_orders_list(bigint, date, text[]);

CREATE OR REPLACE FUNCTION bps.om_post_standing_orders_list(
  p_tenant_id        BIGINT,
  p_date_from        DATE,
  p_date_to          DATE,
  p_production_codes TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
BEGIN
  IF NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb
          -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to < p_date_from OR p_date_to - p_date_from > 13 THEN
    RAISE EXCEPTION 'A valid date range of at most 14 days is required';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'production_date', x.production_date,
             'customer_id',     x.customer_id,
             'customer_number', COALESCE(x.customer_number, ''),
             'customer_name',   x.customer_name,
             'customer_type',   x.customer_type,
             'production_code', x.production_code,
             'status',          x.status,
             'already_posted',  x.status <> 'NEW',
             'order_id',        x.order_id,
             'order_number',    x.order_number,
             'department_event', x.department_event,
             'last_posted_at',  x.last_posted_at)
           ORDER BY x.production_date, x.production_code, x.customer_number, x.customer_id)
    FROM (
      SELECT s.*, o.order_id, o.order_number, o.department_event, lg.last_posted_at,
             CASE
               WHEN o.order_id IS NOT NULL AND EXISTS (
                      SELECT 1 FROM ar_transaction_lines l
                        JOIN ar_transactions t ON t.ar_transaction_id = l.ar_transaction_id AND t.tenant_id = l.tenant_id
                       WHERE l.tenant_id = p_tenant_id AND l.order_id = o.order_id
                         AND t.document_number IS NOT NULL AND t.status <> 'CANCELLED') THEN 'POSTED_TO_AR'
               WHEN o.order_id IS NOT NULL THEN 'POSTED'
               WHEN lg.posting_id IS NOT NULL THEN 'ORDER_DELETED'
               ELSE 'NEW'
             END AS status
        FROM (
          SELECT DISTINCT d.d::date AS production_date, so.customer_id, so.production_code,
                 c.customer_number, c.customer_name, c.customer_type,
                 CASE WHEN UPPER(TRIM(c.customer_type)) = 'DEPARTMENT' AND c.customer_parent_id IS NOT NULL
                      THEN c.customer_parent_id ELSE c.customer_id END AS order_customer_id,
                 COALESCE(NULLIF(UPPER(TRIM(c.customer_name)), ''), 'ORDER') AS event
            FROM generate_series(p_date_from, p_date_to, interval '1 day') d
            JOIN om_standing_orders so
              ON so.tenant_id = p_tenant_id
             AND so.production_dow = (ARRAY['SUN','MON','TUE','WED','THU','FRI','SAT'])[EXTRACT(DOW FROM d.d)::int + 1]
             AND so.production_code = ANY (p_production_codes)
             AND so.is_active
             AND (so.effective_from IS NULL OR so.effective_from <= d.d::date)
             AND (so.effective_to IS NULL OR so.effective_to >= d.d::date)
            JOIN fnd_customers c
              ON c.customer_id = so.customer_id AND c.tenant_id = p_tenant_id
             AND c.is_standing_order AND c.is_active
        ) s
        LEFT JOIN om_standing_order_postings lg
               ON lg.tenant_id = p_tenant_id AND lg.customer_id = s.customer_id
              AND lg.production_date = s.production_date AND lg.production_code = s.production_code
        LEFT JOIN LATERAL (
               SELECT o2.order_id, o2.order_number, o2.department_event
                 FROM om_orders o2
                WHERE o2.tenant_id = p_tenant_id
                  AND (o2.order_id = lg.order_id
                       OR (o2.customer_id = s.order_customer_id AND o2.production_date = s.production_date
                           AND o2.production_code = s.production_code AND o2.department_event = s.event))
                ORDER BY (o2.order_id = lg.order_id) DESC NULLS LAST
                LIMIT 1
        ) o ON TRUE
    ) x
  ), '[]'::JSONB);
END;
$$;
