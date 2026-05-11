-- ============================================================
-- SEED om_orders FROM LEGACY ORDR TABLE
--
-- Run order: 1) Apply table DDL (newTables / recreate scripts). 2) This file (seed_om_orders).
--   3) seed_ar_transactions. 4) seed_ar_transaction_lines, seed_ar_payments, seed_ar_payment_applications as needed.
--
-- Source:  public.ordr, public.customer (for address / invoice flags)
-- Target:  public.om_orders
--
-- snapshot_data keys (stable app-facing names):
--   cus_name, cus_key, route_id, route_no (route_no ← ordr.route_stop_no)
--   shipping address — single line from customer s_* when cus_invc_rqrd = 'Y'
--   Delivery Instructions — cus_dlvr_instr when cus_invc_rqrd = 'Y'
--   billing address — single line from customer b_* when cus_parent_id = cus_id (ACCOUNT)
--
-- Tenant: Alpine Bakery (same pattern as seed_fnd_item_bom.sql)
--
-- TRUNCATE om_orders CASCADE — PostgreSQL truncates all tables that FK into this truncate set,
-- not only om_order_lines. In this schema that includes at least: om_order_lines,
-- om_order_shipments, ar_transaction_lines (all tenants). ar_transactions is not truncated.
-- After this script, re-run seed_ar_transactions and seed_ar_transaction_lines (and cash seeds if used)
-- or AR header/line data will be out of sync with orders.
--
-- Prerequisite: newTables/om_orders.sql applied, fnd_customers populated for cus_id lookup.
-- Reload is Alpine-only for om_orders rows; CASCADE still clears dependent rows globally.
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_inserted    INT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    TRUNCATE TABLE om_orders CASCADE;

    -- Department orders are stored under their immediate parent customer.
    -- Department/Event stays as the department name unless the final slot key
    -- would duplicate another order, in which case it is suffixed with the order number.
    WITH order_source AS (
        SELECT
            trim(o.ordr_no::BIGINT::TEXT) AS order_number,
            CASE
                WHEN UPPER(TRIM(cus.customer_type)) IN ('DEPARTMENT', 'LOCATION')
                 AND cus.customer_parent_id IS NOT NULL
                THEN parent.customer_id
                ELSE cus.customer_id
            END AS customer_id,
            CASE
                WHEN UPPER(TRIM(cus.customer_type)) IN ('DEPARTMENT', 'LOCATION')
                 AND cus.customer_parent_id IS NOT NULL
                THEN parent.customer_name
                ELSE cus.customer_name
            END AS customer_name,
            CASE
                WHEN UPPER(TRIM(cus.customer_type)) IN ('DEPARTMENT', 'LOCATION')
                THEN COALESCE(NULLIF(UPPER(TRIM(cus.customer_name)), ''), '')
                ELSE ''
            END AS base_department_event,
            o.ordr_prdctn_dt::DATE AS order_date,
            COALESCE(o.ordr_prdctn_dt::DATE, o.ordr_dt::DATE, DATE '2000-01-01') AS production_date,
            NULLIF(UPPER(trim(o.ordr_prdctn_cd)), '') AS production_code,
            (COALESCE(o.ordr_amt, 0) + COALESCE(o.ordr_discount_amt, 0))::NUMERIC(14,4) AS amount,
            COALESCE(o.ordr_discount_amt, 0)::NUMERIC(14,4) AS discount_amount,
            COALESCE(o.ordr_qty_sold, 0)::NUMERIC(14,4) AS quantity,
            COALESCE(
                jsonb_strip_nulls(
                    jsonb_build_object(
                        'cus_name', o.cus_name,
                        'cus_key', o.cus_key,
                        'route_id', o.route_id::BIGINT,
                        'route_no', o.route_stop_no::INT,
                        'shipping address',
                            CASE WHEN cu.cus_invc_rqrd = 'Y' THEN
                                NULLIF(
                                    trim(both ' ,' FROM concat_ws(', ',
                                        NULLIF(trim(COALESCE(cu.s_contact::TEXT, '')), ''),
                                        NULLIF(trim(COALESCE(cu.s_addr1::TEXT, '')), ''),
                                        NULLIF(trim(COALESCE(cu.s_addr2::TEXT, '')), ''),
                                        NULLIF(trim(COALESCE(cu.s_city::TEXT, '')), ''),
                                        NULLIF(trim(COALESCE(cu.s_state::TEXT, '')), ''),
                                        NULLIF(trim(COALESCE(cu.s_zip::TEXT, '')), '')
                                    )),
                                    ''
                                )
                            END,
                        'Delivery Instructions',
                            CASE WHEN cu.cus_invc_rqrd = 'Y' THEN
                                NULLIF(trim(COALESCE(cu.cus_dlvr_instr::TEXT, '')), '')
                            END,
                        'billing address',
                            CASE
                                WHEN cu.cus_parent_id IS NOT NULL
                                 AND cu.cus_id IS NOT NULL
                                 AND cu.cus_parent_id::NUMERIC = cu.cus_id::NUMERIC
                                THEN
                                    NULLIF(
                                        trim(both ' ,' FROM concat_ws(', ',
                                            NULLIF(trim(COALESCE(cu.b_contact::TEXT, '')), ''),
                                            NULLIF(trim(COALESCE(cu.b_addr1::TEXT, '')), ''),
                                            NULLIF(trim(COALESCE(cu.b_addr2::TEXT, '')), ''),
                                            NULLIF(trim(COALESCE(cu.b_city::TEXT, '')), ''),
                                            NULLIF(trim(COALESCE(cu.b_state::TEXT, '')), ''),
                                            NULLIF(trim(COALESCE(cu.b_zip::TEXT, '')), '')
                                        )),
                                        ''
                                    )
                            END
                    )
                ),
                '{}'::JSONB
            ) AS snapshot_data,
            v_tenant_id AS tenant_id
        FROM ordr o
        LEFT JOIN fnd_customers cus
            ON cus.tenant_id = v_tenant_id
           AND cus.legacy_id = o.cus_id::INT
        LEFT JOIN fnd_customers parent
            ON parent.tenant_id = cus.tenant_id
           AND parent.customer_id = cus.customer_parent_id
        LEFT JOIN customer cu
            ON cu.cus_id::NUMERIC = o.cus_id
    ),
    duplicate_slots AS (
        SELECT
            tenant_id,
            customer_id,
            production_date,
            production_code,
            base_department_event
        FROM order_source
        GROUP BY
            tenant_id,
            customer_id,
            production_date,
            production_code,
            base_department_event
        HAVING COUNT(*) > 1
    )
    INSERT INTO om_orders (
        order_number,
        customer_id,
        customer_name,
        department_event,
        order_date,
        production_date,
        production_code,
        amount,
        discount_amount,
        quantity,
        snapshot_data,
        tenant_id
    )
    SELECT
        src.order_number,
        src.customer_id,
        src.customer_name,
        CASE
            WHEN dup.tenant_id IS NOT NULL
            THEN src.base_department_event || ' #' || src.order_number
            ELSE src.base_department_event
        END,
        src.order_date,
        src.production_date,
        src.production_code,
        src.amount,
        src.discount_amount,
        src.quantity,
        src.snapshot_data,
        src.tenant_id
    FROM order_source src
    LEFT JOIN duplicate_slots dup
        ON dup.tenant_id = src.tenant_id
       AND dup.customer_id IS NOT DISTINCT FROM src.customer_id
       AND dup.production_date = src.production_date
       AND dup.production_code IS NOT DISTINCT FROM src.production_code
       AND dup.base_department_event = src.base_department_event;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'om_orders: % rows inserted', v_inserted;
END $$;

SELECT COUNT(*) AS om_orders_row_count FROM om_orders;
