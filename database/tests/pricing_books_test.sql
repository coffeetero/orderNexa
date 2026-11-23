-- ============================================================
-- SQL tests for pricing books: precedence, date ranges, fallback, approval, unpriced items, customer rules, to-do's.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/pricing_books_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _ids (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _ids TO PUBLIC;

-- An account "zz Starbucks" with two books: High Volume (Default, open ended) and Holiday Season (Seasonal, 12/15-12/25).
DO $$
DECLARE acc bigint; hv bigint; hol bigint; ia bigint; ib bigint; ic bigint; r_pr bigint; uPr bigint; uCust bigint; r_cadm bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, is_active) VALUES (200000000002, 'zz Starbucks', 'ACCOUNT', true) RETURNING customer_id INTO acc;
  SELECT item_id INTO ia FROM fnd_items WHERE tenant_id = 200000000002 AND is_active ORDER BY item_id LIMIT 1;
  SELECT item_id INTO ib FROM fnd_items WHERE tenant_id = 200000000002 AND is_active AND item_id > ia ORDER BY item_id LIMIT 1;
  SELECT item_id INTO ic FROM fnd_items WHERE tenant_id = 200000000002 AND is_active AND item_id > ib ORDER BY item_id LIMIT 1;
  INSERT INTO fnd_pricebooks (tenant_id, pricebook_name, is_active, owner_customer_id, currency_id) VALUES (200000000002, 'zz High Volume', true, acc, 200000000001) RETURNING pricebook_id INTO hv;
  INSERT INTO fnd_pricebooks (tenant_id, pricebook_name, is_active, currency_id) VALUES (200000000002, 'zz Holiday Season', true, 200000000001) RETURNING pricebook_id INTO hol;
  INSERT INTO fnd_pricebook_items (tenant_id, pricebook_id, item_id, item_price, is_active) VALUES
    (200000000002, hv, ia, 10, true), (200000000002, hv, ib, 20, true), (200000000002, hol, ia, 12, true);
  INSERT INTO fnd_customer_pricebooks (tenant_id, customer_id, pricebook_id, assignment_type, status, effective_start_date, effective_end_date, is_active, precedence) VALUES
    (200000000002, acc, hol, 'Seasonal', 'Approved', '2026-12-15', '2026-12-25', true, 1),
    (200000000002, acc, hv,  'Default',  'Approved', '2026-01-01', NULL,         true, 2);

  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz pricing clerk', 'TENANT') RETURNING role_id INTO r_pr;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, r_pr, 'customers.pricing', true, true), (200000000002, r_pr, 'orders.enter', true, true);
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz pricing clerk', 'TENANCY_USER') RETURNING user_id INTO uPr;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz starbucks user', 'CUSTOMER_USER') RETURNING user_id INTO uCust;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, uPr), (200000000002, uCust);
  INSERT INTO fnd_user_customers (tenant_id, user_id, customer_id) VALUES (200000000002, uCust, acc);
  SELECT role_id INTO r_cadm FROM fnd_roles WHERE tenant_id = 200000000002 AND role_name = 'Customer Administrator' AND owner_customer_id IS NULL;
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uPr, r_pr), (200000000002, uCust, r_cadm);
  INSERT INTO fnd_user_customer_groups (tenant_id, user_id, group_id) SELECT 200000000002, uPr, group_id FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers;
  INSERT INTO _ids VALUES ('acc', acc), ('hv', hv), ('hol', hol), ('ia', ia), ('ib', ib), ('ic', ic), ('uPr', uPr), ('uCust', uCust);
END $$;

-- ── resolver, as a staff administrator ───────────────────────────────────────
DO $$
DECLARE acc bigint := (SELECT v FROM _ids WHERE k='acc'); ia text := (SELECT v::text FROM _ids WHERE k='ia'); ib text := (SELECT v::text FROM _ids WHERE k='ib'); ic text := (SELECT v::text FROM _ids WHERE k='ic');
        m jsonb; j jsonb; r boolean; n int; d date;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":200000174045}}', true);
  SET LOCAL ROLE authenticated;

  m := fnd_item_prices_map(200000000002, acc, '2026-12-20', NULL);
  INSERT INTO _t VALUES ('in the holiday range the seasonal book prices its item (12) and the default fills the rest (20)', (m ->> ia)::numeric = 12 AND (m ->> ib)::numeric = 20);
  INSERT INTO _t VALUES ('an item in no book is not priced', NOT (m ? ic));
  m := fnd_item_prices_map(200000000002, acc, '2026-11-20', NULL);
  INSERT INTO _t VALUES ('outside the range the default book prices everything it holds', (m ->> ia)::numeric = 10 AND (m ->> ib)::numeric = 20);
  m := fnd_item_prices_map(200000000002, acc, '2026-12-26', NULL);
  INSERT INTO _t VALUES ('the day after the seasonal range the default applies again', (m ->> ia)::numeric = 10);
  m := fnd_item_prices_map(200000000002, acc, '2025-12-20', NULL);
  INSERT INTO _t VALUES ('before the default starts nothing is priced', m = '{}'::jsonb);
  m := fnd_item_prices_map(200000000002, acc, '2026-12-20', ARRAY[(ib)::bigint]);
  INSERT INTO _t VALUES ('the item filter limits the result', m ? ib AND NOT (m ? ia));

  -- precedence is strictly the table order: put the default above the seasonal book and it wins
  UPDATE fnd_customer_pricebooks SET precedence = 0 WHERE customer_id = acc AND assignment_type = 'Default';
  m := fnd_item_prices_map(200000000002, acc, '2026-12-20', NULL);
  INSERT INTO _t VALUES ('a default above the seasonal book wins by its order', (m ->> ia)::numeric = 10);
  UPDATE fnd_customer_pricebooks SET precedence = 2 WHERE customer_id = acc AND assignment_type = 'Default';

  -- inactive, unapproved and inactive-book assignments are ignored
  UPDATE fnd_customer_pricebooks SET is_active = false WHERE customer_id = acc AND assignment_type = 'Seasonal';
  INSERT INTO _t VALUES ('an inactive assignment is ignored', (fnd_item_prices_map(200000000002, acc, '2026-12-20', NULL) ->> ia)::numeric = 10);
  UPDATE fnd_customer_pricebooks SET is_active = true, status = 'Pending Approval' WHERE customer_id = acc AND assignment_type = 'Seasonal';
  INSERT INTO _t VALUES ('an assignment that is not Approved is ignored', (fnd_item_prices_map(200000000002, acc, '2026-12-20', NULL) ->> ia)::numeric = 10);
  UPDATE fnd_customer_pricebooks SET status = 'Approved' WHERE customer_id = acc AND assignment_type = 'Seasonal';
  UPDATE fnd_pricebooks SET is_active = false WHERE pricebook_id = (SELECT v FROM _ids WHERE k='hol');
  INSERT INTO _t VALUES ('an inactive book is ignored', (fnd_item_prices_map(200000000002, acc, '2026-12-20', NULL) ->> ia)::numeric = 10);
  UPDATE fnd_pricebooks SET is_active = true WHERE pricebook_id = (SELECT v FROM _ids WHERE k='hol');

  -- the delivery date, not the production date, selects the book
  d := om_delivery_date_calc(200000000002, '2026-12-19', 'MORNING');
  INSERT INTO _t VALUES ('delivery date is production date plus the code days', d = '2026-12-20');
  j := om_items_get_v2(200000000002, acc, true, '2026-12-19', 'MORNING');
  INSERT INTO _t VALUES ('item list for a 12/19 production (12/20 delivery) shows the holiday price and in_pricebook', EXISTS (
    SELECT 1 FROM jsonb_array_elements(j) e WHERE (e ->> 'item_id') = ia AND (e ->> 'unit_price')::numeric = 12 AND (e ->> 'in_pricebook')::boolean));
  INSERT INTO _t VALUES ('an item no book prices has no price and in_pricebook false', EXISTS (
    SELECT 1 FROM jsonb_array_elements(j) e WHERE (e ->> 'item_id') = ic AND (e ->> 'unit_price') IS NULL AND NOT (e ->> 'in_pricebook')::boolean));

  -- pricing books screen functions
  INSERT INTO _ids VALUES ('nb', fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_name', 'zz Starbucks Pricing Book', 'description', 'x', 'owner_customer_id', acc)));
  BEGIN PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_name', 'ZZ STARBUCKS PRICING BOOK')); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('pricing book names are unique per company, ignoring case', r);
  n := fnd_pricebook_items_set(200000000002, (SELECT v FROM _ids WHERE k='nb'), jsonb_build_array(jsonb_build_object('item_id', (SELECT v FROM _ids WHERE k='ia'), 'item_price', 7.5), jsonb_build_object('item_id', (SELECT v FROM _ids WHERE k='ib'), 'item_price', 8)));
  n := fnd_pricebook_items_set(200000000002, (SELECT v FROM _ids WHERE k='nb'), jsonb_build_array(jsonb_build_object('item_id', (SELECT v FROM _ids WHERE k='ib'), 'remove', true), jsonb_build_object('item_id', (SELECT v FROM _ids WHERE k='ia'), 'item_price', 9)));
  j := fnd_pricebook_detail_get(200000000002, (SELECT v FROM _ids WHERE k='nb'));
  INSERT INTO _t VALUES ('items can be added, repriced and removed in a book', jsonb_array_length(j -> 'items') = 1 AND ((j -> 'items' -> 0) ->> 'item_price')::numeric = 9);
  BEGIN PERFORM fnd_pricebook_items_set(200000000002, (SELECT v FROM _ids WHERE k='nb'), jsonb_build_array(jsonb_build_object('item_id', (SELECT v FROM _ids WHERE k='ia'), 'item_price', -1))); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a negative price is rejected', r);
  INSERT INTO _t VALUES ('list shows the owner customer, item count and assigned count', EXISTS (
    SELECT 1 FROM jsonb_array_elements(fnd_pricebooks_list_get(200000000002)) e WHERE e ->> 'pricebook_name' = 'zz High Volume' AND (e ->> 'item_count')::int = 2 AND (e ->> 'assigned_count')::int = 1 AND (e ->> 'owner_customer_id')::bigint = acc));
  RESET ROLE;
END $$;

-- ── approval, to-do's: a pricing clerk who may not approve ───────────────────
DO $$
DECLARE uPr bigint := (SELECT v FROM _ids WHERE k='uPr'); acc bigint := (SELECT v FROM _ids WHERE k='acc'); nb bigint := (SELECT v FROM _ids WHERE k='nb'); r boolean; j jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uPr), true);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO fnd_customer_pricebooks (tenant_id, customer_id, pricebook_id, assignment_type, status, effective_start_date, is_active, precedence)
    VALUES (200000000002, acc, nb, 'Promotional', 'Approved', '2026-12-01', true, 3); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a clerk without Approve rights cannot create an Approved assignment', r);
  INSERT INTO fnd_customer_pricebooks (tenant_id, customer_id, pricebook_id, assignment_type, status, effective_start_date, is_active, precedence)
  VALUES (200000000002, acc, nb, 'Promotional', 'Pending Approval', current_date + 3, true, 3);
  INSERT INTO _t VALUES ('the clerk can create it pending approval', true);
  BEGIN UPDATE fnd_customer_pricebooks SET status = 'Approved' WHERE customer_id = acc AND pricebook_id = nb; r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('and cannot approve it later', r);
  INSERT INTO _t VALUES ('a user who cannot approve gets no to-do list', fnd_todos_get(200000000002) = '[]'::jsonb);
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":200000174045}}', true);
  SET LOCAL ROLE authenticated;
  j := fnd_todos_get(200000000002);
  INSERT INTO _t VALUES ('an approver sees the pending assignment starting in 3 days', EXISTS (
    SELECT 1 FROM jsonb_array_elements(j) e WHERE (e ->> 'customer_id')::bigint = acc AND e ->> 'pricebook_name' = 'zz Starbucks Pricing Book' AND (e ->> 'days_until_start')::int BETWEEN 3 AND 4));
  UPDATE fnd_customer_pricebooks SET status = 'Approved' WHERE customer_id = acc AND pricebook_id = nb;
  INSERT INTO _t VALUES ('an approver can approve it', true);
  INSERT INTO _t VALUES ('an approved, active assignment leaves the to-do list', NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(fnd_todos_get(200000000002)) e WHERE e ->> 'pricebook_name' = 'zz Starbucks Pricing Book'));
  UPDATE fnd_customer_pricebooks SET status = 'Draft' WHERE customer_id = acc AND pricebook_id = nb;
  UPDATE fnd_customer_pricebooks SET effective_start_date = current_date + 60 WHERE customer_id = acc AND pricebook_id = nb;
  INSERT INTO _t VALUES ('an assignment starting beyond the window is not listed', NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(fnd_todos_get(200000000002)) e WHERE e ->> 'pricebook_name' = 'zz Starbucks Pricing Book'));
  RESET ROLE;
END $$;

-- ── orders: staff may add an unpriced item, customers may not and cannot change prices ──
DO $$
DECLARE acc bigint := (SELECT v FROM _ids WHERE k='acc'); ia bigint := (SELECT v FROM _ids WHERE k='ia'); ib bigint := (SELECT v FROM _ids WHERE k='ib'); ic bigint := (SELECT v FROM _ids WHERE k='ic');
        uCust bigint := (SELECT v FROM _ids WHERE k='uCust'); res jsonb; oid bigint; r boolean; n int; p numeric; flag boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":200000174045}}', true);
  SET LOCAL ROLE authenticated;
  res := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', '2026-12-19', 'production_code', 'MORNING', 'order_date', '2026-12-01',
     'lines', jsonb_build_array(
       jsonb_build_object('item_id', ia, 'item_description', 'A', 'quantity', 2, 'unit_price', 12),
       jsonb_build_object('item_id', ic, 'item_description', 'C sample', 'quantity', 1, 'unit_price', 0))));
  oid := (res ->> 'order_id')::bigint;
  SELECT is_unpriced INTO flag FROM om_order_lines WHERE order_id = oid AND item_id = ic;
  INSERT INTO _t VALUES ('staff can add an item no book prices; the line is flagged unpriced', flag);
  SELECT is_unpriced INTO flag FROM om_order_lines WHERE order_id = oid AND item_id = ia;
  INSERT INTO _t VALUES ('a priced item is not flagged', NOT flag);
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uCust), true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', '2026-12-19', 'production_code', 'MORNING', 'department_event', 'CUSTOMER TRY',
      'lines', jsonb_build_array(jsonb_build_object('item_id', ic, 'item_description', 'C', 'quantity', 1, 'unit_price', 1)))); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a customer cannot order an item their books do not price', r);
  res := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', '2026-12-19', 'production_code', 'MORNING', 'department_event', 'CUSTOMER OK',
      'lines', jsonb_build_array(jsonb_build_object('item_id', ia, 'item_description', 'A', 'quantity', 3, 'unit_price', 1))));
  SELECT unit_price INTO p FROM om_order_lines WHERE order_id = (res ->> 'order_id')::bigint AND item_id = ia;
  INSERT INTO _t VALUES ('a customer line is priced from the books (12 on a holiday delivery), not from what they sent', p = 12);
  RESET ROLE;
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
