-- ============================================================
-- ar_payment_void
-- Voids a payment (bounced / NSF check, entered in error): every live application and credit application is reversed
-- with the reason, and the payment is marked void. Nothing is deleted; reports count the payment until the void date.
-- A bank fee for a returned check is not charged here (enter it as an invoice charge).
-- Returns ar_payment_get.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_void(p_tenant_id bigint, p_ar_payment_id bigint, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user   bigint := bps.fnd_current_user_id();
  v_reason text   := NULLIF(btrim(p_reason), '');
  v_pay    ar_payments%ROWTYPE;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'W') THEN RAISE EXCEPTION 'You do not have access to void payments'; END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION 'Enter the reason for voiding the payment'; END IF;
  SELECT * INTO v_pay FROM ar_payments WHERE tenant_id = p_tenant_id AND ar_payment_id = p_ar_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment % not found', p_ar_payment_id; END IF;
  IF v_pay.voided_at IS NOT NULL THEN RAISE EXCEPTION 'Payment % is already void', COALESCE(v_pay.payment_number, v_pay.ar_payment_id::text); END IF;

  UPDATE ar_payment_applications SET reversed_at = now(), reversed_by = v_user, reversal_reason = 'Void: ' || v_reason, updated_by = v_user
   WHERE tenant_id = p_tenant_id AND ar_payment_id = p_ar_payment_id AND reversed_at IS NULL;
  UPDATE ar_credit_applications SET reversed_at = now(), reversed_by = v_user, reversal_reason = 'Void: ' || v_reason, updated_by = v_user
   WHERE tenant_id = p_tenant_id AND ar_payment_id = p_ar_payment_id AND reversed_at IS NULL;
  UPDATE ar_payments SET voided_at = now(), voided_by = v_user, void_reason = v_reason, updated_by = v_user
   WHERE ar_payment_id = p_ar_payment_id;
  RETURN bps.ar_payment_get(p_tenant_id, p_ar_payment_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_void(bigint, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_void(bigint, bigint, text) TO authenticated, service_role, bps_dev;
