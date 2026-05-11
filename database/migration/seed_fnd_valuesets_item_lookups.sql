-- ============================================================
-- SEED FND_VALUESETS + FND_VALUESET_VALUES — ITEM LOOKUP LISTS
--
-- Source:  public.item  (uploaded from SQL Anywhere)
-- Target:  fnd_valuesets, fnd_valueset_values
--
-- Creates five STATIC valuesets from distinct values in the
-- legacy item table:
--
--   ITEMCATEGORY  ← item.item_ctgry
--   ITEMUNIT      ← item.item_unit
--   ITEMDOUGH     ← item.item_dough
--   ITEMSHAPE     ← item.item_shape
--   ITEMPACKING   ← item.item_packing
--
-- Idempotent: uses ON CONFLICT DO NOTHING for both tables,
-- so it is safe to re-run after partial failures.
-- ============================================================

DO $$
DECLARE
    v_tenant_id     BIGINT;
    v_vs_id         BIGINT;
    v_inserted_vs   INT := 0;
    v_inserted_vv   INT := 0;
    v_total_vs      INT := 0;
    v_total_vv      INT := 0;

    -- Valueset definitions: (code, name)
    v_valuesets TEXT[][] := ARRAY[
        ARRAY['ITEMCATEGORY', 'Item Category'],
        ARRAY['ITEMUNIT',     'Item Unit of Sale'],
        ARRAY['ITEMDOUGH',    'Item Dough Type'],
        ARRAY['ITEMSHAPE',    'Item Shape'],
        ARRAY['ITEMPACKING',  'Item Packing']
    ];

    v_rec TEXT[];

BEGIN

    -- --------------------------------------------------------
    -- 1. Resolve tenant
    -- --------------------------------------------------------
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    -- --------------------------------------------------------
    -- 2. Insert valuesets (idempotent)
    -- --------------------------------------------------------
    FOREACH v_rec SLICE 1 IN ARRAY v_valuesets LOOP
        INSERT INTO fnd_valuesets (
            tenant_id,
            valueset_code,
            valueset_name,
            value_type,
            control_type,
            source_type,
            refresh_mode
        ) VALUES (
            v_tenant_id,
            v_rec[1],
            v_rec[2],
            'TEXT',
            'select',
            'STATIC',
            'MANUAL'
        )
        ON CONFLICT ON CONSTRAINT uq_fnd_valuesets_tenant_code DO NOTHING;

        GET DIAGNOSTICS v_inserted_vs = ROW_COUNT;
        v_total_vs := v_total_vs + v_inserted_vs;
        RAISE NOTICE 'Valueset %: % row(s) inserted', v_rec[1], v_inserted_vs;
    END LOOP;

    -- --------------------------------------------------------
    -- 3. Insert values for ITEMCATEGORY  ← item.item_ctgry
    -- --------------------------------------------------------
    SELECT valueset_id INTO v_vs_id
    FROM fnd_valuesets
    WHERE tenant_id = v_tenant_id AND valueset_code = 'ITEMCATEGORY';

    INSERT INTO fnd_valueset_values (
        tenant_id, valueset_id, value, label, display_order
    )
    SELECT
        v_tenant_id,
        v_vs_id,
        UPPER(TRIM(item_ctgry))        AS value,
        INITCAP(TRIM(item_ctgry))      AS label,
        ROW_NUMBER() OVER (ORDER BY UPPER(TRIM(item_ctgry)))::INT AS display_order
    FROM (
        SELECT DISTINCT item_ctgry
        FROM item
        WHERE NULLIF(TRIM(item_ctgry), '') IS NOT NULL
    ) src
    ON CONFLICT ON CONSTRAINT uq_fnd_valueset_values_tenant_valueset_value DO NOTHING;

    GET DIAGNOSTICS v_inserted_vv = ROW_COUNT;
    v_total_vv := v_total_vv + v_inserted_vv;
    RAISE NOTICE 'ITEMCATEGORY values: % row(s) inserted', v_inserted_vv;

    -- --------------------------------------------------------
    -- 4. Insert values for ITEMUNIT  ← item.item_unit
    -- --------------------------------------------------------
    SELECT valueset_id INTO v_vs_id
    FROM fnd_valuesets
    WHERE tenant_id = v_tenant_id AND valueset_code = 'ITEMUNIT';

    INSERT INTO fnd_valueset_values (
        tenant_id, valueset_id, value, label, display_order
    )
    SELECT
        v_tenant_id,
        v_vs_id,
        UPPER(TRIM(item_unit))         AS value,
        INITCAP(TRIM(item_unit))       AS label,
        ROW_NUMBER() OVER (ORDER BY UPPER(TRIM(item_unit)))::INT AS display_order
    FROM (
        SELECT DISTINCT item_unit
        FROM item
        WHERE NULLIF(TRIM(item_unit), '') IS NOT NULL
    ) src
    ON CONFLICT ON CONSTRAINT uq_fnd_valueset_values_tenant_valueset_value DO NOTHING;

    GET DIAGNOSTICS v_inserted_vv = ROW_COUNT;
    v_total_vv := v_total_vv + v_inserted_vv;
    RAISE NOTICE 'ITEMUNIT values: % row(s) inserted', v_inserted_vv;

    -- --------------------------------------------------------
    -- 5. Insert values for ITEMDOUGH  ← item.item_dough
    -- --------------------------------------------------------
    SELECT valueset_id INTO v_vs_id
    FROM fnd_valuesets
    WHERE tenant_id = v_tenant_id AND valueset_code = 'ITEMDOUGH';

    INSERT INTO fnd_valueset_values (
        tenant_id, valueset_id, value, label, display_order
    )
    SELECT
        v_tenant_id,
        v_vs_id,
        UPPER(TRIM(item_dough))        AS value,
        INITCAP(TRIM(item_dough))      AS label,
        ROW_NUMBER() OVER (ORDER BY UPPER(TRIM(item_dough)))::INT AS display_order
    FROM (
        SELECT DISTINCT item_dough
        FROM item
        WHERE NULLIF(TRIM(item_dough), '') IS NOT NULL
    ) src
    ON CONFLICT ON CONSTRAINT uq_fnd_valueset_values_tenant_valueset_value DO NOTHING;

    GET DIAGNOSTICS v_inserted_vv = ROW_COUNT;
    v_total_vv := v_total_vv + v_inserted_vv;
    RAISE NOTICE 'ITEMDOUGH values: % row(s) inserted', v_inserted_vv;

    -- --------------------------------------------------------
    -- 6. Insert values for ITEMSHAPE  ← item.item_shape
    -- --------------------------------------------------------
    SELECT valueset_id INTO v_vs_id
    FROM fnd_valuesets
    WHERE tenant_id = v_tenant_id AND valueset_code = 'ITEMSHAPE';

    INSERT INTO fnd_valueset_values (
        tenant_id, valueset_id, value, label, display_order
    )
    SELECT
        v_tenant_id,
        v_vs_id,
        UPPER(TRIM(item_shape))        AS value,
        INITCAP(TRIM(item_shape))      AS label,
        ROW_NUMBER() OVER (ORDER BY UPPER(TRIM(item_shape)))::INT AS display_order
    FROM (
        SELECT DISTINCT item_shape
        FROM item
        WHERE NULLIF(TRIM(item_shape), '') IS NOT NULL
    ) src
    ON CONFLICT ON CONSTRAINT uq_fnd_valueset_values_tenant_valueset_value DO NOTHING;

    GET DIAGNOSTICS v_inserted_vv = ROW_COUNT;
    v_total_vv := v_total_vv + v_inserted_vv;
    RAISE NOTICE 'ITEMSHAPE values: % row(s) inserted', v_inserted_vv;

    -- --------------------------------------------------------
    -- 7. Insert values for ITEMPACKING  ← item.item_packing
    -- --------------------------------------------------------
    SELECT valueset_id INTO v_vs_id
    FROM fnd_valuesets
    WHERE tenant_id = v_tenant_id AND valueset_code = 'ITEMPACKING';

    INSERT INTO fnd_valueset_values (
        tenant_id, valueset_id, value, label, display_order
    )
    SELECT
        v_tenant_id,
        v_vs_id,
        UPPER(TRIM(item_packing))      AS value,
        INITCAP(TRIM(item_packing))    AS label,
        ROW_NUMBER() OVER (ORDER BY UPPER(TRIM(item_packing)))::INT AS display_order
    FROM (
        SELECT DISTINCT item_packing
        FROM item
        WHERE NULLIF(TRIM(item_packing), '') IS NOT NULL
    ) src
    ON CONFLICT ON CONSTRAINT uq_fnd_valueset_values_tenant_valueset_value DO NOTHING;

    GET DIAGNOSTICS v_inserted_vv = ROW_COUNT;
    v_total_vv := v_total_vv + v_inserted_vv;
    RAISE NOTICE 'ITEMPACKING values: % row(s) inserted', v_inserted_vv;

    -- --------------------------------------------------------
    -- 8. Summary
    -- --------------------------------------------------------
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total valuesets inserted : %', v_total_vs;
    RAISE NOTICE 'Total values inserted    : %', v_total_vv;
    RAISE NOTICE '========================================';

END $$;

-- ============================================================
-- QA — verify counts per valueset
-- ============================================================
SELECT
    vs.valueset_code,
    vs.valueset_name,
    COUNT(vv.valueset_value_id) AS value_count
FROM fnd_valuesets vs
LEFT JOIN fnd_valueset_values vv
       ON vv.valueset_id = vs.valueset_id
WHERE vs.valueset_code IN (
    'ITEMCATEGORY', 'ITEMUNIT', 'ITEMDOUGH', 'ITEMSHAPE', 'ITEMPACKING'
)
GROUP BY vs.valueset_code, vs.valueset_name
ORDER BY vs.valueset_code;
