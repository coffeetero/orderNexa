-- ============================================================
-- ar_payment_get
-- One payment with its applications (live and reversed) and the credit applications entered with it.
-- status: VOID (unapplied 0), UNAPPLIED (nothing applied), PARTIAL (some cash left), APPLIED.
-- Returns { ar_payment_id, payment_number, customer_id, customer_name, customer_number, payment_date, payment_method,
--           reference_number, amount, applied, unapplied, status, created_at, created_by_name, voided_at, voided_by_name,
--           void_reason, legacy, applications: [...], credit_applications: [...] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_get(p_tenant_id bigint, p_ar_payment_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'R') THEN RAISE EXCEPTION 'You do not have access to payments'; END IF;

  SELECT jsonb_build_object(
           'ar_payment_id', p.ar_payment_id, 'payment_number', p.payment_number, 'customer_id', p.customer_id,
           'customer_name', c.customer_name, 'customer_number', c.customer_number, 'payment_date', p.payment_date,
           'payment_method', p.payment_method, 'reference_number', p.reference_number, 'amount', p.amount,
           'applied', a.applied, 'settled', p.settled_amount,
           'unapplied', CASE WHEN p.voided_at IS NULL THEN p.amount - a.applied - p.settled_amount ELSE 0 END,
           'status', CASE WHEN p.voided_at IS NOT NULL THEN 'VOID' WHEN a.applied + p.settled_amount = 0 THEN 'UNAPPLIED'
                          WHEN a.applied + p.settled_amount < p.amount THEN 'PARTIAL' ELSE 'APPLIED' END,
           'created_at', p.created_at, 'created_by_name', (SELECT u.user_name FROM fnd_users u WHERE u.user_id = p.created_by),
           'voided_at', p.voided_at, 'voided_by_name', (SELECT u.user_name FROM fnd_users u WHERE u.user_id = p.voided_by),
           'void_reason', p.void_reason, 'legacy', p.legacy_ar_trn_id IS NOT NULL,
           'applications', COALESCE((
             SELECT jsonb_agg(jsonb_build_object(
                      'ar_payment_application_id', pa.ar_payment_application_id, 'ar_transaction_id', t.ar_transaction_id,
                      'document_number', t.document_number, 'transaction_type', t.transaction_type, 'customer_name', tc.customer_name,
                      'transaction_date', t.transaction_date, 'document_amount', t.amount, 'applied_amount', pa.applied_amount,
                      'applied_at', pa.applied_at, 'reversed_at', pa.reversed_at, 'reversal_reason', pa.reversal_reason,
                      'reversed_by_name', (SELECT u.user_name FROM fnd_users u WHERE u.user_id = pa.reversed_by),
                      'open', bps.ar_transaction_open_amount(p_tenant_id, t.ar_transaction_id))
                      ORDER BY pa.reversed_at IS NOT NULL, t.transaction_date, t.document_number, pa.ar_payment_application_id)
               FROM ar_payment_applications pa
               JOIN ar_transactions t ON t.ar_transaction_id = pa.ar_transaction_id
               JOIN fnd_customers tc ON tc.customer_id = t.customer_id
              WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id), '[]'::jsonb),
           'credit_applications', COALESCE((
             SELECT jsonb_agg(jsonb_build_object(
                      'ar_credit_application_id', ca.ar_credit_application_id,
                      'credit_ar_transaction_id', ca.credit_ar_transaction_id, 'credit_document_number', cr.document_number,
                      'ar_transaction_id', ca.ar_transaction_id, 'document_number', inv.document_number,
                      'applied_amount', ca.applied_amount, 'applied_at', ca.applied_at, 'reversed_at', ca.reversed_at,
                      'reversal_reason', ca.reversal_reason,
                      'reversed_by_name', (SELECT u.user_name FROM fnd_users u WHERE u.user_id = ca.reversed_by))
                      ORDER BY ca.reversed_at IS NOT NULL, inv.transaction_date, inv.document_number, ca.ar_credit_application_id)
               FROM ar_credit_applications ca
               JOIN ar_transactions cr ON cr.ar_transaction_id = ca.credit_ar_transaction_id
               JOIN ar_transactions inv ON inv.ar_transaction_id = ca.ar_transaction_id
              WHERE ca.tenant_id = p_tenant_id AND ca.ar_payment_id = p.ar_payment_id), '[]'::jsonb))
    INTO v_result
    FROM ar_payments p
    JOIN fnd_customers c ON c.customer_id = p.customer_id
    CROSS JOIN LATERAL (SELECT COALESCE(SUM(pa.applied_amount), 0) AS applied FROM ar_payment_applications pa
                         WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id AND pa.reversed_at IS NULL) a
   WHERE p.tenant_id = p_tenant_id AND p.ar_payment_id = p_ar_payment_id;
  IF v_result IS NULL THEN RAISE EXCEPTION 'Payment % not found', p_ar_payment_id; END IF;
  RETURN v_result;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_get(bigint, bigint) TO authenticated, service_role, bps_dev;
