-- ============================================================
-- ar_payment_enter (Financials › Enter Payments)
-- Saves one check (or cash) as entered on Enter Payments, in one transaction: allowances on their invoices, then the payment
-- with its applications and the credits it takes (ar_payment_post). Nothing is saved when any part is refused.
-- p_payload: { customer_id, payment_date, check_no ('CASH' for cash), amount, allow_duplicate?,
--              lines: [{ ar_transaction_id | ar_payment_id, payment, allowance?, allowance_reason? }] }
--   payment > 0 on an invoice     applies that much of the money taken (check, earlier cash, credits) to it
--   payment on a credit           (a credit memo or negative invoice) takes the whole credit: it adds to what the check can pay
--   ar_payment_id line            takes an earlier payment's unapplied cash, whole: it adds to what the check can pay
--   allowance on an invoice       adds to the invoice's allowance (with a reason saying why and which items)
-- Oldest money first: earlier payments' unapplied cash is applied to the invoices first (in line order; ar_payment_apply on
-- that payment), except what the credits taken need, then the new payment (check plus credits) covers the rest. Whatever
-- is not used stays unapplied: on the earlier payment if its cash was not needed, otherwise on the new check.
-- Rules: an invoice never gets more than is open on it (payment + allowance); a reason is needed with an allowance; the
-- documents belong to the customer or beneath it; ar_payment_post / ar_payment_apply keep their own rules (date, amount,
-- duplicate check number, a check needs its number, credits used <= applied). With no new money and no credits no payment is
-- made (only allowances and earlier cash reapplied).
-- Returns ar_payment_get plus { reapplied }, or { allowances_only: true, count, reapplied } when no new payment was needed.
-- SECURITY INVOKER: row security and financials.payments write decide what the caller may do.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_enter(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user     bigint  := bps.fnd_current_user_id();
  v_customer bigint  := NULLIF(p_payload ->> 'customer_id', '')::bigint;
  v_check    text    := NULLIF(btrim(p_payload ->> 'check_no'), '');
  v_amount   numeric := COALESCE(NULLIF(p_payload ->> 'amount', '')::numeric, 0);
  v_apps     jsonb   := '[]'::jsonb;
  v_credits  jsonb   := '[]'::jsonb;
  v_allow    integer := 0;
  v_olds     jsonb   := '[]'::jsonb;   -- earlier payments taken: [{ ar_payment_id, unapplied }]
  v_old_cash numeric := 0;
  v_credit   numeric := 0;
  v_room     numeric;
  v_take     numeric;
  v_rest     jsonb;
  v_part     jsonb;
  v_reapplied integer := 0;
  o          jsonb;
  a          jsonb;
  v_unapp    numeric;
  v_result   jsonb;
  l          jsonb;
  v_doc      record;
  v_pay      numeric;
  v_alw      numeric;
  v_reason   text;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'W') THEN RAISE EXCEPTION 'You do not have access to enter payments'; END IF;
  IF v_customer IS NULL THEN RAISE EXCEPTION 'Choose a customer'; END IF;

  FOR l IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload -> 'lines', '[]'::jsonb)) LOOP
    v_pay := round(COALESCE(NULLIF(l ->> 'payment', '')::numeric, 0), 2);
    v_alw := round(COALESCE(NULLIF(l ->> 'allowance', '')::numeric, 0), 2);
    v_reason := NULLIF(btrim(l ->> 'allowance_reason'), '');
    CONTINUE WHEN v_pay = 0 AND v_alw = 0;

    IF NULLIF(l ->> 'ar_payment_id', '') IS NOT NULL THEN
      -- an earlier payment of the customer (or beneath it) with unapplied cash: taken whole
      WITH RECURSIVE tree AS (
        SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = v_customer
        UNION ALL
        SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
         WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT')
      SELECT round(p.amount - COALESCE((SELECT SUM(pa.applied_amount) FROM ar_payment_applications pa
                                         WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id AND pa.reversed_at IS NULL), 0)
                   - p.settled_amount, 2)
        INTO v_unapp
        FROM ar_payments p JOIN tree ON tree.customer_id = p.customer_id
       WHERE p.tenant_id = p_tenant_id AND p.ar_payment_id = (l ->> 'ar_payment_id')::bigint AND p.voided_at IS NULL;
      IF COALESCE(v_unapp, 0) <= 0 THEN RAISE EXCEPTION 'An earlier payment on this check has no unapplied cash left. Refresh and try again.'; END IF;
      v_olds := v_olds || jsonb_build_object('ar_payment_id', (l ->> 'ar_payment_id')::bigint, 'unapplied', v_unapp);
      v_old_cash := v_old_cash + v_unapp;
      CONTINUE;
    END IF;

    -- the document must be open and belong to the customer or beneath it (not another account)
    WITH RECURSIVE tree AS (
      SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = v_customer
      UNION ALL
      SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
       WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT')
    SELECT t.ar_transaction_id, t.transaction_type, t.document_number, o.open_amount
      INTO v_doc
      FROM ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
      JOIN ar_open_items o ON o.ar_transaction_id = t.ar_transaction_id
     WHERE t.tenant_id = p_tenant_id AND t.ar_transaction_id = NULLIF(l ->> 'ar_transaction_id', '')::bigint;
    IF NOT FOUND THEN RAISE EXCEPTION 'A transaction on this payment is no longer open. Refresh and try again.'; END IF;

    IF v_doc.open_amount < 0 THEN
      -- a credit memo or negative invoice: taken whole
      IF v_alw <> 0 THEN RAISE EXCEPTION 'An allowance cannot go on credit %', v_doc.document_number; END IF;
      v_credits := v_credits || jsonb_build_object('ar_transaction_id', v_doc.ar_transaction_id, 'amount', -v_doc.open_amount);
      v_credit := v_credit - v_doc.open_amount;
    ELSE
      IF v_pay < 0 OR v_alw < 0 THEN RAISE EXCEPTION 'Amounts on invoice % cannot be negative', v_doc.document_number; END IF;
      IF v_pay + v_alw > v_doc.open_amount THEN
        RAISE EXCEPTION 'Invoice % has % open; the payment and allowance add up to more', v_doc.document_number, round(v_doc.open_amount, 2);
      END IF;
      IF v_alw > 0 THEN
        IF v_reason IS NULL THEN RAISE EXCEPTION 'Say why the allowance on invoice % was given', v_doc.document_number; END IF;
        UPDATE ar_transactions
           SET allowance_amount = allowance_amount + v_alw,
               allowance_reason = CASE WHEN NULLIF(btrim(allowance_reason), '') IS NULL THEN v_reason ELSE allowance_reason || ' | ' || v_reason END,
               allowance_at = now(), allowance_by = v_user, updated_by = v_user
         WHERE tenant_id = p_tenant_id AND ar_transaction_id = v_doc.ar_transaction_id;
        v_allow := v_allow + 1;
      END IF;
      IF v_pay > 0 THEN
        v_apps := v_apps || jsonb_build_object('ar_transaction_id', v_doc.ar_transaction_id, 'amount', v_pay);
      END IF;
    END IF;
  END LOOP;

  -- earlier cash first: each earlier payment covers invoices in line order, leaving what the credits taken need
  v_room := GREATEST((SELECT COALESCE(SUM((x ->> 'amount')::numeric), 0) FROM jsonb_array_elements(v_apps) x) - v_credit, 0);
  FOR o IN SELECT * FROM jsonb_array_elements(v_olds) LOOP
    v_take := LEAST((o ->> 'unapplied')::numeric, v_room);
    CONTINUE WHEN v_take <= 0;
    v_part := '[]'::jsonb; v_rest := '[]'::jsonb;
    FOR a IN SELECT * FROM jsonb_array_elements(v_apps) LOOP
      IF v_take > 0 THEN
        v_pay := LEAST((a ->> 'amount')::numeric, v_take);
        v_part := v_part || jsonb_build_object('ar_transaction_id', a -> 'ar_transaction_id', 'amount', v_pay);
        v_take := v_take - v_pay; v_room := v_room - v_pay;
        IF (a ->> 'amount')::numeric > v_pay THEN
          v_rest := v_rest || jsonb_build_object('ar_transaction_id', a -> 'ar_transaction_id', 'amount', (a ->> 'amount')::numeric - v_pay);
        END IF;
      ELSE
        v_rest := v_rest || a;
      END IF;
    END LOOP;
    PERFORM bps.ar_payment_apply(p_tenant_id, (o ->> 'ar_payment_id')::bigint, jsonb_build_object('applications', v_part));
    v_apps := v_rest;
    v_reapplied := v_reapplied + 1;
  END LOOP;

  IF v_amount = 0 AND jsonb_array_length(v_credits) = 0 THEN
    IF jsonb_array_length(v_apps) > 0 THEN RAISE EXCEPTION 'Enter the check amount'; END IF;
    IF v_allow = 0 AND v_reapplied = 0 THEN RAISE EXCEPTION 'Nothing to save'; END IF;
    RETURN jsonb_build_object('allowances_only', true, 'count', v_allow, 'reapplied', v_reapplied);
  END IF;

  v_result := bps.ar_payment_post(p_tenant_id, jsonb_build_object(
    'customer_id', v_customer,
    'payment_date', p_payload ->> 'payment_date',
    'payment_method', CASE WHEN upper(COALESCE(v_check, '')) = 'CASH' THEN 'CASH' ELSE 'CHECK' END,
    'reference_number', CASE WHEN upper(COALESCE(v_check, '')) = 'CASH' THEN NULL ELSE v_check END,
    'amount', v_amount,
    'applications', v_apps,
    'credits', v_credits,
    'allow_duplicate', COALESCE((p_payload ->> 'allow_duplicate')::boolean, false)));
  RETURN v_result || jsonb_build_object('reapplied', v_reapplied);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_enter(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_enter(bigint, jsonb) TO authenticated, service_role, bps_dev;
