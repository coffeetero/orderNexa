-- ============================================================
-- Customer hierarchy — account → site → location
-- Sorted alphabetically by name within each level
-- ============================================================

WITH RECURSIVE tree AS (

    -- Base: top-level accounts (no parent)
    SELECT
        customer_id,
        customer_parent_id,
        customer_number,
        customer_name,
        customer_type,
        0                                           AS depth,
        ARRAY[lower(customer_name)]                 AS sort_path
    FROM  fnd_customers
    WHERE customer_parent_id IS NULL

    UNION ALL

    -- Recursive: attach children to their parent
    SELECT
        c.customer_id,
        c.customer_parent_id,
        c.customer_number,
        c.customer_name,
        c.customer_type,
        t.depth + 1,
        t.sort_path || lower(c.customer_name)       -- extend sort path per level
    FROM  fnd_customers c
    JOIN  tree t ON c.customer_parent_id = t.customer_id

)
SELECT
    -- Visual indentation: 4 spaces per depth level
    repeat('    ', depth) || customer_number    AS customer_number,
    repeat('    ', depth) || customer_name      AS customer_name,
    customer_type
FROM  tree
ORDER BY sort_path;
