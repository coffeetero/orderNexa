-- ============================================================
-- om_standing_orders_get
-- Returns standing order lines with item details for a given
-- (customer, production_dow, production_code).
-- Returns empty array when no standing order exists yet.
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_standing_orders_get(
  p_tenant_id       BIGINT,
  p_customer_id     BIGINT,
  p_production_dow  TEXT,
  p_production_code TEXT
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

  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'standing_order_id', so.standing_order_id,
        'item_id',           so.item_id,
        'item_number',       COALESCE(i.item_number, ''),
        'item_name',         i.item_name,
        'quantity',          so.quantity,
        'prep_options',      so.prep_options
      )
      ORDER BY i.item_number
    )
    FROM om_standing_orders so
    JOIN fnd_items i
      ON i.item_id   = so.item_id
     AND i.tenant_id = p_tenant_id
    WHERE so.tenant_id       = p_tenant_id
      AND so.customer_id     = p_customer_id
      AND so.production_dow  = p_production_dow
      AND so.production_code = p_production_code
      AND so.is_active       = TRUE
  ), '[]'::JSONB);
END;
$$;
