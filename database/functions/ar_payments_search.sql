-- ============================================================
-- ar_payments_search
-- Payments list for Manage Payments, newest first, at most 500 rows.
-- p_filters: { customer_id (the account and everything beneath it that is not an ACCOUNT), date_from, date_to,
--              payment_method, reference (part of the reference or payment number), amount (exact),
--              unapplied_only (live payments with cash left), include_void (default true) }
-- Returns { rows: [{ ar_payment_id, payment_number, payment_date, customer_id, customer_name, customer_number,
--                    payment_method, reference_number, amount, applied, unapplied, status, void_reason }], truncated }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payments_search(p_tenant_id bigint, p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_customer  bigint  := NULLIF(p_filters ->> 'customer_id', '')::bigint;
  v_from      date    := NULLIF(p_filters ->> 'date_from', '')::date;
  v_to        date    := NULLIF(p_filters ->> 'date_to', '')::date;
  v_method    text    := upper(NULLIF(btrim(p_filters ->> 'payment_method'), ''));
  v_ref       text    := lower(NULLIF(btrim(p_filters ->> 'reference'), ''));
  v_amount    numeric := NULLIF(p_filters ->> 'amount', '')::numeric;
  v_unapplied boolean := COALESCE((p_filters ->> 'unapplied_only')::boolean, false);
  v_void      boolean := COALESCE((p_filters ->> 'include_void')::boolean, true);
  v_rows      jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'R') THEN RAISE EXCEPTION 'You do not have access to payments'; END IF;

  WITH RECURSIVE tree AS (
    SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = v_customer
    UNION ALL
    SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), hits AS (
    SELECT p.*, COALESCE((SELECT SUM(pa.applied_amount) FROM ar_payment_applications pa
                           WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id AND pa.reversed_at IS NULL), 0) AS applied
      FROM ar_payments p
     WHERE p.tenant_id = p_tenant_id
       AND (v_customer IS NULL OR p.customer_id IN (SELECT customer_id FROM tree))
       AND (v_from IS NULL OR p.payment_date >= v_from)
       AND (v_to IS NULL OR p.payment_date <= v_to)
       AND (v_method IS NULL OR p.payment_method = v_method)
       AND (v_ref IS NULL OR lower(p.reference_number) LIKE '%' || v_ref || '%' OR lower(p.payment_number) LIKE '%' || v_ref || '%')
       AND (v_amount IS NULL OR p.amount = v_amount)
       AND (v_void OR p.voided_at IS NULL)
       AND (NOT v_unapplied OR p.voided_at IS NULL)
  ), shown AS (
    SELECT h.* FROM hits h WHERE NOT v_unapplied OR h.amount > h.applied
     ORDER BY h.payment_date DESC, h.ar_payment_id DESC LIMIT 501
  )
  SELECT jsonb_agg(jsonb_build_object(
           'ar_payment_id', s.ar_payment_id, 'payment_number', s.payment_number, 'payment_date', s.payment_date,
           'customer_id', s.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number,
           'payment_method', s.payment_method, 'reference_number', s.reference_number, 'amount', s.amount,
           'applied', s.applied, 'unapplied', CASE WHEN s.voided_at IS NULL THEN s.amount - s.applied ELSE 0 END,
           'status', CASE WHEN s.voided_at IS NOT NULL THEN 'VOID' WHEN s.applied = 0 THEN 'UNAPPLIED'
                          WHEN s.applied < s.amount THEN 'PARTIAL' ELSE 'APPLIED' END,
           'void_reason', s.void_reason)
           ORDER BY s.payment_date DESC, s.ar_payment_id DESC)
    INTO v_rows
    FROM shown s JOIN fnd_customers c ON c.customer_id = s.customer_id;

  RETURN jsonb_build_object(
    'rows', COALESCE((SELECT jsonb_agg(e) FROM (SELECT e FROM jsonb_array_elements(COALESCE(v_rows, '[]'::jsonb)) WITH ORDINALITY x(e, n) WHERE n <= 500 ORDER BY n) y), '[]'::jsonb),
    'truncated', jsonb_array_length(COALESCE(v_rows, '[]'::jsonb)) > 500);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payments_search(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payments_search(bigint, jsonb) TO authenticated, service_role, bps_dev;
