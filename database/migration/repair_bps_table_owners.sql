-- Repair bps schema table ownership after table recreation.
-- Run as postgres/admin. Runtime access remains controlled by grants + RLS.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bps_owner') THEN
        EXECUTE 'CREATE ROLE bps_owner NOLOGIN NOINHERIT';
    END IF;
END;
$$;

GRANT USAGE, CREATE ON SCHEMA bps TO bps_owner;
GRANT bps_owner TO postgres;

ALTER SEQUENCE bps.fnd_entity_id_seq OWNER TO bps_owner;

ALTER TABLE bps.ar OWNER TO bps_owner;
ALTER TABLE bps.ar_payment_applications OWNER TO bps_owner;
ALTER TABLE bps.ar_payments OWNER TO bps_owner;
ALTER TABLE bps.ar_transaction_lines OWNER TO bps_owner;
ALTER TABLE bps.ar_transactions OWNER TO bps_owner;
ALTER TABLE bps.box OWNER TO bps_owner;
ALTER TABLE bps.citem OWNER TO bps_owner;
ALTER TABLE bps.customer OWNER TO bps_owner;
ALTER TABLE bps.fnd_audit_log OWNER TO bps_owner;
ALTER TABLE bps.fnd_contact_points OWNER TO bps_owner;
ALTER TABLE bps.fnd_contacts OWNER TO bps_owner;
ALTER TABLE bps.fnd_currencies OWNER TO bps_owner;
ALTER TABLE bps.fnd_customer_pricebooks OWNER TO bps_owner;
ALTER TABLE bps.fnd_customers OWNER TO bps_owner;
ALTER TABLE bps.fnd_item_bom OWNER TO bps_owner;
ALTER TABLE bps.fnd_items OWNER TO bps_owner;
ALTER TABLE bps.fnd_notes OWNER TO bps_owner;
ALTER TABLE bps.fnd_pricebook_items OWNER TO bps_owner;
ALTER TABLE bps.fnd_pricebooks OWNER TO bps_owner;
ALTER TABLE bps.fnd_tenant_sequences OWNER TO bps_owner;
ALTER TABLE bps.fnd_tenants OWNER TO bps_owner;
ALTER TABLE bps.fnd_user_customers OWNER TO bps_owner;
ALTER TABLE bps.fnd_user_tenants OWNER TO bps_owner;
ALTER TABLE bps.fnd_users OWNER TO bps_owner;
ALTER TABLE bps.fnd_valueset_values OWNER TO bps_owner;
ALTER TABLE bps.fnd_valuesets OWNER TO bps_owner;
ALTER TABLE bps.item OWNER TO bps_owner;
ALTER TABLE bps.item_price OWNER TO bps_owner;
ALTER TABLE bps.om_order_lines OWNER TO bps_owner;
ALTER TABLE bps.om_order_shipments OWNER TO bps_owner;
ALTER TABLE bps.om_standing_orders OWNER TO bps_owner;
ALTER TABLE bps.ordr OWNER TO bps_owner;
ALTER TABLE bps.ordr_detail OWNER TO bps_owner;
ALTER TABLE bps.pmt_detail OWNER TO bps_owner;
ALTER TABLE bps.route OWNER TO bps_owner;
ALTER TABLE bps.route_stop OWNER TO bps_owner;
ALTER TABLE bps.sordr OWNER TO bps_owner;
ALTER TABLE bps.v_allowed_tenant_ids OWNER TO bps_owner;
ALTER TABLE bps.v_app_user_id OWNER TO bps_owner;
ALTER TABLE bps.v_restricted_tenant_ids OWNER TO bps_owner;
ALTER TABLE bps.v_result OWNER TO bps_owner;
ALTER TABLE bps.v_tenant_id OWNER TO bps_owner;
