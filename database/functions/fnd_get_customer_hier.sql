CREATE OR REPLACE FUNCTION fnd_get_customer_hier(tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_result jsonb;
BEGIN
    WITH RECURSIVE customer_tree AS (
        SELECT
            cus.customer_id,
            cus.customer_parent_id,
            cus.customer_number,
            cus.customer_name,
            0 AS level,
            LPAD(COALESCE(cus.customer_number, cus.customer_id::text), 20, '0') AS sort_path,
            ARRAY[cus.customer_id]::bigint[] AS path_ids
        FROM fnd_customers cus
        WHERE cus.tenant_id = fnd_get_customer_hier.tenant_id
          AND (
            cus.customer_parent_id IS NULL
            OR NOT EXISTS (
                SELECT 1
                FROM fnd_customers parent
                WHERE parent.tenant_id = fnd_get_customer_hier.tenant_id
                  AND parent.customer_id = cus.customer_parent_id
            )
          )

        UNION ALL

        SELECT
            ch.customer_id,
            ch.customer_parent_id,
            ch.customer_number,
            ch.customer_name,
            ct.level + 1,
            ct.sort_path || '.' || LPAD(COALESCE(ch.customer_number, ch.customer_id::text), 20, '0'),
            ct.path_ids || ch.customer_id
        FROM fnd_customers ch
        JOIN customer_tree ct
          ON ct.customer_id = ch.customer_parent_id
        WHERE ch.tenant_id = fnd_get_customer_hier.tenant_id
          AND NOT (ch.customer_id = ANY(ct.path_ids))
    )
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'tenant_id', fnd_get_customer_hier.tenant_id,
                'customer_id', customer_id,
                'customer_parent_id', customer_parent_id,
                'customer_number', customer_number,
                'customer_name', customer_name,
                'level', level,
                'sort_path', sort_path
            )
            ORDER BY sort_path
        ),
        '[]'::jsonb
    )
    INTO v_result
    FROM customer_tree;

    RETURN v_result;
END;
$$;
