-- ============================================================
-- Financials › AR Open Balances
--
-- ar_open_balances_get(tenant, accounts, as_of)   the report (PDF): each account's open items and balance.
--   Works out the open items once for all accounts (it used to repeat them twice per account).
-- ar_open_accounts_get(tenant, as_of)             the customer list: active accounts with something open as of the date, with the balance.
-- ar_open_item_details_get(tenant, account, as_of) the details below the list: the account's open items, each with what was applied to it
--   (payments and credits) and, for each of those, the other documents the same payment or credit covered. Same as-of rules as
--   ar_report_open_items: an application counts from the day it was applied until the day it was reversed.
-- For today these read bps.ar_open_items (fast); for an earlier date ar_report_open_items recalculates from the documents.
-- SECURITY INVOKER: row security limits everything to the caller's company and customer scope. No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_open_balances_get(p_tenant_id bigint, p_account_ids bigint[], p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (WITH items AS (SELECT * FROM bps.ar_report_open_items(p_tenant_id, p_account_ids, p_as_of) i WHERE i.open_amount <> 0)
    SELECT jsonb_build_object('as_of', p_as_of, 'accounts', COALESCE(jsonb_agg(jsonb_build_object(
             'customer_id', c.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number,
             'balance', COALESCE((SELECT SUM(i.open_amount) FROM items i WHERE i.account_id = c.customer_id), 0),
             'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('document_number', i.document_number, 'type', i.transaction_type,
                 'date', i.transaction_date, 'due_date', i.due_date, 'amount', i.amount, 'paid', i.paid, 'open', i.open_amount)
                 ORDER BY i.transaction_date, i.document_number) FROM items i WHERE i.account_id = c.customer_id), '[]'::jsonb))
             ORDER BY c.customer_name), '[]'::jsonb))
      FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT');
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_open_balances_get(bigint, bigint[], date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_open_balances_get(bigint, bigint[], date) TO authenticated, service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.ar_open_accounts_get(p_tenant_id bigint, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_ids bigint[];
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT COALESCE(array_agg(c.customer_id), '{}') INTO v_ids FROM bps.fnd_customers c
   WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) = 'ACCOUNT' AND c.is_active;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('customer_id', c.customer_id, 'customer_name', c.customer_name,
                                                       'customer_number', c.customer_number, 'balance', b.balance) ORDER BY c.customer_name), '[]'::jsonb)
            FROM (SELECT i.account_id, SUM(i.open_amount) AS balance FROM bps.ar_report_open_items(p_tenant_id, v_ids, p_as_of) i
                   WHERE i.open_amount <> 0 GROUP BY i.account_id HAVING SUM(i.open_amount) <> 0) b
            JOIN bps.fnd_customers c ON c.customer_id = b.account_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_open_accounts_get(bigint, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_open_accounts_get(bigint, date) TO authenticated, service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.ar_open_item_details_get(p_tenant_id bigint, p_account_id bigint, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_tz text;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  v_tz := COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC');
  RETURN (WITH items AS (
      SELECT * FROM bps.ar_report_open_items(p_tenant_id, ARRAY[p_account_id], p_as_of) i WHERE i.open_amount <> 0
    ),
    -- live applications as of the date: payment applications, and credit applications seen from both sides
    pa AS (
      SELECT a.ar_payment_id, a.ar_transaction_id, a.applied_amount, (a.applied_at AT TIME ZONE v_tz)::date AS applied_on
        FROM bps.ar_payment_applications a
       WHERE a.tenant_id = p_tenant_id AND a.applied_at::date <= p_as_of
         AND (a.reversed_at IS NULL OR (a.reversed_at AT TIME ZONE v_tz)::date > p_as_of)
         AND (a.ar_payment_id IN (SELECT a2.ar_payment_id FROM bps.ar_payment_applications a2 JOIN items ON a2.ar_transaction_id = items.ar_transaction_id
                                   WHERE a2.tenant_id = p_tenant_id)
              OR a.ar_payment_id IN (SELECT items.ar_payment_id FROM items WHERE items.ar_payment_id IS NOT NULL))
    ),
    ca AS (
      SELECT a.credit_ar_transaction_id, a.ar_transaction_id, a.applied_amount, (a.applied_at AT TIME ZONE v_tz)::date AS applied_on
        FROM bps.ar_credit_applications a
       WHERE a.tenant_id = p_tenant_id AND a.applied_at::date <= p_as_of
         AND (a.reversed_at IS NULL OR (a.reversed_at AT TIME ZONE v_tz)::date > p_as_of)
         AND (a.ar_transaction_id IN (SELECT items.ar_transaction_id FROM items) OR a.credit_ar_transaction_id IN (SELECT items.ar_transaction_id FROM items))
    ),
    doc AS (   -- document names for invoices / credit memos and payments
      SELECT t.ar_transaction_id AS t_id, NULL::bigint AS p_id, t.document_number AS number, t.transaction_type AS type, t.transaction_date AS date, t.amount
        FROM bps.ar_transactions t
       WHERE t.tenant_id = p_tenant_id AND (t.ar_transaction_id IN (SELECT pa.ar_transaction_id FROM pa)
                                            OR t.ar_transaction_id IN (SELECT ca.ar_transaction_id FROM ca)
                                            OR t.ar_transaction_id IN (SELECT ca.credit_ar_transaction_id FROM ca))
      UNION ALL
      SELECT NULL, p.ar_payment_id, COALESCE(p.payment_number, p.reference_number, 'Payment'), 'PMT', p.payment_date, p.amount
        FROM bps.ar_payments p WHERE p.tenant_id = p_tenant_id AND p.ar_payment_id IN (SELECT pa.ar_payment_id FROM pa)
    )
    SELECT jsonb_build_object(
      'as_of', p_as_of,
      'customer_id', c.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number,
      'balance', COALESCE((SELECT SUM(open_amount) FROM items), 0),
      'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'ar_transaction_id', i.ar_transaction_id, 'ar_payment_id', i.ar_payment_id,
          'document_number', i.document_number, 'type', i.transaction_type, 'date', i.transaction_date, 'due_date', i.due_date,
          'amount', i.amount, 'paid', i.paid, 'open', i.open_amount, 'days_past_due', i.days_past_due,
          'applied', CASE WHEN i.ar_payment_id IS NOT NULL THEN
              -- an unapplied payment: the documents it was applied to
              COALESCE((SELECT jsonb_agg(jsonb_build_object('number', d.number, 'type', d.type, 'date', d.date, 'amount', d.amount,
                                                            'applied_on', x.applied_on, 'applied', x.applied_amount, 'covers', '[]'::jsonb)
                                         ORDER BY x.applied_on, d.number)
                          FROM pa x JOIN doc d ON d.t_id = x.ar_transaction_id WHERE x.ar_payment_id = i.ar_payment_id), '[]'::jsonb)
            ELSE
              -- an invoice or credit memo: the payments and credits applied to it, each with the other documents it covered
              COALESCE((SELECT jsonb_agg(z.j ORDER BY z.applied_on, z.number) FROM (
                SELECT x.applied_on, d.number, jsonb_build_object('number', d.number, 'type', d.type, 'date', d.date, 'amount', d.amount,
                         'applied_on', x.applied_on, 'applied', x.applied_amount,
                         'covers', COALESCE((SELECT jsonb_agg(jsonb_build_object('number', d2.number, 'type', d2.type, 'date', d2.date, 'applied', y.applied_amount)
                                                              ORDER BY d2.date, d2.number)
                                               FROM pa y JOIN doc d2 ON d2.t_id = y.ar_transaction_id
                                              WHERE y.ar_payment_id = x.ar_payment_id AND y.ar_transaction_id <> i.ar_transaction_id), '[]'::jsonb)) AS j
                  FROM pa x JOIN doc d ON d.p_id = x.ar_payment_id WHERE x.ar_transaction_id = i.ar_transaction_id
                UNION ALL
                -- a credit memo that paid this invoice
                SELECT x.applied_on, d.number, jsonb_build_object('number', d.number, 'type', d.type, 'date', d.date, 'amount', d.amount,
                         'applied_on', x.applied_on, 'applied', x.applied_amount,
                         'covers', COALESCE((SELECT jsonb_agg(jsonb_build_object('number', d2.number, 'type', d2.type, 'date', d2.date, 'applied', y.applied_amount)
                                                              ORDER BY d2.date, d2.number)
                                               FROM ca y JOIN doc d2 ON d2.t_id = y.ar_transaction_id
                                              WHERE y.credit_ar_transaction_id = x.credit_ar_transaction_id AND y.ar_transaction_id <> i.ar_transaction_id), '[]'::jsonb))
                  FROM ca x JOIN doc d ON d.t_id = x.credit_ar_transaction_id WHERE x.ar_transaction_id = i.ar_transaction_id
                UNION ALL
                -- this is a credit memo: the invoices it paid
                SELECT x.applied_on, d.number, jsonb_build_object('number', d.number, 'type', d.type, 'date', d.date, 'amount', d.amount,
                         'applied_on', x.applied_on, 'applied', -x.applied_amount, 'covers', '[]'::jsonb)
                  FROM ca x JOIN doc d ON d.t_id = x.ar_transaction_id WHERE x.credit_ar_transaction_id = i.ar_transaction_id
              ) z), '[]'::jsonb)
            END)
          ORDER BY i.transaction_date, i.document_number) FROM items i), '[]'::jsonb))
      FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_account_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_open_item_details_get(bigint, bigint, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_open_item_details_get(bigint, bigint, date) TO authenticated, service_role, bps_dev;
