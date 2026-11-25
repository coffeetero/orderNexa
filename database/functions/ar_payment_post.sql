-- ============================================================
-- ar_payment_post
-- Records a customer payment and its applications in one call.
-- p_payload: { customer_id, payment_date, payment_method, reference_number, amount,
--              applications: [{ ar_transaction_id, amount }], credits: [{ ar_transaction_id, amount }], auto_apply,
--              allow_duplicate }
-- Rules: the date is not in the future; the amount is >= 0 in cents ($0 only to apply credits); a CHECK needs its check
-- number; the same reference on another live payment of the customer is refused with "Duplicate reference: ..." unless
-- allow_duplicate is true. Applications follow ar_payment_apply; whatever is not applied stays on account as unapplied
-- cash (a credit in the AR reports). The payment number continues the PMT-n series under a per-tenant lock.
-- Returns ar_payment_get.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_post(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user     bigint  := bps.fnd_current_user_id();
  v_today    date    := (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date;
  v_customer bigint  := NULLIF(p_payload ->> 'customer_id', '')::bigint;
  v_date     date    := NULLIF(p_payload ->> 'payment_date', '')::date;
  v_method   text    := upper(NULLIF(btrim(p_payload ->> 'payment_method'), ''));
  v_ref      text    := NULLIF(btrim(p_payload ->> 'reference_number'), '');
  v_amount   numeric := NULLIF(p_payload ->> 'amount', '')::numeric;
  v_dup      text;
  v_number   text;
  v_id       bigint;
  v_has_apps boolean := jsonb_array_length(COALESCE(p_payload -> 'applications', '[]'::jsonb)) > 0
                        OR COALESCE((p_payload ->> 'auto_apply')::boolean, false);
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'W') THEN RAISE EXCEPTION 'You do not have access to enter payments'; END IF;

  IF v_customer IS NULL OR NOT EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = v_customer) THEN
    RAISE EXCEPTION 'Choose a customer';
  END IF;
  IF v_date IS NULL THEN RAISE EXCEPTION 'Enter the payment date'; END IF;
  IF v_date > v_today THEN RAISE EXCEPTION 'The payment date cannot be in the future'; END IF;
  IF v_method IS NULL OR v_method NOT IN ('CHECK', 'ACH', 'CARD', 'CASH', 'WIRE', 'ZELLE', 'MISC') THEN
    RAISE EXCEPTION 'Choose a payment method';
  END IF;
  IF v_method = 'CHECK' AND v_ref IS NULL THEN RAISE EXCEPTION 'Enter the check number'; END IF;
  IF v_amount IS NULL OR v_amount < 0 OR round(v_amount, 2) <> v_amount THEN RAISE EXCEPTION 'Enter the amount in dollars and cents'; END IF;
  IF v_amount = 0 AND jsonb_array_length(COALESCE(p_payload -> 'credits', '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'Enter an amount, or choose credits to apply';
  END IF;

  IF v_ref IS NOT NULL AND NOT COALESCE((p_payload ->> 'allow_duplicate')::boolean, false) THEN
    SELECT COALESCE(p.payment_number, p.ar_payment_id::text) || ' on ' || p.payment_date || ' for ' || round(p.amount, 2) INTO v_dup
      FROM ar_payments p
     WHERE p.tenant_id = p_tenant_id AND p.customer_id = v_customer AND p.voided_at IS NULL
       AND lower(btrim(p.reference_number)) = lower(v_ref)
     ORDER BY p.payment_date DESC LIMIT 1;
    IF v_dup IS NOT NULL THEN
      RAISE EXCEPTION 'Duplicate reference: % is already on payment %', v_ref, v_dup;
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('ar_payment_number:' || p_tenant_id, 0));
  SELECT 'PMT-' || (COALESCE(max(substring(p.payment_number FROM 5)::bigint), 0) + 1) INTO v_number
    FROM ar_payments p WHERE p.tenant_id = p_tenant_id AND p.payment_number ~ '^PMT-[0-9]{1,15}$';

  INSERT INTO ar_payments (tenant_id, customer_id, payment_date, amount, payment_number, payment_method, reference_number, created_by, updated_by)
  VALUES (p_tenant_id, v_customer, v_date, v_amount, v_number, v_method, v_ref, v_user, v_user)
  RETURNING ar_payment_id INTO v_id;

  IF v_has_apps THEN
    RETURN bps.ar_payment_apply(p_tenant_id, v_id, jsonb_build_object(
      'applications', COALESCE(p_payload -> 'applications', '[]'::jsonb), 'credits', COALESCE(p_payload -> 'credits', '[]'::jsonb),
      'auto_apply', COALESCE((p_payload ->> 'auto_apply')::boolean, false), 'applied_on', v_date));
  END IF;
  RETURN bps.ar_payment_get(p_tenant_id, v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_post(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_post(bigint, jsonb) TO authenticated, service_role, bps_dev;
