-- ============================================================
-- fnd_pricebook_items_get
--
-- Returns all active pricebooks for a tenant, left-joined to
-- the item's tier-1 (min_quantity=1) price if one exists.
--
-- Sorted: priced pricebooks first (has pricebook_item_id),
--         then unpriced, both groups alphabetical by name.
--
-- SECURITY DEFINER — bypasses the customer-facing RLS on
-- fnd_pricebook_items; validates tenant access via JWT claims.
--
-- Prerequisites: fnd_pricebooks.sql, fnd_pricebook_items.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_pricebook_items_get(
  p_tenant_id BIGINT,
  p_item_id   BIGINT
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
        (NULLIF(current_setting('request.jwt.claims'::text, true), ''::text))::jsonb
          -> 'app_metadata'::text
          -> 'allowed_tenant_ids'::text
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'pricebook_id',      pb.pricebook_id,
        'pricebook_name',    pb.pricebook_name,
        'pricebook_item_id', pi.pricebook_item_id,
        'item_price',        pi.item_price,
        'is_active',         pi.is_active
      )
      ORDER BY (pi.pricebook_item_id IS NOT NULL) DESC, pb.pricebook_name
    ),
    '[]'::JSONB
  )
  INTO v_result
  FROM fnd_pricebooks pb
  LEFT JOIN fnd_pricebook_items pi
         ON pi.pricebook_id = pb.pricebook_id
        AND pi.item_id      = p_item_id
        AND pi.tenant_id    = p_tenant_id
        AND pi.min_quantity = 1
  WHERE pb.tenant_id = p_tenant_id
    AND pb.is_active  = true;

  RETURN v_result;
END;
$$;
