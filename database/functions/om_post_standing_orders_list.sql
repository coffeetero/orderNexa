-- ============================================================
-- om_post_standing_orders_list
-- Returns candidates for posting standing orders on a given
-- production date and set of production codes.
--
-- Filters to: is_standing_order = TRUE AND is_active = TRUE
-- Derives day-of-week from p_production_date.
-- Sets already_posted = TRUE when an order already exists
-- (checks parent customer_id for DEPARTMENT customers).
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_post_standing_orders_list(
  p_tenant_id        BIGINT,
  p_production_date  DATE,
  p_production_codes TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_dow TEXT;
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

  v_dow := CASE EXTRACT(DOW FROM p_production_date)
    WHEN 0 THEN 'SUN' WHEN 1 THEN 'MON' WHEN 2 THEN 'TUE'
    WHEN 3 THEN 'WED' WHEN 4 THEN 'THU' WHEN 5 THEN 'FRI'
    WHEN 6 THEN 'SAT'
  END;

  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'customer_id',     fc.customer_id,
        'customer_number', COALESCE(fc.customer_number, ''),
        'customer_name',   fc.customer_name,
        'production_code', so.production_code,
        'already_posted',  CASE
          WHEN fc.customer_type = 'DEPARTMENT' THEN
            EXISTS(SELECT 1 FROM om_orders o
              WHERE o.tenant_id       = p_tenant_id
                AND o.customer_id    = COALESCE(fc.customer_parent_id, fc.customer_id)
                AND o.production_date = p_production_date
                AND o.production_code = so.production_code)
          ELSE
            EXISTS(SELECT 1 FROM om_orders o
              WHERE o.tenant_id       = p_tenant_id
                AND o.customer_id    = fc.customer_id
                AND o.production_date = p_production_date
                AND o.production_code = so.production_code)
        END
      )
      ORDER BY so.production_code, fc.customer_number
    )
    FROM (
      SELECT DISTINCT so2.customer_id, so2.production_code
      FROM om_standing_orders so2
      WHERE so2.tenant_id       = p_tenant_id
        AND so2.production_dow  = v_dow
        AND so2.production_code = ANY(p_production_codes)
        AND so2.is_active       = TRUE
    ) so
    JOIN fnd_customers fc
      ON fc.customer_id        = so.customer_id
     AND fc.tenant_id          = p_tenant_id
     AND fc.is_standing_order  = TRUE
     AND fc.is_active          = TRUE
  ), '[]'::JSONB);
END;
$$;
