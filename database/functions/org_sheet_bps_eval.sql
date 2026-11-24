-- ============================================================
-- org_sheet_bps_eval
-- Evaluates the BPS functions used in a sheet, in one call. Runs as the signed-in user (row security applies) and checks
-- the access area each function needs; without it the result is #ACCESS.
-- p_calls: [{ fn, args: [...] }]   (dates as YYYY-MM-DD, numbers as text or numbers)
-- Returns an array in the same order: { v: value } or { e: '#ACCESS' | '#N/A' | '#VALUE!' | '#NAME?' , message }.
--   SALES(from, [to])                 net sales (invoices less credits issued, not DRAFT/CANCELLED) dated in the range
--   BALANCE(customer_no)              the customer's account balance today (open invoices less credits and unapplied payments)
--   AGING(customer_no, bucket)        one aging bucket of that balance: current, 1-30, 31-60, 61-90, 90+ or total
--   ITEM_PRICE(item_no, customer_no, [date])   the item's price for the customer on a delivery date (default today)
--   QTY_ORDERED(item_no, date, [code])         quantity ordered for a production date (and code); unapproved imports excluded
-- At most 500 calls per request.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_sheet_bps_eval(p_tenant_id bigint, p_calls jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  c       jsonb;
  fn      text;
  a       jsonb;
  v_out   jsonb := '[]'::jsonb;
  v_res   jsonb;
  v_cust  record;
  v_item  bigint;
  v_num   numeric;
  v_stmt  jsonb;
  v_key   text;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF jsonb_typeof(p_calls) <> 'array' THEN RAISE EXCEPTION 'calls must be an array'; END IF;
  IF jsonb_array_length(p_calls) > 500 THEN RAISE EXCEPTION 'Too many BPS functions in one sheet (over 500)'; END IF;

  FOR c IN SELECT x FROM jsonb_array_elements(p_calls) x LOOP
    fn := upper(btrim(COALESCE(c ->> 'fn', '')));
    a  := COALESCE(c -> 'args', '[]'::jsonb);
    BEGIN
      v_res := NULL;
      IF fn = 'SALES' THEN
        IF NOT bps.fnd_has_access('financials.sales', 'R') THEN v_res := jsonb_build_object('e', '#ACCESS');
        ELSE
          SELECT COALESCE(SUM(t.amount), 0) INTO v_num FROM ar_transactions t
           WHERE t.tenant_id = p_tenant_id AND t.transaction_type IN ('INV', 'CM') AND t.status NOT IN ('DRAFT', 'CANCELLED')
             AND t.transaction_date BETWEEN (a ->> 0)::date AND COALESCE(NULLIF(a ->> 1, ''), a ->> 0)::date;
          v_res := jsonb_build_object('v', v_num);
        END IF;

      ELSIF fn IN ('BALANCE', 'AGING') THEN
        IF NOT bps.fnd_has_access(CASE fn WHEN 'BALANCE' THEN 'financials.ar' ELSE 'financials.aging' END, 'R') THEN
          v_res := jsonb_build_object('e', '#ACCESS');
        ELSE
          SELECT c2.customer_id, COALESCE(c2.top_customer_id, c2.customer_id) AS account_id INTO v_cust
            FROM fnd_customers c2 WHERE c2.tenant_id = p_tenant_id AND c2.customer_number = btrim(a ->> 0);
          IF v_cust.customer_id IS NULL THEN
            v_res := jsonb_build_object('e', '#N/A', 'message', 'Customer ' || COALESCE(a ->> 0, '') || ' not found');
          ELSE
            v_stmt := bps.ar_statement_get(p_tenant_id, v_cust.account_id, current_date, true);
            IF fn = 'BALANCE' THEN
              v_res := jsonb_build_object('v', COALESCE((v_stmt ->> 'total_due')::numeric, 0));
            ELSE
              v_key := CASE lower(btrim(COALESCE(a ->> 1, '')))
                         WHEN 'current' THEN 'current_amt' WHEN '1-30' THEN 'd1_30' WHEN '31-60' THEN 'd31_60'
                         WHEN '61-90' THEN 'd61_90' WHEN '90+' THEN 'd90_plus' WHEN 'total' THEN 'total' END;
              v_res := CASE WHEN v_key IS NULL
                            THEN jsonb_build_object('e', '#VALUE!', 'message', 'Bucket must be current, 1-30, 31-60, 61-90, 90+ or total')
                            ELSE jsonb_build_object('v', COALESCE((v_stmt -> 'aging' ->> v_key)::numeric, 0)) END;
            END IF;
          END IF;
        END IF;

      ELSIF fn = 'ITEM_PRICE' THEN
        IF NOT bps.fnd_has_access_any('{customers.pricing,inventory.pricing}'::text[], 'R') THEN v_res := jsonb_build_object('e', '#ACCESS');
        ELSE
          SELECT i.item_id INTO v_item FROM fnd_items i WHERE i.tenant_id = p_tenant_id AND i.item_number = btrim(a ->> 0)
           ORDER BY i.is_active DESC LIMIT 1;
          SELECT c2.customer_id INTO v_cust FROM fnd_customers c2 WHERE c2.tenant_id = p_tenant_id AND c2.customer_number = btrim(a ->> 1);
          IF v_item IS NULL THEN v_res := jsonb_build_object('e', '#N/A', 'message', 'Item ' || COALESCE(a ->> 0, '') || ' not found');
          ELSIF v_cust.customer_id IS NULL THEN v_res := jsonb_build_object('e', '#N/A', 'message', 'Customer ' || COALESCE(a ->> 1, '') || ' not found');
          ELSE
            v_num := (bps.fnd_item_prices_map(p_tenant_id, v_cust.customer_id, COALESCE(NULLIF(a ->> 2, '')::date, current_date),
                                              ARRAY[v_item]) ->> v_item::text)::numeric;
            v_res := CASE WHEN v_num IS NULL THEN jsonb_build_object('e', '#N/A', 'message', 'No price for this customer')
                          ELSE jsonb_build_object('v', v_num) END;
          END IF;
        END IF;

      ELSIF fn = 'QTY_ORDERED' THEN
        IF NOT bps.fnd_has_access_any('{orders.enter,orders.manage}'::text[], 'R') THEN v_res := jsonb_build_object('e', '#ACCESS');
        ELSE
          SELECT i.item_id INTO v_item FROM fnd_items i WHERE i.tenant_id = p_tenant_id AND i.item_number = btrim(a ->> 0)
           ORDER BY i.is_active DESC LIMIT 1;
          IF v_item IS NULL THEN v_res := jsonb_build_object('e', '#N/A', 'message', 'Item ' || COALESCE(a ->> 0, '') || ' not found');
          ELSE
            SELECT COALESCE(SUM(l.quantity), 0) INTO v_num
              FROM om_order_lines l JOIN om_orders o ON o.order_id = l.order_id
             WHERE o.tenant_id = p_tenant_id AND l.item_id = v_item AND o.production_date = (a ->> 1)::date
               AND (NULLIF(btrim(a ->> 2), '') IS NULL OR o.production_code = upper(btrim(a ->> 2)))
               AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED';
            v_res := jsonb_build_object('v', v_num);
          END IF;
        END IF;

      ELSE
        v_res := jsonb_build_object('e', '#NAME?', 'message', 'Unknown BPS function ' || fn);
      END IF;
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow OR invalid_text_representation THEN
      v_res := jsonb_build_object('e', '#VALUE!', 'message', SQLERRM);
    END;
    v_out := v_out || jsonb_build_array(v_res);
  END LOOP;
  RETURN v_out;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_sheet_bps_eval(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_sheet_bps_eval(bigint, jsonb) TO authenticated, service_role, bps_dev;
