-- ============================================================
-- DROP foundation schema objects for greenfield recreate.
-- Run before applying newTables/*.sql in recreate_all.py order.
--
-- Order is the reverse of DDL_SCRIPTS (children / dependents first).
-- Destroys all data. Not for production lightly.
--
-- Upgrading from pre-plural AR names? Run:
--   dataMigration/migrate_rename_ar_tables_to_plural.sql
-- before recreate, or drop old tables manually.
-- ============================================================

-- --- AR ---
DROP TABLE IF EXISTS ar_payment_applications CASCADE;
DROP TABLE IF EXISTS ar_applications CASCADE;
DROP TABLE IF EXISTS ar_receivable_applications CASCADE;
DROP TABLE IF EXISTS ar_payments CASCADE;
DROP TABLE IF EXISTS ar_cash_receipts CASCADE;
DROP TABLE IF EXISTS ar_transaction_lines CASCADE;
DROP TABLE IF EXISTS ar_transactions CASCADE;

-- --- OM ---
DROP TABLE IF EXISTS om_order_shipments CASCADE;
DROP TABLE IF EXISTS om_order_fullfillments CASCADE;
DROP TABLE IF EXISTS om_order_lines CASCADE;
DROP TABLE IF EXISTS om_orders CASCADE;

-- --- App users & people (FK to tenants / customers) ---
DROP TABLE IF EXISTS fnd_user_customers CASCADE;
DROP TABLE IF EXISTS fnd_user_tenants CASCADE;
DROP TABLE IF EXISTS fnd_contact_points CASCADE;
DROP TABLE IF EXISTS fnd_people CASCADE;
DROP TABLE IF EXISTS fnd_users CASCADE;

-- --- BOM ---
DROP TABLE IF EXISTS fnd_item_bom CASCADE;

-- --- Price books & items ---
DROP TABLE IF EXISTS fnd_pricebook_items CASCADE;
DROP TABLE IF EXISTS bps_items CASCADE;
DROP TABLE IF EXISTS fnd_customer_pricebooks CASCADE;
DROP TABLE IF EXISTS fnd_customers CASCADE;
DROP TABLE IF EXISTS fnd_pricebooks CASCADE;
DROP TABLE IF EXISTS fnd_currencies CASCADE;
DROP TABLE IF EXISTS fnd_items CASCADE;

-- --- Audit & tenants ---
DROP TABLE IF EXISTS fnd_audit_log CASCADE;
DROP TABLE IF EXISTS fnd_tenants CASCADE;

DROP TYPE IF EXISTS pricebook_assignment_type_enum CASCADE;
DROP TYPE IF EXISTS customer_type_enum CASCADE;
DROP TYPE IF EXISTS org_type_enum CASCADE;

DROP SEQUENCE IF EXISTS fnd_entity_id_seq CASCADE;
