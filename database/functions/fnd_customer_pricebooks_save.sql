-- ============================================================
-- fnd_customer_pricebooks_save
--
-- Upserts customer pricebook assignments.
-- p_entries: JSONB array — null customer_pricebook_id → INSERT, else UPDATE.
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- Prerequisites: fnd_customer_pricebooks.sql, fnd_users.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_customer_pricebooks_save(
  p_tenant_id   BIGINT,
  p_customer_id BIGINT,
  p_entries     JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_entry   JSONB;
  v_user_id BIGINT;
  v_id      BIGINT;
  v_saved   INT := 0;
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

  SELECT user_id INTO v_user_id
  FROM fnd_users
  WHERE auth_user_id = auth.uid()
    AND tenant_id    = p_tenant_id
  LIMIT 1;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_entries)
  LOOP
    v_id := NULLIF(v_entry->>'customer_pricebook_id', '')::BIGINT;

    IF v_id IS NULL THEN
      INSERT INTO fnd_customer_pricebooks (
        tenant_id, customer_id, pricebook_id,
        assignment_type, status,
        effective_start_date, effective_end_date,
        is_active, precedence,
        created_by, updated_by
      ) VALUES (
        p_tenant_id,
        p_customer_id,
        (v_entry->>'pricebook_id')::BIGINT,
        v_entry->>'assignment_type',
        COALESCE(NULLIF(v_entry->>'status', ''), 'Draft'),
        (v_entry->>'effective_start_date')::DATE,
        NULLIF(v_entry->>'effective_end_date', '')::DATE,
        COALESCE((v_entry->>'is_active')::BOOLEAN, TRUE),
        COALESCE(NULLIF(v_entry->>'precedence', '')::BIGINT, 0),
        v_user_id, v_user_id
      );
    ELSE
      UPDATE fnd_customer_pricebooks SET
        pricebook_id         = (v_entry->>'pricebook_id')::BIGINT,
        assignment_type      = v_entry->>'assignment_type',
        status               = COALESCE(NULLIF(v_entry->>'status', ''), status),
        effective_start_date = (v_entry->>'effective_start_date')::DATE,
        effective_end_date   = NULLIF(v_entry->>'effective_end_date', '')::DATE,
        is_active            = COALESCE((v_entry->>'is_active')::BOOLEAN, is_active),
        precedence           = COALESCE(NULLIF(v_entry->>'precedence', '')::BIGINT, precedence),
        updated_by           = v_user_id
      WHERE customer_pricebook_id = v_id
        AND tenant_id             = p_tenant_id;
    END IF;

    v_saved := v_saved + 1;
  END LOOP;

  RETURN jsonb_build_object('saved', v_saved);
END;
$$;
