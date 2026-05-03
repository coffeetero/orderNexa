-- ============================================================
-- om_get_invoices
-- Looks up an existing AR invoice (ar_transactions) for a given
-- customer + production date + production window, and returns
-- the invoice document number together with the production order
-- numbers (om_orders) linked to that invoice via the shipment chain:
--
--   om_orders → om_order_shipments → ar_transaction_lines → ar_transactions
--
-- Returns:
--   { "invoice_number": "523310",
--     "orders": [ { "order_id": 101, "order_number": "8845" }, ... ] }
-- or NULL when no ar_transaction is found for the given combination.
--
-- p_user_id is accepted for future created_by stamping but not used
-- for filtering in this release.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_get_invoices(
    p_tenant_id        BIGINT,
    p_customer_id      BIGINT,
    p_production_date  DATE,
    p_production_code  TEXT,
    p_user_id          BIGINT DEFAULT NULL   -- reserved; not used for filtering
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_ar_transaction_id BIGINT;
    v_invoice_number    TEXT;
    v_orders            JSONB;
    v_result            JSONB;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;
    IF p_customer_id IS NULL THEN
        RAISE EXCEPTION 'p_customer_id is required';
    END IF;

    -- ── Resolve ar_transaction via the shipment chain ─────────────────────
    -- Find an AR invoice whose lines link back to shipments of orders that
    -- match the given customer + production_date + production_code.
    SELECT DISTINCT
           ar.ar_transaction_id,
           ar.document_number
      INTO v_ar_transaction_id, v_invoice_number
      FROM om_orders          o
      JOIN om_order_shipments s  ON s.order_id   = o.order_id
                                AND s.tenant_id  = o.tenant_id
      JOIN ar_transaction_lines tl ON tl.order_shipment_id = s.order_shipment_id
                                  AND tl.tenant_id         = o.tenant_id
      JOIN ar_transactions      ar ON ar.ar_transaction_id = tl.ar_transaction_id
                                  AND ar.tenant_id         = o.tenant_id
     WHERE o.tenant_id       = p_tenant_id
       AND o.customer_id     = p_customer_id
       AND o.production_date = p_production_date
       AND o.production_code = p_production_code
     ORDER BY ar.ar_transaction_id DESC
     LIMIT 1;

    -- No invoice found → return NULL
    IF v_ar_transaction_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- ── Collect order numbers linked to this invoice ─────────────────────
    SELECT jsonb_agg(
               jsonb_build_object(
                   'order_id',     o.order_id,
                   'order_number', o.order_number
               )
               ORDER BY o.order_id
           )
      INTO v_orders
      FROM (
          SELECT DISTINCT o.order_id, o.order_number
            FROM om_orders          o
            JOIN om_order_shipments s  ON s.order_id   = o.order_id
                                      AND s.tenant_id  = o.tenant_id
            JOIN ar_transaction_lines tl ON tl.order_shipment_id = s.order_shipment_id
                                        AND tl.tenant_id         = o.tenant_id
           WHERE tl.ar_transaction_id = v_ar_transaction_id
             AND o.tenant_id          = p_tenant_id
      ) o;

    v_result := jsonb_build_object(
        'invoice_number', v_invoice_number,
        'orders',         COALESCE(v_orders, '[]'::JSONB)
    );

    RETURN v_result;
END;
$$;
