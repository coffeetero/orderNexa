-- ============================================================
-- ar_payment_allocate
-- Auto-apply: spreads money over the customer's open invoices, oldest first (due date, then invoice date and number),
-- each invoice up to its open amount. Nothing is saved; the Auto-apply button shows the result and ar_payment_apply
-- uses it when { auto_apply: true }.
-- p_payload: { customer_id, amount, credits: [{ ar_transaction_id, amount }] }  money = amount + credits used
--         or { ar_payment_id, credits: [...] }                                  money = the payment's unapplied cash + credits
-- Returns { applications: [{ ar_transaction_id, amount }], applied, left_over }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_allocate(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_payment_id bigint  := NULLIF(p_payload ->> 'ar_payment_id', '')::bigint;
  v_customer   bigint  := NULLIF(p_payload ->> 'customer_id', '')::bigint;
  v_money      numeric := COALESCE(NULLIF(p_payload ->> 'amount', '')::numeric, 0);
  v_left       numeric;
  v_take       numeric;
  v_apps       jsonb := '[]'::jsonb;
  v_inv        jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'R') THEN RAISE EXCEPTION 'You do not have access to payments'; END IF;

  IF v_payment_id IS NOT NULL THEN
    SELECT p.customer_id,
           p.amount - COALESCE((SELECT SUM(pa.applied_amount) FROM ar_payment_applications pa
                                 WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id AND pa.reversed_at IS NULL), 0)
      INTO v_customer, v_money
      FROM ar_payments p WHERE p.tenant_id = p_tenant_id AND p.ar_payment_id = v_payment_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment % not found', v_payment_id; END IF;
  END IF;
  IF v_customer IS NULL THEN RAISE EXCEPTION 'Choose a customer'; END IF;
  IF v_money < 0 THEN RAISE EXCEPTION 'The amount cannot be negative'; END IF;

  v_left := v_money + COALESCE((SELECT SUM((c ->> 'amount')::numeric) FROM jsonb_array_elements(COALESCE(p_payload -> 'credits', '[]'::jsonb)) c), 0);

  FOR v_inv IN SELECT jsonb_array_elements(bps.ar_payment_open_items_get(p_tenant_id, v_customer) -> 'invoices') LOOP
    EXIT WHEN v_left <= 0;
    v_take := LEAST(v_left, (v_inv ->> 'open')::numeric);
    v_apps := v_apps || jsonb_build_object('ar_transaction_id', (v_inv ->> 'ar_transaction_id')::bigint, 'amount', v_take);
    v_left := v_left - v_take;
  END LOOP;

  RETURN jsonb_build_object('applications', v_apps,
                            'applied', COALESCE((SELECT SUM((a ->> 'amount')::numeric) FROM jsonb_array_elements(v_apps) a), 0),
                            'left_over', v_left);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_allocate(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_allocate(bigint, jsonb) TO authenticated, service_role, bps_dev;
