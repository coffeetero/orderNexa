-- ============================================================
-- fnd_customer_import_validate
-- Internal (no app grant): (re)checks every row of a customer import against the current customers and sets
-- row_action, issue, changes, hierarchy_depth and the import's counts. Called by upload and again by apply.
-- Matching: on customer number (the tenant's number mask characters are dropped, so 100-00 matches 10000).
-- ERROR when: customer no missing / longer than 30 / twice in the file; name missing / longer than 200; type not ACCOUNT,
--   SITE or DEPARTMENT; an ACCOUNT with a parent; parent no is the row itself / not in the file nor the customers / makes a
--   loop; a flag not Y or N; billing type not ACCOUNT or COD; billing period not DAILY, WEEKLY or MONTHLY; credit limit not
--   a number >= 0; delivery method unknown; cutoff extra minutes not a whole number >= 0; invoice copies not a whole number
--   >= 1; email not an address; the parent is a new customer whose row has errors.
-- Blank flags, invoice copies, addresses, phone and email keep the current value (new customers: the defaults, nothing).
-- Blank parent no, billing type / period, credit limit, delivery method and cutoff minutes clear the value.
-- The pricing book column is not imported; a different value is noted on the row.
-- NEW = customer number not found; CHANGED = some value differs (changes lists them); UNCHANGED otherwise.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_customer_import_validate(p_tenant_id bigint, p_customer_import_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_actor  bigint := bps.fnd_nav_app_user_id();
    v_mask   text;
    v_re     text;
    v_ch     text;
    v_keys   text[] := ARRAY['customer_name', 'customer_type', 'parent_number', 'is_active', 'billing_type', 'billing_period', 'credit_limit',
                             'delivery_method', 'cutoff_extra_minutes', 'invoice_copy_count', 'is_standing_order', 'is_signature_required',
                             'is_label_required', 'is_invoice_required', 'is_cost_on_invoice', 'is_cost_on_bill_of_lading', 'is_returns_allowed',
                             'billing_address', 'shipping_address', 'phone', 'email'];
    -- blank in the file = keep the current value
    v_keep   text[] := ARRAY['is_active', 'invoice_copy_count', 'is_standing_order', 'is_signature_required', 'is_label_required',
                             'is_invoice_required', 'is_cost_on_invoice', 'is_cost_on_bill_of_lading', 'is_returns_allowed',
                             'billing_address', 'shipping_address', 'phone', 'email'];
BEGIN
    -- number mask (e.g. ###-##, # = a digit) as a pattern: a value typed in the mask's format loses the mask characters
    SELECT NULLIF(customer_number_mask, '') INTO v_mask FROM fnd_tenants WHERE tenant_id = p_tenant_id;
    IF v_mask IS NOT NULL THEN
        v_re := '^';
        FOREACH v_ch IN ARRAY regexp_split_to_array(v_mask, '') LOOP
            v_re := v_re || CASE WHEN v_ch = '#' THEN '[0-9]' ELSE regexp_replace(v_ch, '([^0-9A-Za-z])', '\\\1') END;
        END LOOP;
        v_re := v_re || '$';
    END IF;

    -- 1) normalised numbers, match, fresh state
    UPDATE fnd_customer_import_rows r SET
           customer_number = n.num, parent_number = n.par,
           customer_id = (SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_number = n.num),
           row_action = NULL, issue = NULL, changes = NULL, current_data = NULL, hierarchy_depth = NULL,
           updated_at = now(), updated_by = v_actor
      FROM (SELECT x.customer_import_row_id AS id,
                   CASE WHEN v_re IS NOT NULL AND x.num ~ v_re THEN regexp_replace(x.num, '[^0-9A-Za-z]', '', 'g') ELSE x.num END AS num,
                   CASE WHEN v_re IS NOT NULL AND x.par ~ v_re THEN regexp_replace(x.par, '[^0-9A-Za-z]', '', 'g') ELSE x.par END AS par
              FROM (SELECT customer_import_row_id, bps.fnd_customer_import_value('customer_number', data ->> 'customer_number') AS num,
                           bps.fnd_customer_import_value('parent_number', data ->> 'parent_number') AS par
                      FROM fnd_customer_import_rows WHERE customer_import_id = p_customer_import_id) x) n
     WHERE r.customer_import_row_id = n.id;

    -- the customer's current values (and contact ids, for apply)
    UPDATE fnd_customer_import_rows r SET current_data = e.data || jsonb_build_object(
             'addresses_contact_id', e.addresses_contact_id, 'billing_point_id', e.billing_point_id, 'shipping_point_id', e.shipping_point_id,
             'phone_point_id', e.phone_point_id, 'email_point_id', e.email_point_id)
      FROM bps.fnd_customer_export_rows(p_tenant_id, ARRAY(SELECT customer_id FROM fnd_customer_import_rows
                                                            WHERE customer_import_id = p_customer_import_id AND customer_id IS NOT NULL)) e
     WHERE r.customer_import_id = p_customer_import_id AND r.customer_id = e.customer_id;

    -- 2) value checks
    WITH f AS (
        SELECT r.customer_import_row_id AS id, r.customer_number AS num, r.parent_number AS par,
               count(*) OVER (PARTITION BY r.customer_number) AS dup,
               bps.fnd_customer_import_value('customer_name', r.data ->> 'customer_name') AS name,
               bps.fnd_customer_import_value('customer_type', r.data ->> 'customer_type') AS typ,
               bps.fnd_customer_import_value('billing_type', r.data ->> 'billing_type') AS btype,
               bps.fnd_customer_import_value('billing_period', r.data ->> 'billing_period') AS bper,
               bps.fnd_customer_import_value('credit_limit', r.data ->> 'credit_limit') AS credit,
               bps.fnd_customer_import_value('delivery_method', r.data ->> 'delivery_method') AS dm,
               bps.fnd_customer_import_value('cutoff_extra_minutes', r.data ->> 'cutoff_extra_minutes') AS cutoff,
               bps.fnd_customer_import_value('invoice_copy_count', r.data ->> 'invoice_copy_count') AS copies,
               bps.fnd_customer_import_value('email', r.data ->> 'email') AS email,
               r.data
          FROM fnd_customer_import_rows r WHERE r.customer_import_id = p_customer_import_id
    ), e AS (
        SELECT f.id, NULLIF(concat_ws('; ',
                 CASE WHEN f.num IS NULL THEN 'Customer no is missing'
                      WHEN length(f.num) > 30 THEN 'Customer no is longer than 30 characters'
                      WHEN f.dup > 1 THEN 'Customer no ' || f.num || ' is in the file more than once' END,
                 CASE WHEN f.name IS NULL THEN 'Name is missing' WHEN length(f.name) > 200 THEN 'Name is longer than 200 characters' END,
                 CASE WHEN f.typ IS NULL OR f.typ NOT IN ('ACCOUNT', 'SITE', 'DEPARTMENT') THEN 'Type must be ACCOUNT, SITE or DEPARTMENT'
                      WHEN f.typ = 'ACCOUNT' AND f.par IS NOT NULL THEN 'An ACCOUNT cannot have a parent' END,
                 CASE WHEN f.par IS NULL OR f.typ = 'ACCOUNT' THEN NULL
                      WHEN f.par = f.num THEN 'A customer cannot be its own parent'
                      WHEN NOT EXISTS (SELECT 1 FROM f p WHERE p.num = f.par)
                       AND NOT EXISTS (SELECT 1 FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_number = f.par)
                      THEN 'Parent no ' || f.par || ' not found' END,
                 (SELECT string_agg(l.label || ' must be Y or N', '; ' ORDER BY l.ord)
                    FROM (VALUES (1, 'is_active', 'Active'), (2, 'is_standing_order', 'Standing order'), (3, 'is_signature_required', 'Signature required'),
                                 (4, 'is_label_required', 'Label required'), (5, 'is_invoice_required', 'Invoice required'),
                                 (6, 'is_cost_on_invoice', 'Cost on invoice'), (7, 'is_cost_on_bill_of_lading', 'Cost on bill of lading'),
                                 (8, 'is_returns_allowed', 'Returns allowed')) l(ord, k, label)
                   WHERE bps.fnd_customer_import_value(l.k, f.data ->> l.k) NOT IN ('Y', 'N')),
                 CASE WHEN f.btype NOT IN ('ACCOUNT', 'COD') THEN 'Billing type must be ACCOUNT or COD' END,
                 CASE WHEN f.bper NOT IN ('DAILY', 'WEEKLY', 'MONTHLY') THEN 'Billing period must be DAILY, WEEKLY or MONTHLY' END,
                 CASE WHEN f.credit !~ '^\d+(\.\d+)?$' OR length(f.credit) > 15 THEN 'Credit limit must be a number of 0 or more' END,
                 CASE WHEN f.dm IS NOT NULL AND NOT EXISTS (SELECT 1 FROM om_delivery_methods m WHERE m.tenant_id = p_tenant_id AND m.delivery_method_code = f.dm)
                      THEN 'Delivery method ' || f.dm || ' does not exist' END,
                 CASE WHEN f.cutoff !~ '^\d{1,5}$' THEN 'Cutoff extra minutes must be a whole number of 0 or more' END,
                 CASE WHEN f.copies !~ '^\d{1,3}$' OR f.copies = '0' THEN 'Invoice copies must be a whole number of 1 or more' END,
                 CASE WHEN f.email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN 'Email is not a valid address' END), '') AS msg
          FROM f
    )
    UPDATE fnd_customer_import_rows r SET row_action = 'ERROR', issue = e.msg
      FROM e WHERE r.customer_import_row_id = e.id AND e.msg IS NOT NULL;

    -- 3) loops: walk up the parents (the file's parent for file rows, else the current one) back to the row itself
    WITH RECURSIVE filenums AS (
        SELECT DISTINCT ON (customer_number) customer_number AS num, parent_number AS par
          FROM fnd_customer_import_rows WHERE customer_import_id = p_customer_import_id AND customer_number IS NOT NULL
         ORDER BY customer_number, row_number
    ), eff AS (
        SELECT num, par FROM filenums
        UNION ALL
        SELECT c.customer_number, p.customer_number FROM fnd_customers c LEFT JOIN fnd_customers p ON p.customer_id = c.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND c.customer_number IS NOT NULL AND c.customer_number NOT IN (SELECT num FROM filenums)
    ), walk AS (
        SELECT num AS start, par AS cur, 1 AS steps FROM filenums WHERE par IS NOT NULL AND par <> num
        UNION ALL
        SELECT w.start, e.par, w.steps + 1 FROM walk w JOIN eff e ON e.num = w.cur
         WHERE w.cur <> w.start AND e.par IS NOT NULL AND w.steps < 50
    )
    UPDATE fnd_customer_import_rows r SET row_action = 'ERROR', issue = concat_ws('; ', r.issue, 'Parent no ' || r.parent_number || ' makes a loop (a customer under itself)')
     WHERE r.customer_import_id = p_customer_import_id AND r.customer_number IN (SELECT start FROM walk WHERE cur = start);

    -- depth inside the file: rows whose parent is not in the file are 0, their children 1, ...
    WITH RECURSIVE d AS (
        SELECT customer_import_row_id AS id, customer_number AS num, 0 AS depth FROM fnd_customer_import_rows r
         WHERE r.customer_import_id = p_customer_import_id
           AND (r.parent_number IS NULL OR NOT EXISTS (SELECT 1 FROM fnd_customer_import_rows p WHERE p.customer_import_id = p_customer_import_id
                                                          AND p.customer_number = r.parent_number))
        UNION ALL
        SELECT c.customer_import_row_id, c.customer_number, d.depth + 1 FROM fnd_customer_import_rows c JOIN d ON c.parent_number = d.num
         WHERE c.customer_import_id = p_customer_import_id AND d.depth < 50
    )
    UPDATE fnd_customer_import_rows r SET hierarchy_depth = x.depth
      FROM (SELECT id, max(depth) AS depth FROM d GROUP BY id) x WHERE r.customer_import_row_id = x.id;

    -- 4) a new customer's row with errors blocks its children
    LOOP
        UPDATE fnd_customer_import_rows c SET row_action = 'ERROR', issue = 'Parent no ' || c.parent_number || ' has errors'
          FROM fnd_customer_import_rows p
         WHERE c.customer_import_id = p_customer_import_id AND p.customer_import_id = p_customer_import_id
           AND p.customer_number = c.parent_number AND p.row_action = 'ERROR' AND p.customer_id IS NULL
           AND c.row_action IS DISTINCT FROM 'ERROR'
           AND NOT EXISTS (SELECT 1 FROM fnd_customers x WHERE x.tenant_id = p_tenant_id AND x.customer_number = c.parent_number);
        EXIT WHEN NOT FOUND;
    END LOOP;

    -- 5) changes of matched customers; pricing book note
    UPDATE fnd_customer_import_rows r SET changes = (
             SELECT jsonb_agg(jsonb_build_object('field', k.key, 'from', k.cur, 'to', k.val) ORDER BY k.ord)
               FROM (SELECT u.key, u.ord,
                            bps.fnd_customer_import_value(u.key, r.current_data ->> u.key) AS cur,
                            CASE WHEN u.key = 'parent_number' THEN r.parent_number
                                 ELSE bps.fnd_customer_import_value(u.key, r.data ->> u.key) END AS val
                       FROM unnest(v_keys) WITH ORDINALITY u(key, ord)) k
              WHERE (k.val IS NOT NULL OR NOT (k.key = ANY (v_keep))) AND k.val IS DISTINCT FROM k.cur)
     WHERE r.customer_import_id = p_customer_import_id AND r.customer_id IS NOT NULL AND r.row_action IS NULL;

    UPDATE fnd_customer_import_rows r SET
           row_action = CASE WHEN r.customer_id IS NULL THEN 'NEW' WHEN r.changes IS NULL THEN 'UNCHANGED' ELSE 'CHANGED' END,
           issue = CASE WHEN bps.fnd_customer_import_value('pricebook', r.data ->> 'pricebook') IS DISTINCT FROM
                             bps.fnd_customer_import_value('pricebook', r.current_data ->> 'pricebook')
                         AND bps.fnd_customer_import_value('pricebook', r.data ->> 'pricebook') IS NOT NULL
                        THEN 'Pricing book is not imported; assign it in Pricing Books' END
     WHERE r.customer_import_id = p_customer_import_id AND r.row_action IS NULL;

    UPDATE fnd_customer_imports i SET
           row_count       = x.n, new_count = x.n_new, changed_count = x.n_chg, unchanged_count = x.n_same, error_count = x.n_err,
           updated_at = now(), updated_by = v_actor
      FROM (SELECT count(*) AS n, count(*) FILTER (WHERE row_action = 'NEW') AS n_new, count(*) FILTER (WHERE row_action = 'CHANGED') AS n_chg,
                   count(*) FILTER (WHERE row_action = 'UNCHANGED') AS n_same, count(*) FILTER (WHERE row_action = 'ERROR') AS n_err
              FROM fnd_customer_import_rows WHERE customer_import_id = p_customer_import_id) x
     WHERE i.customer_import_id = p_customer_import_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_import_validate(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_import_validate(bigint, bigint) TO service_role, bps_dev;
