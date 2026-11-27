-- ============================================================
-- ar_open_items_refresh
-- Recalculates bps.ar_open_items for the given documents of one company: each listed invoice / credit memo and payment gets a row
-- holding what is still open today, or no row when nothing is open. Called by the triggers on ar_transactions, ar_payments,
-- ar_payment_applications and ar_credit_applications, and once by the migration to fill the table.
-- Same rules as ar_transaction_open_amount and ar_report_open_items:
--   invoice / credit memo (not DRAFT or CANCELLED): amount - live payment applications - live credit applications that paid it
--                                                   + live credit applications that used it - allowance - settled
--   payment (not voided):                           -(amount) + live applications + settled   (negative = credit still available)
-- One recalculation per company at a time (transaction-level advisory lock), so two payments applied to the same invoice at the
-- same moment cannot leave a stale balance: the second waits, then reads the first one's committed applications.
-- SECURITY DEFINER: writes the table, which has no write policies. Not granted to users.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_open_items_refresh(p_tenant_id bigint, p_transaction_ids bigint[], p_payment_ids bigint[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  IF p_tenant_id IS NULL OR (COALESCE(cardinality(p_transaction_ids), 0) = 0 AND COALESCE(cardinality(p_payment_ids), 0) = 0) THEN
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('bps.ar_open_items:' || p_tenant_id, 0));

  IF COALESCE(cardinality(p_transaction_ids), 0) > 0 THEN
    DELETE FROM bps.ar_open_items WHERE tenant_id = p_tenant_id AND ar_transaction_id = ANY(p_transaction_ids);
    INSERT INTO bps.ar_open_items (tenant_id, ar_transaction_id, customer_id, open_amount)
    SELECT x.tenant_id, x.ar_transaction_id, x.customer_id, x.open_amount
      FROM (SELECT t.tenant_id, t.ar_transaction_id, t.customer_id,
                   t.amount - COALESCE(pa.s, 0) - COALESCE(ci.s, 0) + COALESCE(cc.s, 0) - t.allowance_amount - t.settled_amount AS open_amount
              FROM bps.ar_transactions t
              LEFT JOIN (SELECT a.ar_transaction_id, sum(a.applied_amount) s FROM bps.ar_payment_applications a
                          WHERE a.tenant_id = p_tenant_id AND a.ar_transaction_id = ANY(p_transaction_ids) AND a.reversed_at IS NULL
                          GROUP BY 1) pa ON pa.ar_transaction_id = t.ar_transaction_id
              LEFT JOIN (SELECT a.ar_transaction_id, sum(a.applied_amount) s FROM bps.ar_credit_applications a
                          WHERE a.tenant_id = p_tenant_id AND a.ar_transaction_id = ANY(p_transaction_ids) AND a.reversed_at IS NULL
                          GROUP BY 1) ci ON ci.ar_transaction_id = t.ar_transaction_id
              LEFT JOIN (SELECT a.credit_ar_transaction_id, sum(a.applied_amount) s FROM bps.ar_credit_applications a
                          WHERE a.tenant_id = p_tenant_id AND a.credit_ar_transaction_id = ANY(p_transaction_ids) AND a.reversed_at IS NULL
                          GROUP BY 1) cc ON cc.credit_ar_transaction_id = t.ar_transaction_id
             WHERE t.tenant_id = p_tenant_id AND t.ar_transaction_id = ANY(p_transaction_ids)
               AND t.status NOT IN ('DRAFT', 'CANCELLED') AND t.transaction_type IN ('INV', 'CM')) x
     WHERE x.open_amount <> 0;
  END IF;

  IF COALESCE(cardinality(p_payment_ids), 0) > 0 THEN
    DELETE FROM bps.ar_open_items WHERE tenant_id = p_tenant_id AND ar_payment_id = ANY(p_payment_ids);
    INSERT INTO bps.ar_open_items (tenant_id, ar_payment_id, customer_id, open_amount)
    SELECT x.tenant_id, x.ar_payment_id, x.customer_id, x.open_amount
      FROM (SELECT p.tenant_id, p.ar_payment_id, p.customer_id, -p.amount + COALESCE(pa.s, 0) + p.settled_amount AS open_amount
              FROM bps.ar_payments p
              LEFT JOIN (SELECT a.ar_payment_id, sum(a.applied_amount) s FROM bps.ar_payment_applications a
                          WHERE a.tenant_id = p_tenant_id AND a.ar_payment_id = ANY(p_payment_ids) AND a.reversed_at IS NULL
                          GROUP BY 1) pa ON pa.ar_payment_id = p.ar_payment_id
             WHERE p.tenant_id = p_tenant_id AND p.ar_payment_id = ANY(p_payment_ids) AND p.voided_at IS NULL) x
     WHERE x.open_amount <> 0;
  END IF;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_open_items_refresh(bigint, bigint[], bigint[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.ar_open_items_refresh(bigint, bigint[], bigint[]) TO service_role, bps_dev;

-- ============================================================
-- Trigger functions (statement level, with transition tables: a bulk load or a production run's invoices are recalculated in one
-- pass). Each collects the documents the statement touched, per company, and recalculates them.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_open_items_trg_transactions()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'bps', 'public' AS $function$
DECLARE r record;
BEGIN
  -- a transition table exists only for the events that have it, so each event reads its own
  IF TG_OP = 'INSERT' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS id FROM new_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.ids, NULL); END LOOP;
  ELSIF TG_OP = 'DELETE' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS id FROM old_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.ids, NULL); END LOOP;
  ELSE
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS id FROM new_rows UNION SELECT tenant_id, ar_transaction_id AS id FROM old_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.ids, NULL); END LOOP;
  END IF;
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION bps.ar_open_items_trg_payments()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'bps', 'public' AS $function$
DECLARE r record;
BEGIN
  -- a transition table exists only for the events that have it, so each event reads its own
  IF TG_OP = 'INSERT' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_payment_id AS id FROM new_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, NULL, r.ids); END LOOP;
  ELSIF TG_OP = 'DELETE' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_payment_id AS id FROM old_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, NULL, r.ids); END LOOP;
  ELSE
    FOR r IN WITH d AS (SELECT tenant_id, ar_payment_id AS id FROM new_rows UNION SELECT tenant_id, ar_payment_id AS id FROM old_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, NULL, r.ids); END LOOP;
  END IF;
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION bps.ar_open_items_trg_payment_applications()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'bps', 'public' AS $function$
DECLARE r record;
BEGIN
  -- a transition table exists only for the events that have it, so each event reads its own
  IF TG_OP = 'INSERT' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS t_id, ar_payment_id AS p_id FROM new_rows) SELECT tenant_id, array_agg(DISTINCT t_id) FILTER (WHERE t_id IS NOT NULL) t_ids, array_agg(DISTINCT p_id) FILTER (WHERE p_id IS NOT NULL) p_ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.t_ids, r.p_ids); END LOOP;
  ELSIF TG_OP = 'DELETE' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS t_id, ar_payment_id AS p_id FROM old_rows) SELECT tenant_id, array_agg(DISTINCT t_id) FILTER (WHERE t_id IS NOT NULL) t_ids, array_agg(DISTINCT p_id) FILTER (WHERE p_id IS NOT NULL) p_ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.t_ids, r.p_ids); END LOOP;
  ELSE
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS t_id, ar_payment_id AS p_id FROM new_rows UNION SELECT tenant_id, ar_transaction_id AS t_id, ar_payment_id AS p_id FROM old_rows) SELECT tenant_id, array_agg(DISTINCT t_id) FILTER (WHERE t_id IS NOT NULL) t_ids, array_agg(DISTINCT p_id) FILTER (WHERE p_id IS NOT NULL) p_ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.t_ids, r.p_ids); END LOOP;
  END IF;
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION bps.ar_open_items_trg_credit_applications()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'bps', 'public' AS $function$
DECLARE r record;
BEGIN
  -- a transition table exists only for the events that have it, so each event reads its own
  IF TG_OP = 'INSERT' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS id FROM new_rows UNION SELECT tenant_id, credit_ar_transaction_id FROM new_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.ids, NULL); END LOOP;
  ELSIF TG_OP = 'DELETE' THEN
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS id FROM old_rows UNION SELECT tenant_id, credit_ar_transaction_id FROM old_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.ids, NULL); END LOOP;
  ELSE
    FOR r IN WITH d AS (SELECT tenant_id, ar_transaction_id AS id FROM new_rows UNION SELECT tenant_id, credit_ar_transaction_id FROM new_rows UNION SELECT tenant_id, ar_transaction_id AS id FROM old_rows UNION SELECT tenant_id, credit_ar_transaction_id FROM old_rows) SELECT tenant_id, array_agg(id) ids FROM d GROUP BY tenant_id LOOP PERFORM bps.ar_open_items_refresh(r.tenant_id, r.ids, NULL); END LOOP;
  END IF;
  RETURN NULL;
END $function$;

REVOKE EXECUTE ON FUNCTION bps.ar_open_items_trg_transactions(), bps.ar_open_items_trg_payments(),
  bps.ar_open_items_trg_payment_applications(), bps.ar_open_items_trg_credit_applications() FROM PUBLIC, anon, authenticated;
