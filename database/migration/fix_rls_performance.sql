-- RLS performance. Rewrites the live bps policies in place; no new tables or columns. Safe to run again.
-- 1. bps.fnd_is_trusted() written bare in a policy runs once per row (its SET search_path stops inlining).
--    Wrapped as (SELECT bps.fnd_is_trusted()) it runs once per query.
-- 2. Child tables checked their parent with "col IN (SELECT id FROM parent)". The parent list (300k orders) is too big to hash
--    in work_mem, so Postgres rescanned it for every child row (2M order lines: over 90 s).
--    Now a per-row lookup on the parent key: EXISTS (SELECT 1 FROM parent p WHERE p.id = child.col).
--    Read policies also skip the parent check for users who see all customers: the child row already passed the same tenant
--    and area checks as its parent. Writes keep the parent check, so a row can't be attached to another company's parent.
--    fnd_pricebook_items gets no skip: its parent has different area rules.
-- bps stays off the search path so pg_policies prints names as bps.x, which the patterns below expect.
SET search_path = pg_catalog, public;

DO $$
DECLARE r record; q text; c text; parent_check text; read_check text;
BEGIN
  FOR r IN SELECT tablename, policyname, cmd, qual, with_check FROM pg_policies WHERE schemaname = 'bps' LOOP
    q := regexp_replace(r.qual,       '(?<!SELECT )bps\.fnd_is_trusted\(\)', '(SELECT bps.fnd_is_trusted())', 'g');
    c := regexp_replace(r.with_check, '(?<!SELECT )bps\.fnd_is_trusted\(\)', '(SELECT bps.fnd_is_trusted())', 'g');

    IF r.tablename IN ('om_order_lines', 'om_shipment_lines', 'ar_transaction_lines', 'ar_payment_applications',
                       'fnd_contact_points', 'fnd_pricebook_items') THEN
      -- deparsed form: (order_id IN ( SELECT om_orders.order_id FROM bps.om_orders))
      parent_check := format('EXISTS (SELECT 1 FROM bps.\4 p WHERE p.\3 = %I.\1)', r.tablename);
      read_check := CASE WHEN r.tablename = 'fnd_pricebook_items' THEN parent_check
                         ELSE '(SELECT bps.fnd_scope_is_all()) OR ' || parent_check END;
      q := regexp_replace(q, '\((\w+) IN \( SELECT (\w+)\.(\w+)\s+FROM bps\.(\w+)\)\)',
                          '(' || CASE WHEN r.cmd = 'SELECT' THEN read_check ELSE parent_check END || ')');
      c := regexp_replace(c, '\((\w+) IN \( SELECT (\w+)\.(\w+)\s+FROM bps\.(\w+)\)\)', '(' || parent_check || ')');
    END IF;

    IF q IS DISTINCT FROM r.qual THEN
      EXECUTE format('ALTER POLICY %I ON bps.%I USING (%s)', r.policyname, r.tablename, q);
    END IF;
    IF c IS DISTINCT FROM r.with_check THEN
      EXECUTE format('ALTER POLICY %I ON bps.%I WITH CHECK (%s)', r.policyname, r.tablename, c);
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'bps'
              AND (coalesce(qual, '') || coalesce(with_check, '')) ~ '(?<!SELECT )bps\.fnd_is_trusted\(\)') THEN
    RAISE EXCEPTION 'A policy still calls fnd_is_trusted() per row';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'bps'
              AND tablename IN ('om_order_lines', 'om_shipment_lines', 'ar_transaction_lines', 'ar_payment_applications',
                                'fnd_contact_points', 'fnd_pricebook_items')
              AND (coalesce(qual, '') || coalesce(with_check, '')) ~ ' IN \( SELECT') THEN
    RAISE EXCEPTION 'A child policy still checks its parent with IN (SELECT ...)';
  END IF;
END $$;
