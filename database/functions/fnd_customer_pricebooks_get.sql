-- ============================================================
-- fnd_customer_pricebooks_get
--
-- Returns pricebook assignments for a customer plus all active
-- pricebooks for the tenant (for the dropdown).
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- Prerequisites: fnd_customer_pricebooks.sql, fnd_pricebooks.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_customer_pricebooks_get(
  p_tenant_id   BIGINT,
  p_customer_id BIGINT
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

  SELECT jsonb_build_object(
    'assignments', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'customer_pricebook_id', cp.customer_pricebook_id,
          'pricebook_id',          cp.pricebook_id,
          'pricebook_name',        pb.pricebook_name,
          'assignment_type',       cp.assignment_type,
          'status',                cp.status,
          'effective_start_date',  to_char(cp.effective_start_date, 'YYYY-MM-DD'),
          'effective_end_date',    to_char(cp.effective_end_date,   'YYYY-MM-DD'),
          'is_active',             cp.is_active,
          'precedence',            cp.precedence
        )
        ORDER BY cp.precedence, cp.effective_start_date
      )
      FROM fnd_customer_pricebooks cp
      JOIN fnd_pricebooks pb ON pb.pricebook_id = cp.pricebook_id
      WHERE cp.tenant_id   = p_tenant_id
        AND cp.customer_id = p_customer_id
    ), '[]'::jsonb),
    'pricebooks', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'pricebook_id',   pb.pricebook_id,
          'pricebook_name', pb.pricebook_name
        )
        ORDER BY pb.pricebook_name
      )
      FROM fnd_pricebooks pb
      WHERE pb.tenant_id = p_tenant_id
        AND pb.is_active  = TRUE
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;
