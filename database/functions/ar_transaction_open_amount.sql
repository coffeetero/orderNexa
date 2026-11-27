-- ============================================================
-- ar_transaction_open_amount
-- What is still open on an AR document today: amount less live (not reversed) payment applications, less credit
-- applications that paid it, plus credit applications that used it (a credit memo moves toward zero), less its allowance and
-- its settled amount.
-- Positive = still owed (invoice); negative = credit still available.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_transaction_open_amount(p_tenant_id bigint, p_ar_transaction_id bigint)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT t.amount
         - COALESCE((SELECT SUM(pa.applied_amount) FROM bps.ar_payment_applications pa
                      WHERE pa.tenant_id = p_tenant_id AND pa.ar_transaction_id = t.ar_transaction_id AND pa.reversed_at IS NULL), 0)
         - COALESCE((SELECT SUM(ca.applied_amount) FROM bps.ar_credit_applications ca
                      WHERE ca.tenant_id = p_tenant_id AND ca.ar_transaction_id = t.ar_transaction_id AND ca.reversed_at IS NULL), 0)
         + COALESCE((SELECT SUM(ca.applied_amount) FROM bps.ar_credit_applications ca
                      WHERE ca.tenant_id = p_tenant_id AND ca.credit_ar_transaction_id = t.ar_transaction_id AND ca.reversed_at IS NULL), 0)
         - t.allowance_amount
         - t.settled_amount
    FROM bps.ar_transactions t
   WHERE t.tenant_id = p_tenant_id AND t.ar_transaction_id = p_ar_transaction_id
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_transaction_open_amount(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_transaction_open_amount(bigint, bigint) TO authenticated, service_role, bps_dev;
