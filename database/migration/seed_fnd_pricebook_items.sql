-- ============================================================
-- Seed fnd_pricebook_items from legacy item_price / item_prices
--
-- Joins legacy rows to fnd_items (legacy_id = item_id) and fnd_pricebooks
-- (pricebook_name = trim(cus_price_cd)). Amount column is auto-detected (first match):
--   price, item_price, item_cost, unit_price, sell_price.
--
-- TRUNCATE fnd_pricebook_items then load. Run after seed_fnd_items.
--
-- Prerequisite: seed_fnd_pricebooks.sql, seed_fnd_items.sql, Alpine tenant.
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_src       TEXT;
    v_amt       TEXT;
    v_sql       TEXT;
    v_ins       INT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    IF to_regclass('public.item_price') IS NOT NULL THEN
        v_src := 'item_price';
    ELSIF to_regclass('public.item_prices') IS NOT NULL THEN
        v_src := 'item_prices';
    ELSE
        RAISE EXCEPTION 'Need legacy table public.item_price or public.item_prices';
    END IF;

    SELECT a.attname::text INTO v_amt
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = v_src
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attname::text = ANY (
          ARRAY['price', 'item_price', 'item_cost', 'unit_price', 'sell_price']
      )
    ORDER BY array_position(
        ARRAY['price', 'item_price', 'item_cost', 'unit_price', 'sell_price'],
        a.attname::text
    )
    LIMIT 1;

    IF v_amt IS NULL THEN
        RAISE EXCEPTION 'Legacy table % has none of: price, item_price, item_cost, unit_price, sell_price', v_src;
    END IF;

    TRUNCATE TABLE fnd_pricebook_items;

    v_sql := format(
        $q$
        INSERT INTO fnd_pricebook_items (
            pricebook_id,
            item_id,
            item_price,
            tenant_id,
            min_quantity,
            is_active
        )
        SELECT DISTINCT ON (itm.item_id, prcBk.pricebook_id)
            prcBk.pricebook_id,
            itm.item_id,
            GREATEST(COALESCE(ip.%I::numeric, 0), 0)::numeric(14,4),
            %L::bigint,
            1,
            TRUE
        FROM %I ip
        JOIN fnd_items itm
          ON itm.tenant_id = %L::bigint
         AND itm.legacy_id = ip.item_id::INT
        JOIN fnd_pricebooks prcBk
          ON prcBk.tenant_id = %L::bigint
         AND prcBk.pricebook_name = TRIM(BOTH FROM COALESCE(ip.cus_price_cd::text, ''))
        WHERE NULLIF(TRIM(BOTH FROM COALESCE(ip.cus_price_cd::text, '')), '') IS NOT NULL
        ORDER BY itm.item_id, prcBk.pricebook_id, GREATEST(COALESCE(ip.%I::numeric, 0), 0) DESC
        $q$,
        v_amt,
        v_tenant_id,
        v_src,
        v_tenant_id,
        v_tenant_id,
        v_amt
    );
    EXECUTE v_sql;

    GET DIAGNOSTICS v_ins = ROW_COUNT;
    RAISE NOTICE 'fnd_pricebook_items: % rows inserted (amount column % on %)', v_ins, v_amt, v_src;
END $$;
