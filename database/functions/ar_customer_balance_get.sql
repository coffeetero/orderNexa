-- ============================================================
-- ar_customer_balance_get
-- What a paying customer (an account, or a department that pays for itself) owes: recognised invoices (shipped lines)
-- of the customer and of everything beneath it that is not itself an ACCOUNT, minus credit memos, minus payments applied.
-- Staff only. Returns { recognized_invoices, credits, payments_applied, balance }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_customer_balance_get(p_tenant_id bigint, p_customer_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_inv  numeric;
    v_cred numeric;
    v_pay  numeric;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can see balances';
    END IF;

    WITH RECURSIVE tree AS (
        SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
         WHERE c.tenant_id = p_tenant_id AND UPPER(TRIM(c.customer_type)) <> 'ACCOUNT'
    ), docs AS (
        SELECT t.ar_transaction_id, t.transaction_type, t.amount FROM ar_transactions t
         WHERE t.tenant_id = p_tenant_id AND t.customer_id IN (SELECT customer_id FROM tree) AND t.status NOT IN ('DRAFT', 'CANCELLED')
    )
    SELECT COALESCE(SUM(d.amount) FILTER (WHERE d.transaction_type = 'INV'), 0),
           COALESCE(SUM(d.amount) FILTER (WHERE d.transaction_type = 'CM'), 0),
           COALESCE((SELECT SUM(pa.applied_amount) FROM ar_payment_applications pa WHERE pa.tenant_id = p_tenant_id
                        AND pa.ar_transaction_id IN (SELECT ar_transaction_id FROM docs WHERE transaction_type = 'INV')), 0)
      INTO v_inv, v_cred, v_pay
      FROM docs d;

    RETURN jsonb_build_object('recognized_invoices', v_inv, 'credits', v_cred, 'payments_applied', v_pay, 'balance', v_inv + v_cred - v_pay);
END;
$function$;
