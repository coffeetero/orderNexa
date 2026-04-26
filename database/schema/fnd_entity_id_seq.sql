-- ============================================================
-- FND_ENTITY_ID_SEQ  –  Global BIGINT surrogate-id sequence
-- Target: Supabase (PostgreSQL 15+)
--
-- Use for primary keys that share one numeric space across fnd_* tables via:
--   DEFAULT nextval('fnd_entity_id_seq'::regclass)
--
-- Adopters: fnd_tenants.tenant_id, fnd_audit_log.id, fnd_customers.customer_id,
-- fnd_currencies.currency_id, fnd_items.item_id, om_orders.order_id, om_order_lines.order_line_id,
-- fnd_item_bom.item_bom_id, fnd_pricebooks.pricebook_id, fnd_pricebook_items.pricebook_item_id
--
-- Do not use OWNED BY when multiple tables share this sequence.
-- After loading legacy data, align the sequence:
--   SELECT setval('fnd_entity_id_seq', (SELECT MAX(m) FROM (...)));
--
-- Run before INSERTs that rely on the default, typically early in bootstrap.
-- Required before fnd_customers.sql when using DEFAULT nextval for customer_id.
-- ============================================================

CREATE SEQUENCE IF NOT EXISTS fnd_entity_id_seq
    AS BIGINT
    START WITH 200000000001
    INCREMENT BY 1
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

COMMENT ON SEQUENCE fnd_entity_id_seq IS
    'Global sequence for entity-style primary keys; nextval shared across tables that adopt it.';
