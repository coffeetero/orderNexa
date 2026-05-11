-- Schema grants required by Supabase/PostgREST API roles.
-- Function EXECUTE alone is not enough; callers also need USAGE on the schema.

GRANT USAGE ON SCHEMA bps TO anon, authenticated;

GRANT SELECT ON TABLE fnd_valuesets TO anon, authenticated;
GRANT SELECT ON TABLE fnd_valueset_values TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE fnd_valuesets TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE fnd_valueset_values TO authenticated;
