-- Schema grants required by Supabase/PostgREST API roles.
-- Function EXECUTE alone is not enough; callers also need USAGE on the schema.

GRANT USAGE ON SCHEMA bps TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE ON TABLE fnd_notes TO authenticated;
GRANT ALL ON TABLE fnd_notes TO bps_dev;

-- Contacts (added when fnd_contacts / fnd_contact_points were created)
GRANT ALL ON TABLE fnd_contacts       TO bps_dev;
GRANT ALL ON TABLE fnd_contact_points TO bps_dev;

-- Standing orders (added when om_standing_orders was created)
GRANT ALL ON TABLE om_standing_orders TO bps_dev;

-- Shared entity ID sequence (used by PK defaults on all entity tables)
GRANT USAGE, SELECT ON SEQUENCE fnd_entity_id_seq TO bps_dev;

-- Tenant sequence allocator support
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_tenant_sequences TO bps_dev;
GRANT EXECUTE ON FUNCTION fnd_tenant_sequence_format(TEXT, BIGINT, DATE) TO bps_dev;
GRANT EXECUTE ON FUNCTION fnd_tenant_sequence_reset_key(TEXT, DATE) TO bps_dev;
GRANT EXECUTE ON FUNCTION fnd_tenant_sequence_next(BIGINT, TEXT, DATE) TO bps_dev;

GRANT SELECT ON TABLE fnd_valuesets TO anon, authenticated;
GRANT SELECT ON TABLE fnd_valueset_values TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE fnd_valuesets TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE fnd_valueset_values TO authenticated;
