-- =====================================================================================
-- Saved documents (PDF stored in the database) and the Financials reports.
--   New table fnd_documents (immutable: insert and read only). New areas customers.documents (staff) and portal.documents (customer users).
--   Report functions: AR Open Balances, AR Aging, Customer Statement, Sales, Revenue Forecast; invoice document data.
-- Customers in every report are Accounts only (customer_type ACCOUNT); an account includes its sites and departments.
-- All functions are SECURITY INVOKER: row security limits every report to the caller's company and customer scope.
-- Apply after add_security_settings.sql.
-- =====================================================================================
SET search_path = bps, public;

CREATE TABLE bps.fnd_documents (
  document_id   BIGINT PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id     BIGINT NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  customer_id   BIGINT REFERENCES bps.fnd_customers(customer_id),   -- the account; NULL for a report that spans several customers
  document_type TEXT NOT NULL CHECK (document_type IN ('INVOICE','STATEMENT','AR_OPEN_BALANCES','AR_AGING','SALES','FORECAST')),
  title         TEXT NOT NULL,
  as_of_date    DATE NOT NULL,
  parameters    JSONB NOT NULL DEFAULT '{}'::jsonb,
  file_name     TEXT NOT NULL,
  content_type  TEXT NOT NULL DEFAULT 'application/pdf',
  file_bytes    BYTEA NOT NULL,
  byte_size     INTEGER NOT NULL CHECK (byte_size BETWEEN 1 AND 10485760),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by    BIGINT
);
CREATE INDEX fnd_documents_customer_idx ON bps.fnd_documents (tenant_id, customer_id, as_of_date DESC);
COMMENT ON TABLE bps.fnd_documents IS 'Saved PDF documents (invoices, statements, reports) with the parameters and as-of date they were run for. Never updated or deleted by the app.';

REVOKE ALL ON bps.fnd_documents FROM PUBLIC, anon;
GRANT SELECT, INSERT ON bps.fnd_documents TO authenticated;
GRANT ALL ON bps.fnd_documents TO bps_dev, service_role;
ALTER TABLE bps.fnd_documents ENABLE ROW LEVEL SECURITY;

-- Read: staff with customers.documents, customer users with portal.documents. Customer-scoped rows need the customer in the
-- caller's scope; a row with no customer (multi-customer report) is visible only to staff who may see all customers.
CREATE POLICY pol_fnd_documents_read ON bps.fnd_documents FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    ((SELECT bps.fnd_has_access('customers.documents','R')) AND (
        (SELECT bps.fnd_scope_is_all())
        OR (customer_id IS NOT NULL AND customer_id = ANY(COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[])))))
    OR ((SELECT bps.fnd_has_access('portal.documents','R')) AND customer_id IS NOT NULL
        AND customer_id = ANY(COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))))));
CREATE POLICY pol_fnd_documents_ins ON bps.fnd_documents FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('customers.documents','W')) AND (
    (SELECT bps.fnd_scope_is_all())
    OR (customer_id IS NOT NULL AND customer_id = ANY(COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))))));

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order) VALUES
  ('customers.documents', 'Customers', 'Customer Documents', 'TENANT', 304),
  ('portal.documents',    'Portal',    'Documents',          'CUSTOMER', 450)
ON CONFLICT (area_key) DO NOTHING;
DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ---------- picker: active Accounts the caller may see ----------
CREATE OR REPLACE FUNCTION bps.fnd_report_accounts_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('customer_id', c.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number)
                                    ORDER BY c.customer_name), '[]'::jsonb)
            FROM bps.fnd_customers c
           WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) = 'ACCOUNT' AND c.is_active);
END $$;

-- ---------- open items: invoices and credit memos with what is still owed as of a date ----------
-- INV open = recognized amount - payments applied up to the date; CM open = its (negative) amount. Due date falls back to the
-- document date. Recognition follows shipments as they stand now (it is not rewound to the as-of date).
CREATE OR REPLACE FUNCTION bps.ar_report_open_items(p_tenant_id bigint, p_account_ids bigint[], p_as_of date)
RETURNS TABLE (account_id bigint, ar_transaction_id bigint, document_number text, transaction_type text, transaction_date date,
               due_date date, amount numeric, paid numeric, open_amount numeric, days_past_due integer)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.ar_transaction_id, t.document_number, t.transaction_type, t.transaction_date,
           COALESCE(t.due_date, t.transaction_date) AS due_date,
           CASE t.transaction_type WHEN 'INV' THEN bps.ar_invoice_recognized_amount(t.ar_transaction_id) ELSE t.amount END AS amount,
           CASE t.transaction_type WHEN 'INV' THEN COALESCE((SELECT SUM(pa.applied_amount) FROM bps.ar_payment_applications pa
                 WHERE pa.tenant_id = p_tenant_id AND pa.ar_transaction_id = t.ar_transaction_id AND pa.applied_at::date <= p_as_of), 0) ELSE 0 END AS paid
      FROM bps.ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT','CANCELLED') AND t.transaction_type IN ('INV','CM') AND t.transaction_date <= p_as_of
  )
  SELECT d.account_id, d.ar_transaction_id, d.document_number, d.transaction_type, d.transaction_date, d.due_date, d.amount, d.paid,
         d.amount - d.paid, (p_as_of - d.due_date)
    FROM docs d
$$;

-- ---------- AR Open Balances ----------
CREATE OR REPLACE FUNCTION bps.ar_open_balances_get(p_tenant_id bigint, p_account_ids bigint[], p_as_of date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN jsonb_build_object('as_of', p_as_of, 'accounts', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('customer_id', c.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number,
      'balance', COALESCE((SELECT SUM(i.open_amount) FROM bps.ar_report_open_items(p_tenant_id, p_account_ids, p_as_of) i WHERE i.account_id = c.customer_id), 0),
      'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('document_number', i.document_number, 'type', i.transaction_type,
          'date', i.transaction_date, 'due_date', i.due_date, 'amount', i.amount, 'paid', i.paid, 'open', i.open_amount) ORDER BY i.transaction_date, i.document_number)
          FROM bps.ar_report_open_items(p_tenant_id, p_account_ids, p_as_of) i WHERE i.account_id = c.customer_id AND i.open_amount <> 0), '[]'::jsonb))
      ORDER BY c.customer_name)
      FROM bps.fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'), '[]'::jsonb));
END $$;

-- ---------- AR Aging (buckets by days past due) ----------
CREATE OR REPLACE FUNCTION bps.ar_aging_get(p_tenant_id bigint, p_account_ids bigint[], p_as_of date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_rows jsonb; v_tot jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  WITH items AS (SELECT * FROM bps.ar_report_open_items(p_tenant_id, p_account_ids, p_as_of) WHERE open_amount <> 0),
  per AS (
    SELECT c.customer_id, c.customer_name, c.customer_number,
      COALESCE(SUM(i.open_amount) FILTER (WHERE i.days_past_due <= 0), 0) AS current_amt,
      COALESCE(SUM(i.open_amount) FILTER (WHERE i.days_past_due BETWEEN 1 AND 30), 0) AS d1_30,
      COALESCE(SUM(i.open_amount) FILTER (WHERE i.days_past_due BETWEEN 31 AND 60), 0) AS d31_60,
      COALESCE(SUM(i.open_amount) FILTER (WHERE i.days_past_due BETWEEN 61 AND 90), 0) AS d61_90,
      COALESCE(SUM(i.open_amount) FILTER (WHERE i.days_past_due > 90), 0) AS d90_plus,
      COALESCE(SUM(i.open_amount), 0) AS total
      FROM bps.fnd_customers c LEFT JOIN items i ON i.account_id = c.customer_id
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
     GROUP BY c.customer_id, c.customer_name, c.customer_number)
  SELECT COALESCE(jsonb_agg(to_jsonb(per) ORDER BY per.customer_name), '[]'::jsonb),
         jsonb_build_object('current_amt', COALESCE(SUM(current_amt),0), 'd1_30', COALESCE(SUM(d1_30),0), 'd31_60', COALESCE(SUM(d31_60),0),
                            'd61_90', COALESCE(SUM(d61_90),0), 'd90_plus', COALESCE(SUM(d90_plus),0), 'total', COALESCE(SUM(total),0))
    INTO v_rows, v_tot FROM per;
  RETURN jsonb_build_object('as_of', p_as_of, 'accounts', v_rows, 'totals', v_tot);
END $$;

-- ---------- Customer Statement (one account): opening balance, activity from p_from to p_as_of with a running balance ----------
CREATE OR REPLACE FUNCTION bps.ar_statement_get(p_tenant_id bigint, p_account_id bigint, p_as_of date, p_from date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_cust record; v_open numeric; v_entries jsonb; v_close numeric; v_aging jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF p_from > p_as_of THEN RAISE EXCEPTION 'The statement start date is after the as-of date'; END IF;
  SELECT customer_id, customer_name, customer_number INTO v_cust FROM bps.fnd_customers
   WHERE tenant_id = p_tenant_id AND customer_id = p_account_id AND upper(btrim(customer_type)) = 'ACCOUNT';
  IF NOT FOUND THEN RAISE EXCEPTION 'Account not found'; END IF;

  WITH ent AS (
    SELECT i.transaction_date AS entry_date, i.transaction_type AS entry_type, i.document_number AS number,
           CASE WHEN i.transaction_type = 'INV' THEN i.amount ELSE 0 END AS charge, CASE WHEN i.transaction_type = 'CM' THEN -i.amount ELSE 0 END AS credit
      FROM bps.ar_report_open_items(p_tenant_id, ARRAY[p_account_id], p_as_of) i
    UNION ALL
    SELECT p.payment_date, 'PMT', COALESCE(p.payment_number, p.reference_number, 'Payment'), 0, p.amount
      FROM bps.ar_payments p
     WHERE p.tenant_id = p_tenant_id AND p.payment_date <= p_as_of
       AND p.customer_id IN (WITH RECURSIVE t(id) AS (SELECT p_account_id UNION ALL SELECT c.customer_id FROM bps.fnd_customers c JOIN t ON c.customer_parent_id = t.id
                              WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT') SELECT id FROM t)
  ), opening AS (SELECT COALESCE(SUM(charge - credit), 0) AS amt FROM ent WHERE entry_date < p_from),
  inrange AS (
    SELECT e.*, (SELECT amt FROM opening) + SUM(e.charge - e.credit) OVER (ORDER BY e.entry_date, e.entry_type, e.number ROWS UNBOUNDED PRECEDING) AS balance
      FROM ent e WHERE e.entry_date >= p_from)
  SELECT (SELECT amt FROM opening),
         COALESCE((SELECT jsonb_agg(jsonb_build_object('date', entry_date, 'type', entry_type, 'number', number, 'charge', charge, 'credit', credit, 'balance', balance)
                                    ORDER BY entry_date, entry_type, number) FROM inrange), '[]'::jsonb),
         (SELECT amt FROM opening) + COALESCE((SELECT SUM(charge - credit) FROM inrange), 0)
    INTO v_open, v_entries, v_close;

  SELECT (bps.ar_aging_get(p_tenant_id, ARRAY[p_account_id], p_as_of) -> 'totals') INTO v_aging;
  RETURN jsonb_build_object('customer_id', v_cust.customer_id, 'customer_name', v_cust.customer_name, 'customer_number', v_cust.customer_number,
    'from', p_from, 'as_of', p_as_of, 'opening_balance', v_open, 'entries', v_entries, 'closing_balance', v_close, 'aging', v_aging);
END $$;

-- ---------- Sales report: invoiced and credited per account in a date range, with item totals ----------
CREATE OR REPLACE FUNCTION bps.ar_sales_report_get(p_tenant_id bigint, p_account_ids bigint[], p_from date, p_to date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_rows jsonb; v_tot jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF p_from > p_to THEN RAISE EXCEPTION 'The from date is after the to date'; END IF;
  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.ar_transaction_id, t.transaction_type,
           CASE t.transaction_type WHEN 'INV' THEN bps.ar_invoice_recognized_amount(t.ar_transaction_id) ELSE t.amount END AS amt
      FROM bps.ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT','CANCELLED') AND t.transaction_type IN ('INV','CM')
       AND t.transaction_date BETWEEN p_from AND p_to
  ), items AS (
    SELECT d.account_id, COALESCE(NULLIF(btrim(l.item_description), ''), 'Item') AS item, SUM(l.quantity) AS qty, SUM(l.amount) AS amt
      FROM docs d JOIN bps.ar_transaction_lines l ON l.ar_transaction_id = d.ar_transaction_id
     WHERE d.transaction_type = 'INV' AND l.source_type = 'ITEM' GROUP BY d.account_id, 2
  ), per AS (
    SELECT c.customer_id, c.customer_name, c.customer_number,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_type = 'INV'), 0) AS invoiced,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_type = 'CM'), 0) AS credits,
      COALESCE(SUM(d.amt), 0) AS net,
      COALESCE((SELECT jsonb_agg(jsonb_build_object('item', i.item, 'quantity', i.qty, 'amount', i.amt) ORDER BY i.amt DESC)
                  FROM items i WHERE i.account_id = c.customer_id), '[]'::jsonb) AS items
      FROM bps.fnd_customers c LEFT JOIN docs d ON d.account_id = c.customer_id
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
     GROUP BY c.customer_id, c.customer_name, c.customer_number)
  SELECT COALESCE(jsonb_agg(to_jsonb(per) ORDER BY per.net DESC, per.customer_name), '[]'::jsonb),
         jsonb_build_object('invoiced', COALESCE(SUM(invoiced),0), 'credits', COALESCE(SUM(credits),0), 'net', COALESCE(SUM(net),0))
    INTO v_rows, v_tot FROM per;
  RETURN jsonb_build_object('from', p_from, 'to', p_to, 'accounts', v_rows, 'totals', v_tot);
END $$;

-- ---------- Revenue forecast from sales history: weekly average of net sales over the look-back weeks, projected flat ----------
-- Also reports the trend (last half of the look-back vs the first half) so a falling or rising account is visible.
CREATE OR REPLACE FUNCTION bps.ar_revenue_forecast_get(p_tenant_id bigint, p_account_ids bigint[], p_as_of date, p_lookback_weeks integer, p_horizon_weeks integer)
RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_from date; v_mid date; v_rows jsonb; v_tot jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF p_lookback_weeks NOT BETWEEN 2 AND 104 OR p_horizon_weeks NOT BETWEEN 1 AND 52 THEN RAISE EXCEPTION 'Look-back must be 2-104 weeks and horizon 1-52 weeks'; END IF;
  v_from := p_as_of - (p_lookback_weeks * 7) + 1;
  v_mid  := v_from + ((p_lookback_weeks / 2) * 7);
  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.transaction_date,
           CASE t.transaction_type WHEN 'INV' THEN bps.ar_invoice_recognized_amount(t.ar_transaction_id) ELSE t.amount END AS amt
      FROM bps.ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT','CANCELLED') AND t.transaction_type IN ('INV','CM')
       AND t.transaction_date BETWEEN v_from AND p_as_of
  ), per AS (
    SELECT c.customer_id, c.customer_name, c.customer_number,
      COALESCE(SUM(d.amt), 0) AS history_total,
      ROUND(COALESCE(SUM(d.amt), 0) / p_lookback_weeks, 2) AS weekly_average,
      ROUND(COALESCE(SUM(d.amt), 0) / p_lookback_weeks * p_horizon_weeks, 2) AS projected_total,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_date < v_mid), 0) AS first_half,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_date >= v_mid), 0) AS second_half
      FROM bps.fnd_customers c LEFT JOIN docs d ON d.account_id = c.customer_id
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
     GROUP BY c.customer_id, c.customer_name, c.customer_number)
  SELECT COALESCE(jsonb_agg(to_jsonb(per) ORDER BY per.projected_total DESC, per.customer_name), '[]'::jsonb),
         jsonb_build_object('history_total', COALESCE(SUM(history_total),0), 'weekly_average', COALESCE(SUM(weekly_average),0), 'projected_total', COALESCE(SUM(projected_total),0))
    INTO v_rows, v_tot FROM per;
  RETURN jsonb_build_object('as_of', p_as_of, 'history_from', v_from, 'lookback_weeks', p_lookback_weeks, 'horizon_weeks', p_horizon_weeks, 'accounts', v_rows, 'totals', v_tot);
END $$;

-- ---------- invoice document: header and lines for the PDF ----------
CREATE OR REPLACE FUNCTION bps.ar_invoice_document_get(p_tenant_id bigint, p_ar_transaction_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE t bps.ar_transactions; c bps.fnd_customers; v_lines jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT * INTO t FROM bps.ar_transactions WHERE tenant_id = p_tenant_id AND ar_transaction_id = p_ar_transaction_id AND transaction_type = 'INV';
  IF NOT FOUND THEN RAISE EXCEPTION 'Invoice not found'; END IF;
  SELECT * INTO c FROM bps.fnd_customers WHERE customer_id = COALESCE((SELECT top_customer_id FROM bps.fnd_customers WHERE customer_id = t.customer_id), t.customer_id);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('line', l.line_number, 'description', l.item_description, 'quantity', l.quantity, 'unit_price', l.unit_price, 'amount', l.amount) ORDER BY l.line_number), '[]'::jsonb)
    INTO v_lines FROM bps.ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id;
  RETURN jsonb_build_object('ar_transaction_id', t.ar_transaction_id, 'document_number', t.document_number, 'transaction_date', t.transaction_date,
    'due_date', t.due_date, 'status', t.status, 'customer_id', c.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number,
    'billed_customer_id', t.customer_id, 'amount', bps.ar_invoice_recognized_amount(t.ar_transaction_id), 'lines', v_lines,
    'company_name', (SELECT tenant_name FROM bps.fnd_tenants WHERE tenant_id = p_tenant_id));
END $$;

-- Issued invoices of an account (or its sites and departments) that have no saved PDF yet.
CREATE OR REPLACE FUNCTION bps.ar_invoices_unsaved_get(p_tenant_id bigint, p_account_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (WITH RECURSIVE tree(id) AS (
      SELECT c.customer_id FROM bps.fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_account_id AND upper(btrim(c.customer_type)) = 'ACCOUNT'
      UNION ALL SELECT c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.id
       WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT')
    SELECT COALESCE(jsonb_agg(t.ar_transaction_id ORDER BY t.transaction_date, t.document_number), '[]'::jsonb)
      FROM bps.ar_transactions t
     WHERE t.tenant_id = p_tenant_id AND t.customer_id IN (SELECT id FROM tree) AND t.transaction_type = 'INV' AND t.status NOT IN ('DRAFT','CANCELLED')
       AND NOT EXISTS (SELECT 1 FROM bps.fnd_documents d WHERE d.tenant_id = p_tenant_id AND d.document_type = 'INVOICE'
                          AND d.parameters ->> 'ar_transaction_id' = t.ar_transaction_id::text));
END $$;

-- ---------- documents: save, list, fetch ----------
-- payload: {document_type, title, as_of_date, customer_id?, parameters?, file_name, content_base64}
CREATE OR REPLACE FUNCTION bps.fnd_document_save(p_tenant_id bigint, p_payload jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_bytes bytea; v_id bigint;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  v_bytes := decode(COALESCE(p_payload ->> 'content_base64', ''), 'base64');
  IF length(v_bytes) = 0 THEN RAISE EXCEPTION 'The document is empty'; END IF;
  INSERT INTO bps.fnd_documents (tenant_id, customer_id, document_type, title, as_of_date, parameters, file_name, file_bytes, byte_size, created_by)
  VALUES (p_tenant_id, NULLIF(p_payload ->> 'customer_id', '')::bigint, upper(p_payload ->> 'document_type'), btrim(p_payload ->> 'title'),
          (p_payload ->> 'as_of_date')::date, COALESCE(p_payload -> 'parameters', '{}'::jsonb), p_payload ->> 'file_name', v_bytes, length(v_bytes),
          bps.fnd_current_user_id())
  RETURNING document_id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_documents_get(p_tenant_id bigint, p_customer_id bigint, p_types text[]) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('document_id', d.document_id, 'customer_id', d.customer_id, 'document_type', d.document_type,
            'title', d.title, 'as_of_date', d.as_of_date, 'parameters', d.parameters, 'file_name', d.file_name, 'byte_size', d.byte_size,
            'created_at', d.created_at) ORDER BY d.as_of_date DESC, d.document_id DESC), '[]'::jsonb)
            FROM bps.fnd_documents d
           WHERE d.tenant_id = p_tenant_id AND (p_customer_id IS NULL OR d.customer_id = p_customer_id)
             AND (p_types IS NULL OR d.document_type = ANY(p_types)));
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_document_get(p_tenant_id bigint, p_document_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE d bps.fnd_documents;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT * INTO d FROM bps.fnd_documents WHERE tenant_id = p_tenant_id AND document_id = p_document_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Document not found'; END IF;
  RETURN jsonb_build_object('document_id', d.document_id, 'file_name', d.file_name, 'content_type', d.content_type,
                            'content_base64', encode(d.file_bytes, 'base64'));
END $$;

REVOKE EXECUTE ON FUNCTION
  bps.fnd_report_accounts_get(bigint), bps.ar_report_open_items(bigint, bigint[], date), bps.ar_open_balances_get(bigint, bigint[], date),
  bps.ar_aging_get(bigint, bigint[], date), bps.ar_statement_get(bigint, bigint, date, date), bps.ar_sales_report_get(bigint, bigint[], date, date),
  bps.ar_revenue_forecast_get(bigint, bigint[], date, integer, integer), bps.ar_invoice_document_get(bigint, bigint), bps.ar_invoices_unsaved_get(bigint, bigint),
  bps.fnd_document_save(bigint, jsonb), bps.fnd_documents_get(bigint, bigint, text[]), bps.fnd_document_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  bps.fnd_report_accounts_get(bigint), bps.ar_report_open_items(bigint, bigint[], date), bps.ar_open_balances_get(bigint, bigint[], date),
  bps.ar_aging_get(bigint, bigint[], date), bps.ar_statement_get(bigint, bigint, date, date), bps.ar_sales_report_get(bigint, bigint[], date, date),
  bps.ar_revenue_forecast_get(bigint, bigint[], date, integer, integer), bps.ar_invoice_document_get(bigint, bigint), bps.ar_invoices_unsaved_get(bigint, bigint),
  bps.fnd_document_save(bigint, jsonb), bps.fnd_documents_get(bigint, bigint, text[]), bps.fnd_document_get(bigint, bigint) TO authenticated, service_role, bps_dev;
