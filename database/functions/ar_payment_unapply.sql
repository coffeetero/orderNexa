-- ============================================================
-- ar_payment_unapply
-- Takes applications off a payment: the rows are kept and marked reversed (who, when, why); the invoices reopen and the
-- payment's cash goes back to unapplied. Credit applications entered with the payment are reversed the same way.
-- p_payload: { application_ids: [..], credit_application_ids: [..], reason }  both lists empty or missing = all live ones
-- Returns ar_payment_get.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_unapply(p_tenant_id bigint, p_ar_payment_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user   bigint := bps.fnd_current_user_id();
  v_reason text   := COALESCE(NULLIF(btrim(p_payload ->> 'reason'), ''), 'Unapplied');
  v_apps   bigint[] := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_payload -> 'application_ids', '[]'::jsonb))::bigint);
  v_creds  bigint[] := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_payload -> 'credit_application_ids', '[]'::jsonb))::bigint);
  v_all    boolean;
  v_n      integer;
  v_m      integer;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'W') THEN RAISE EXCEPTION 'You do not have access to unapply payments'; END IF;
  PERFORM 1 FROM ar_payments WHERE tenant_id = p_tenant_id AND ar_payment_id = p_ar_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment % not found', p_ar_payment_id; END IF;
  v_all := cardinality(v_apps) = 0 AND cardinality(v_creds) = 0;

  UPDATE ar_payment_applications SET reversed_at = now(), reversed_by = v_user, reversal_reason = v_reason, updated_by = v_user
   WHERE tenant_id = p_tenant_id AND ar_payment_id = p_ar_payment_id AND reversed_at IS NULL
     AND (v_all OR ar_payment_application_id = ANY (v_apps));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE ar_credit_applications SET reversed_at = now(), reversed_by = v_user, reversal_reason = v_reason, updated_by = v_user
   WHERE tenant_id = p_tenant_id AND ar_payment_id = p_ar_payment_id AND reversed_at IS NULL
     AND (v_all OR ar_credit_application_id = ANY (v_creds));
  GET DIAGNOSTICS v_m = ROW_COUNT;

  IF v_all AND v_n + v_m = 0 THEN RAISE EXCEPTION 'This payment has nothing applied'; END IF;
  IF NOT v_all AND (v_n <> cardinality(v_apps) OR v_m <> cardinality(v_creds)) THEN
    RAISE EXCEPTION 'Some of these applications are not on this payment or were already unapplied';
  END IF;
  RETURN bps.ar_payment_get(p_tenant_id, p_ar_payment_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_unapply(bigint, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_unapply(bigint, bigint, jsonb) TO authenticated, service_role, bps_dev;
