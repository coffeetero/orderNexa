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

    INSERT INTO om_orders (
        order_number,
        customer_id,
        order_date,
        delivery_date,
        delivery_window,
        amount,
        discount_amount,
        quantity,
        snapshot_data,
        tenant_id
    )
    SELECT
        trim(o.ordr_no::BIGINT::TEXT),
        cus.customer_id,
        o.ordr_prdctn_dt::DATE,
        COALESCE(o.ordr_prdctn_dt::DATE, o.ordr_dt::DATE, DATE '2000-01-01'),
        NULLIF(trim(o.ordr_prdctn_cd), ''),
        (COALESCE(o.ordr_amt, 0) + COALESCE(o.ordr_discount_amt, 0))::NUMERIC(14,4) as amount,
        COALESCE(o.ordr_discount_amt, 0)::NUMERIC(14,4) as discount_amount,
        COALESCE(o.ordr_qty_sold, 0)::NUMERIC(14,4) as quantity,
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
        ),
        v_tenant_id
    FROM ordr o
    LEFT JOIN fnd_customers cus
        ON cus.tenant_id = v_tenant_id
       AND cus.legacy_id = o.cus_id::INT
    LEFT JOIN customer cu
        ON cu.cus_id::NUMERIC = o.cus_id;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'om_orders: % rows inserted', v_inserted;
END $$;

SELECT COUNT(*) AS om_orders_row_count FROM om_orders;
