-- ============================================================
-- ar_payment_apply
-- Applies a payment's unapplied cash, and optionally the customer's credits, to open invoices (Reapply; also used by
-- ar_payment_post for a new payment).
-- p_payload: { applications: [{ ar_transaction_id, amount }],   amount applied to each invoice (cash + credits)
--              credits:      [{ ar_transaction_id, amount }],   credit memos / negative invoices to use, fully
--              auto_apply:   true                               applications from ar_payment_allocate (oldest first)
--              applied_on:   date }                             set by ar_payment_post (the payment date); default today
-- Rules: invoices and credits belong to the payment's customer or beneath it (not another ACCOUNT); no invoice gets more
-- than its open amount; no credit gives more than it has left; credits used <= amount applied; the cash part <= the
-- payment's unapplied amount; a void payment cannot be applied. Credits are used on the oldest invoices first and are
-- recorded in ar_credit_applications (textbook credit application, never negative cash).
-- An application is dated the later of applied_on and the invoice (and credit) date, so as-of reports stay balanced.
-- Returns ar_payment_get.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_apply(p_tenant_id bigint, p_ar_payment_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user      bigint := bps.fnd_current_user_id();
  v_today     date := (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date;
  v_on        date;
  v_pay       ar_payments%ROWTYPE;
  v_apps      jsonb := COALESCE(p_payload -> 'applications', '[]'::jsonb);
  v_creds     jsonb := COALESCE(p_payload -> 'credits', '[]'::jsonb);
  v_tree      bigint[];
  v_unapplied numeric;
  v_sum_apps  numeric;
  v_sum_creds numeric;
  v_cred_ids  bigint[];
  v_cred_left numeric[];
  v_cred_date date[];
  v_need      numeric;
  v_take      numeric;
  r           record;
  i           integer;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'W') THEN RAISE EXCEPTION 'You do not have access to apply payments'; END IF;

  SELECT * INTO v_pay FROM ar_payments WHERE tenant_id = p_tenant_id AND ar_payment_id = p_ar_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment % not found', p_ar_payment_id; END IF;
  IF v_pay.voided_at IS NOT NULL THEN RAISE EXCEPTION 'Payment % is void and cannot be applied', COALESCE(v_pay.payment_number, v_pay.ar_payment_id::text); END IF;
  IF jsonb_typeof(v_apps) <> 'array' OR jsonb_typeof(v_creds) <> 'array' THEN RAISE EXCEPTION 'applications and credits must be lists'; END IF;

  IF COALESCE((p_payload ->> 'auto_apply')::boolean, false) THEN
    v_apps := bps.ar_payment_allocate(p_tenant_id, jsonb_build_object('ar_payment_id', p_ar_payment_id, 'credits', v_creds)) -> 'applications';
  END IF;
  IF jsonb_array_length(v_apps) = 0 THEN RAISE EXCEPTION 'Nothing to apply: enter an amount on at least one invoice'; END IF;

  v_on := COALESCE(NULLIF(p_payload ->> 'applied_on', '')::date, v_today);
  IF v_on < v_pay.payment_date OR v_on > v_today THEN RAISE EXCEPTION 'The application date must be between the payment date and today'; END IF;

  -- amounts: above zero, cents only, each document once
  IF EXISTS (SELECT 1 FROM jsonb_to_recordset(v_apps || v_creds) x(ar_transaction_id bigint, amount numeric)
              WHERE x.ar_transaction_id IS NULL OR x.amount IS NULL OR x.amount <= 0 OR round(x.amount, 2) <> x.amount) THEN
    RAISE EXCEPTION 'Each amount must be above zero, in dollars and cents';
  END IF;
  IF (SELECT count(*) <> count(DISTINCT x.ar_transaction_id) FROM jsonb_to_recordset(v_apps || v_creds) x(ar_transaction_id bigint)) THEN
    RAISE EXCEPTION 'A document appears more than once';
  END IF;

  -- lock the documents, then check them against the payment's customer tree (the AR reports' tree)
  PERFORM 1 FROM ar_transactions t
   WHERE t.tenant_id = p_tenant_id AND t.ar_transaction_id IN (SELECT x.ar_transaction_id FROM jsonb_to_recordset(v_apps || v_creds) x(ar_transaction_id bigint))
   ORDER BY t.ar_transaction_id FOR UPDATE;

  WITH RECURSIVE tree AS (
    SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = v_pay.customer_id
    UNION ALL
    SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ) SELECT array_agg(customer_id) INTO v_tree FROM tree;

  FOR r IN
    SELECT x.ar_transaction_id, x.amount, t.document_number, t.transaction_type, t.amount AS doc_amount, t.status, t.customer_id,
           bps.ar_transaction_open_amount(p_tenant_id, x.ar_transaction_id) AS open
      FROM jsonb_to_recordset(v_apps) x(ar_transaction_id bigint, amount numeric)
      LEFT JOIN ar_transactions t ON t.tenant_id = p_tenant_id AND t.ar_transaction_id = x.ar_transaction_id
  LOOP
    IF r.transaction_type IS NULL THEN RAISE EXCEPTION 'Invoice % not found', r.ar_transaction_id; END IF;
    IF r.transaction_type <> 'INV' OR r.doc_amount <= 0 THEN RAISE EXCEPTION 'Only invoices can be paid; % is a credit', r.document_number; END IF;
    IF r.status IN ('DRAFT', 'CANCELLED') THEN RAISE EXCEPTION 'Invoice % is % and cannot be paid', r.document_number, lower(r.status); END IF;
    IF NOT (r.customer_id = ANY (v_tree)) THEN RAISE EXCEPTION 'Invoice % belongs to another customer account', r.document_number; END IF;
    IF r.amount > r.open THEN
      RAISE EXCEPTION 'Cannot apply % to invoice %: only % is open', r.amount, r.document_number, round(GREATEST(r.open, 0), 2);
    END IF;
  END LOOP;

  FOR r IN
    SELECT x.ar_transaction_id, x.amount, t.document_number, t.transaction_type, t.amount AS doc_amount, t.status, t.customer_id, t.transaction_date,
           bps.ar_transaction_open_amount(p_tenant_id, x.ar_transaction_id) AS open
      FROM jsonb_to_recordset(v_creds) x(ar_transaction_id bigint, amount numeric)
      LEFT JOIN ar_transactions t ON t.tenant_id = p_tenant_id AND t.ar_transaction_id = x.ar_transaction_id
     ORDER BY t.transaction_date, t.document_number
  LOOP
    IF r.transaction_type IS NULL THEN RAISE EXCEPTION 'Credit % not found', r.ar_transaction_id; END IF;
    IF NOT (r.transaction_type = 'CM' OR r.doc_amount < 0) THEN RAISE EXCEPTION '% is not a credit', r.document_number; END IF;
    IF r.status IN ('DRAFT', 'CANCELLED') THEN RAISE EXCEPTION 'Credit % is % and cannot be used', r.document_number, lower(r.status); END IF;
    IF NOT (r.customer_id = ANY (v_tree)) THEN RAISE EXCEPTION 'Credit % belongs to another customer account', r.document_number; END IF;
    IF r.amount > -r.open THEN
      RAISE EXCEPTION 'Cannot use % of credit %: only % is left', r.amount, r.document_number, round(GREATEST(-r.open, 0), 2);
    END IF;
    v_cred_ids  := v_cred_ids || r.ar_transaction_id;
    v_cred_left := v_cred_left || r.amount;
    v_cred_date := v_cred_date || r.transaction_date;
  END LOOP;

  SELECT COALESCE(SUM(x.amount), 0) INTO v_sum_apps FROM jsonb_to_recordset(v_apps) x(amount numeric);
  SELECT COALESCE(SUM(x.amount), 0) INTO v_sum_creds FROM jsonb_to_recordset(v_creds) x(amount numeric);
  IF v_sum_creds > v_sum_apps THEN
    RAISE EXCEPTION 'Credits used (%) are more than the amount applied to invoices (%)', v_sum_creds, v_sum_apps;
  END IF;
  v_unapplied := v_pay.amount - COALESCE((SELECT SUM(pa.applied_amount) FROM ar_payment_applications pa
                                           WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = v_pay.ar_payment_id AND pa.reversed_at IS NULL), 0)
                 - v_pay.settled_amount;
  IF v_sum_apps - v_sum_creds > v_unapplied THEN
    RAISE EXCEPTION 'Applying % of cash is more than the payment has unapplied (%)', v_sum_apps - v_sum_creds, round(v_unapplied, 2);
  END IF;

  -- oldest invoices first: credits first, then cash
  FOR r IN
    SELECT x.ar_transaction_id, x.amount, t.transaction_date
      FROM jsonb_to_recordset(v_apps) x(ar_transaction_id bigint, amount numeric)
      JOIN ar_transactions t ON t.tenant_id = p_tenant_id AND t.ar_transaction_id = x.ar_transaction_id
     ORDER BY COALESCE(t.due_date, t.transaction_date), t.transaction_date, t.document_number
  LOOP
    v_need := r.amount;
    FOR i IN 1 .. COALESCE(array_length(v_cred_ids, 1), 0) LOOP
      EXIT WHEN v_need = 0;
      CONTINUE WHEN v_cred_left[i] = 0;
      v_take := LEAST(v_need, v_cred_left[i]);
      INSERT INTO ar_credit_applications (tenant_id, ar_payment_id, credit_ar_transaction_id, ar_transaction_id, applied_amount, applied_at, created_by, updated_by)
      VALUES (p_tenant_id, v_pay.ar_payment_id, v_cred_ids[i], r.ar_transaction_id, v_take,
              GREATEST(v_on, r.transaction_date, v_cred_date[i])::timestamptz, v_user, v_user);
      v_cred_left[i] := v_cred_left[i] - v_take;
      v_need := v_need - v_take;
    END LOOP;
    IF v_need > 0 THEN
      INSERT INTO ar_payment_applications (tenant_id, ar_payment_id, ar_transaction_id, applied_amount, applied_at, created_by, updated_by)
      VALUES (p_tenant_id, v_pay.ar_payment_id, r.ar_transaction_id, v_need, GREATEST(v_on, r.transaction_date)::timestamptz, v_user, v_user);
    END IF;
  END LOOP;

  UPDATE ar_payments SET updated_by = v_user WHERE ar_payment_id = v_pay.ar_payment_id;
  RETURN bps.ar_payment_get(p_tenant_id, v_pay.ar_payment_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_apply(bigint, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_apply(bigint, bigint, jsonb) TO authenticated, service_role, bps_dev;
