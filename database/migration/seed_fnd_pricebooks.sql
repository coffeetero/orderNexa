-- ============================================================
-- Seed fnd_pricebooks from legacy item_price / item_prices
--
-- One row per distinct cus_price_cd (trimmed text). pricebook_name = that code.
-- Uses public.item_price if present, else public.item_prices (dataPump uses item_price).
--
-- TRUNCATE fnd_pricebooks CASCADE clears referencing rows (e.g. fnd_customer_pricebooks) when re-run.
-- If legacy has no price codes, inserts a single 'Default' book.
--
-- Prerequisite: fnd_tenants (Alpine Bakery), legacy pricing table with cus_price_cd.
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_currency_id   BIGINT;
    v_src           TEXT;
    v_sql           TEXT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    SELECT curr.currency_id INTO v_currency_id
    FROM fnd_currencies curr
    WHERE curr.iso_code = 'USD'
    LIMIT 1;

    IF v_currency_id IS NULL THEN
        RAISE EXCEPTION 'fnd_currencies must contain USD — run newTables/fnd_currencies.sql';
    END IF;

    IF to_regclass('public.item_price') IS NOT NULL THEN
        v_src := 'item_price';
    ELSIF to_regclass('public.item_prices') IS NOT NULL THEN
        v_src := 'item_prices';
    ELSE
        RAISE EXCEPTION 'Need legacy table public.item_price or public.item_prices';
    END IF;

    TRUNCATE TABLE fnd_pricebooks CASCADE;

    v_sql := format(
        $q$
        INSERT INTO fnd_pricebooks (pricebook_name, tenant_id, currency_id)
        SELECT DISTINCT TRIM(BOTH FROM COALESCE(t.cus_price_cd::text, '')),
               %L::bigint,
               %L::bigint
        FROM %I t
        WHERE NULLIF(TRIM(BOTH FROM COALESCE(t.cus_price_cd::text, '')), '') IS NOT NULL
        $q$,
        v_tenant_id,
        v_currency_id,
        v_src
    );
    EXECUTE v_sql;

    IF NOT EXISTS (SELECT 1 FROM fnd_pricebooks WHERE tenant_id = v_tenant_id) THEN
        INSERT INTO fnd_pricebooks (pricebook_name, tenant_id, currency_id)
        VALUES ('Default', v_tenant_id, v_currency_id);
    END IF;

    RAISE NOTICE 'fnd_pricebooks: % rows (source table %)', (SELECT COUNT(*)::INT FROM fnd_pricebooks WHERE tenant_id = v_tenant_id), v_src;
END $$;
