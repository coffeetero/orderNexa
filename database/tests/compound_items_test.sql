-- ============================================================
-- SQL tests for compound items: flag, two-level rule, components get/set.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/compound_items_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

DO $$
DECLARE a bigint; b bigint; c bigint; basket bigint; d bigint; r boolean; j jsonb; n int;
BEGIN
  INSERT INTO _t VALUES ('every item that already has components is compound',
    NOT EXISTS (SELECT 1 FROM fnd_item_bom bom JOIN fnd_items i ON i.item_id = bom.parent_item_id WHERE NOT i.is_compound));

  PERFORM set_config('request.jwt.claims', jsonb_build_object('app_metadata', jsonb_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', jsonb_build_array(200000000002), 'app_user_id', 200000174045))::text, true);
  SET LOCAL ROLE authenticated;

  a := (fnd_items_profile_save(200000000002, NULL, 'zz-A', 'zz Small Breads'))->>'item_id';
  b := (fnd_items_profile_save(200000000002, NULL, 'zz-B', 'zz Small Baguettes'))->>'item_id';
  c := (fnd_items_profile_save(200000000002, NULL, 'zz-C', 'zz Butter'))->>'item_id';
  basket := (fnd_items_profile_save(200000000002, NULL, 'zz-X', 'zz Xmas Gift Basket', p_is_compound => true))->>'item_id';
  d := (fnd_items_profile_save(200000000002, NULL, 'zz-D', 'zz Other Compound', p_is_compound => true))->>'item_id';

  j := fnd_items_profile_get(200000000002, false, basket);
  INSERT INTO _t VALUES ('the item detail carries is_compound', (j ->> 'is_compound')::boolean);
  INSERT INTO _t VALUES ('the slim list carries is_compound', EXISTS (SELECT 1 FROM jsonb_array_elements(fnd_items_profile_get(200000000002)) x WHERE (x ->> 'item_id')::bigint = basket AND (x ->> 'is_compound')::boolean));

  n := fnd_item_components_set(200000000002, basket, jsonb_build_array(jsonb_build_object('item_id', a, 'quantity', 1.5), jsonb_build_object('item_id', b, 'quantity', 2), jsonb_build_object('item_id', c, 'quantity', 1)));
  j := fnd_item_components_get(200000000002, basket);
  INSERT INTO _t VALUES ('components save with decimal quantities', n = 3 AND jsonb_array_length(j) = 3 AND EXISTS (SELECT 1 FROM jsonb_array_elements(j) x WHERE (x ->> 'item_id')::bigint = a AND (x ->> 'quantity')::numeric = 1.5));

  BEGIN PERFORM fnd_item_components_set(200000000002, basket, jsonb_build_array(jsonb_build_object('item_id', d, 'quantity', 1))); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a compound item cannot be a component (two levels only)', r);
  BEGIN PERFORM fnd_item_components_set(200000000002, a, jsonb_build_array(jsonb_build_object('item_id', b, 'quantity', 1))); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a simple item cannot have components', r);
  BEGIN PERFORM fnd_item_components_set(200000000002, basket, jsonb_build_array(jsonb_build_object('item_id', basket, 'quantity', 1))); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('an item cannot be its own component', r);
  BEGIN PERFORM fnd_item_components_set(200000000002, basket, jsonb_build_array(jsonb_build_object('item_id', a, 'quantity', 1), jsonb_build_object('item_id', a, 'quantity', 2))); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a component can be listed only once', r);
  BEGIN PERFORM fnd_item_components_set(200000000002, basket, jsonb_build_array(jsonb_build_object('item_id', a, 'quantity', 0))); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a zero quantity is refused', r);
  INSERT INTO _t VALUES ('a refused save changes nothing', jsonb_array_length(fnd_item_components_get(200000000002, basket)) = 3);

  BEGIN PERFORM fnd_items_profile_save(200000000002, basket, 'zz-X', 'zz Xmas Gift Basket', p_is_compound => false); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('turning off Compound item is refused while components exist', r);
  BEGIN PERFORM fnd_items_profile_save(200000000002, a, 'zz-A', 'zz Small Breads', p_is_compound => true); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a component cannot be made compound', r);

  PERFORM fnd_item_components_set(200000000002, basket, jsonb_build_array(jsonb_build_object('item_id', a, 'quantity', 4)));
  j := fnd_item_components_get(200000000002, basket);
  INSERT INTO _t VALUES ('saving a shorter list removes the others and updates quantities', jsonb_array_length(j) = 1 AND ((j -> 0) ->> 'quantity')::numeric = 4);

  PERFORM fnd_item_components_set(200000000002, basket, '[]'::jsonb);
  PERFORM fnd_items_profile_save(200000000002, basket, 'zz-X', 'zz Xmas Gift Basket', p_is_compound => false);
  INSERT INTO _t VALUES ('Compound item can be turned off once the components are gone', NOT (fnd_items_profile_get(200000000002, false, basket) ->> 'is_compound')::boolean);
  RESET ROLE;

  -- last ordered / stale (trusted)
  INSERT INTO _t VALUES ('a new item that was never ordered is stale in the item list',
    (SELECT (x ->> 'is_stale')::boolean FROM jsonb_array_elements(fnd_items_profile_get(200000000002)) x WHERE (x ->> 'item_id')::bigint = a));
  SELECT item_id INTO d FROM fnd_items WHERE tenant_id = 200000000002 AND last_ordered_date IS NOT NULL ORDER BY item_id LIMIT 1;
  INSERT INTO _t VALUES ('items that were ordered recently exist in the data', d IS NOT NULL);
  UPDATE fnd_items SET last_ordered_date = NULL WHERE item_id = d;
  n := fnd_items_last_ordered_refresh(200000000002);
  INSERT INTO _t VALUES ('the refresh restores an item''s last ordered date from the order lines', (SELECT last_ordered_date FROM fnd_items WHERE item_id = d) IS NOT NULL AND n >= 1);
  INSERT INTO _t VALUES ('a second refresh changes nothing', fnd_items_last_ordered_refresh(200000000002) = 0);
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
