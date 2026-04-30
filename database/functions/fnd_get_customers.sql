CREATE OR REPLACE FUNCTION fnd_get_customers(
    p_customer_id bigint,
    p_active_only boolean DEFAULT true
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
     * BPS Foundation: Fetch a single customer by ID.
     * Logic: 
     * - Uses to_jsonb(cus) for efficient row-to-object serialization.
     * - p_active_only defaults to true for standard UI safety.
     * - Returns an empty object {} if the record is not found or is inactive.
     */
    
    SELECT to_jsonb(cus)
      INTO v_result
    FROM fnd_customers cus
    WHERE cus.customer_id = p_customer_id
      AND (NOT p_active_only OR cus.is_active = true)
    LIMIT 1;

    -- COALESCE ensures we don't return a SQL NULL, keeping the frontend happy
    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;