-- ============================================================
-- fnd_hc_payments_over_applied
-- Health check: payments whose live (not reversed) applications exceed the payment amount.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_hc_payments_over_applied(p_tenant_id bigint)
 RETURNS TABLE(type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
  SELECT 'Error', 'Payment ' || COALESCE(p.payment_number, p.ar_payment_id::text) || ' of ' || p.amount || ' has ' || sum(a.applied_amount) || ' applied to invoices.',
         'Correct the payment applications so they do not exceed the payment.', 'PAYMENT', p.ar_payment_id, p.customer_id, '/financials/payments?id=' || p.ar_payment_id
    FROM bps.ar_payments p JOIN bps.ar_payment_applications a ON a.ar_payment_id = p.ar_payment_id AND a.reversed_at IS NULL
   WHERE p.tenant_id = p_tenant_id
   GROUP BY p.ar_payment_id, p.payment_number, p.amount, p.customer_id
  HAVING sum(a.applied_amount) > p.amount
$function$;
