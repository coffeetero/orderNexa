-- ============================================================
-- fnd_hc_ar_open_items_drift
-- Health check: documents whose stored open balance (bps.ar_open_items, kept by triggers) differs from a full recalculation from the
-- invoices, payments and applications. Any finding means a write path was missed; recalculate with
--   SELECT bps.ar_open_items_refresh(<tenant>, ARRAY[<ar_transaction_id>], NULL)   or   (<tenant>, NULL, ARRAY[<ar_payment_id>])
-- plpgsql so it can be loaded before the table exists.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_hc_ar_open_items_drift(p_tenant_id bigint)
 RETURNS TABLE(type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH actual AS (
    SELECT t.ar_transaction_id AS t_id, NULL::bigint AS p_id, t.customer_id, t.document_number AS doc,
           t.amount - COALESCE(pa.s, 0) - COALESCE(ci.s, 0) + COALESCE(cc.s, 0) AS open_amount
      FROM bps.ar_transactions t
      LEFT JOIN (SELECT a.ar_transaction_id, sum(a.applied_amount) s FROM bps.ar_payment_applications a
                  WHERE a.tenant_id = p_tenant_id AND a.reversed_at IS NULL GROUP BY 1) pa ON pa.ar_transaction_id = t.ar_transaction_id
      LEFT JOIN (SELECT a.ar_transaction_id, sum(a.applied_amount) s FROM bps.ar_credit_applications a
                  WHERE a.tenant_id = p_tenant_id AND a.reversed_at IS NULL GROUP BY 1) ci ON ci.ar_transaction_id = t.ar_transaction_id
      LEFT JOIN (SELECT a.credit_ar_transaction_id, sum(a.applied_amount) s FROM bps.ar_credit_applications a
                  WHERE a.tenant_id = p_tenant_id AND a.reversed_at IS NULL GROUP BY 1) cc ON cc.credit_ar_transaction_id = t.ar_transaction_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT', 'CANCELLED') AND t.transaction_type IN ('INV', 'CM')
    UNION ALL
    SELECT NULL, p.ar_payment_id, p.customer_id, COALESCE(p.payment_number, p.reference_number, p.ar_payment_id::text),
           -p.amount + COALESCE(pa.s, 0)
      FROM bps.ar_payments p
      LEFT JOIN (SELECT a.ar_payment_id, sum(a.applied_amount) s FROM bps.ar_payment_applications a
                  WHERE a.tenant_id = p_tenant_id AND a.reversed_at IS NULL GROUP BY 1) pa ON pa.ar_payment_id = p.ar_payment_id
     WHERE p.tenant_id = p_tenant_id AND p.voided_at IS NULL
  ), cmp AS (
    SELECT COALESCE(a.t_id, o.ar_transaction_id) AS t_id, COALESCE(a.p_id, o.ar_payment_id) AS p_id,
           COALESCE(a.customer_id, o.customer_id) AS customer_id, a.doc,
           COALESCE(o.open_amount, 0) AS stored, COALESCE(a.open_amount, 0) AS actual
      FROM (SELECT * FROM actual WHERE actual.open_amount <> 0) a
      FULL JOIN (SELECT * FROM bps.ar_open_items x WHERE x.tenant_id = p_tenant_id) o
        ON COALESCE(o.ar_transaction_id, -o.ar_payment_id) = COALESCE(a.t_id, -a.p_id)   -- one key: invoices positive, payments negative
  )
  SELECT 'Error',
         CASE WHEN c.p_id IS NULL THEN 'Invoice ' ELSE 'Payment ' END || COALESCE(c.doc, COALESCE(c.t_id, c.p_id)::text)
           || ': stored open balance ' || round(c.stored, 2) || ', actual ' || round(c.actual, 2) || '.',
         'Recalculate the document''s open balance (bps.ar_open_items_refresh). Report how it happened so the missed update can be fixed.',
         CASE WHEN c.p_id IS NULL THEN 'AR_TRANSACTION' ELSE 'PAYMENT' END, COALESCE(c.t_id, c.p_id), c.customer_id,
         CASE WHEN c.p_id IS NULL THEN NULL ELSE '/financials/payments?id=' || c.p_id END
    FROM cmp c
   WHERE c.stored <> c.actual
   ORDER BY COALESCE(c.t_id, c.p_id)
   LIMIT 500;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_hc_ar_open_items_drift(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_hc_ar_open_items_drift(bigint) TO authenticated, service_role, bps_dev;
