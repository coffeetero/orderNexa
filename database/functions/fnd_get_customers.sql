DROP FUNCTION IF EXISTS bps.fnd_get_customers(bigint, boolean);

CREATE OR REPLACE FUNCTION bps.fnd_get_customers(
    p_tenant_id bigint,
    p_customer_id bigint,
    p_hierarchy boolean,
    p_active boolean
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_result jsonb;
BEGIN
    /*
     * BPS Foundation: Unified customer fetch.
     *
     *   p_hierarchy = false
     *     - Returns the full customer row (to_jsonb(cus)).
     *     - Requires p_customer_id; row must also belong to p_tenant_id.
     *     - p_active = true filters to is_active = true.
     *     - Returns '{}'::jsonb when no row matches.
     *
     *   p_hierarchy = true
     *     - Returns a jsonb array of slim hierarchy rows ordered by sort_path:
     *       tenant_id, customer_id, customer_parent_id, customer_number,
     *       customer_name, level, sort_path
     *     - p_customer_id IS NULL  -> anchor is top-level customers for tenant.
     *     - p_customer_id NOT NULL -> anchor is exactly that customer (subtree).
     *     - p_active = true filters both the anchor and recursive members
     *       (an inactive parent prunes its descendants by design).
     */

    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    IF NOT p_hierarchy THEN
        IF p_customer_id IS NULL THEN
            RAISE EXCEPTION 'p_customer_id is required when p_hierarchy = false';
        END IF;

        SELECT to_jsonb(cus)
          INTO v_result
        FROM fnd_customers cus
        WHERE cus.customer_id = p_customer_id
          AND cus.tenant_id = p_tenant_id
          AND (NOT p_active OR cus.is_active = true)
        LIMIT 1;

        RETURN COALESCE(v_result, '{}'::jsonb);
    END IF;

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
        WHERE cus.tenant_id = p_tenant_id
          AND (NOT p_active OR cus.is_active = true)
          AND (
                (p_customer_id IS NOT NULL AND cus.customer_id = p_customer_id)
             OR (
                    p_customer_id IS NULL
                    AND (
                        cus.customer_parent_id IS NULL
                        OR NOT EXISTS (
                            SELECT 1
                            FROM fnd_customers parent
                            WHERE parent.tenant_id = p_tenant_id
                              AND parent.customer_id = cus.customer_parent_id
                              AND (NOT p_active OR parent.is_active = true)
                        )
                    )
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
        WHERE ch.tenant_id = p_tenant_id
          AND (NOT p_active OR ch.is_active = true)
          AND NOT (ch.customer_id = ANY(ct.path_ids))
    )
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'tenant_id', p_tenant_id,
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
