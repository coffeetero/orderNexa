-- Schema grants required by Supabase/PostgREST API roles.
-- Function EXECUTE alone is not enough; callers also need USAGE on the schema.

GRANT USAGE ON SCHEMA bps TO anon, authenticated;
