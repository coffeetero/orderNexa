-- ============================================================
-- SEED FND_ITEM_BOM FROM LEGACY CITEM TABLE
--
-- Source:  public.citem
-- Target:  public.fnd_item_bom
--
-- TRUNCATE fnd_item_bom, then reload from legacy citem (same inclusion rules as before).
-- Rules:
--   - Skip self-references (citem_id = item_id)
--   - Skip parents with only one non-self-ref component line
--   - Skip blocklisted fake compounds (e.g. 291 ALL ACTIVE ITEMS)
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted        INT;
    v_orphans         INT;
    v_skip_single     INT;
    v_excluded_parents INT[] := ARRAY[
        291
    ];
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    TRUNCATE TABLE fnd_item_bom;

    SELECT COUNT(*) INTO v_orphans
    FROM citem c
    WHERE NOT EXISTS (
        SELECT 1 FROM fnd_items itm
        WHERE itm.tenant_id = v_tenant_id
          AND itm.legacy_id  = c.item_id::INT
    )
    OR NOT EXISTS (
        SELECT 1 FROM fnd_items itm
        WHERE itm.tenant_id = v_tenant_id
          AND itm.legacy_id  = c.citem_id::INT
    );

    IF v_orphans > 0 THEN
        RAISE NOTICE 'WARNING: % citem rows reference item_ids not found in fnd_items — skipped', v_orphans;
    END IF;

    SELECT COUNT(*)::INT INTO v_skip_single
    FROM (
        SELECT c.citem_id
        FROM citem c
        WHERE c.citem_id != c.item_id
        GROUP BY c.citem_id
        HAVING COUNT(*) = 1
    ) x;

    IF v_skip_single > 0 THEN
        RAISE NOTICE 'Parents with only 1 component line in citem (excluded): %', v_skip_single;
    END IF;

    INSERT INTO fnd_item_bom (
        tenant_id,
        parent_item_id,
        item_id,
        quantity
    )
    SELECT
        v_tenant_id,
        parent.item_id,
        component.item_id,
        COALESCE(c.citem_qty, 1)
    FROM citem c
    JOIN fnd_items parent
      ON parent.tenant_id = v_tenant_id
     AND parent.legacy_id = c.citem_id::INT
    JOIN fnd_items component
      ON component.tenant_id = v_tenant_id
     AND component.legacy_id = c.item_id::INT
    WHERE c.citem_id != c.item_id
      AND NOT (parent.legacy_id = ANY (v_excluded_parents))
      AND c.citem_id IN (
          SELECT c2.citem_id
          FROM citem c2
          WHERE c2.citem_id != c2.item_id
          GROUP BY c2.citem_id
          HAVING COUNT(*) > 1
      );

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'fnd_item_bom: % rows inserted (this run)', v_inserted;
END $$;

SELECT
    itm.item_number,
    itm.item_name,
    COUNT(b.item_bom_id) AS component_count,
    SUM(b.quantity)  AS total_qty
FROM fnd_items itm
JOIN fnd_item_bom b ON b.parent_item_id = itm.item_id
GROUP BY itm.item_id, itm.item_number, itm.item_name
ORDER BY component_count DESC;
