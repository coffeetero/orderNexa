-- ============================================================
-- FND_CURRENCIES — Row Level Security
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after: fnd_currencies.sql (table + triggers + bootstrap INSERT).
-- SELECT USING (TRUE) — enable may still require elevated role per project defaults.
-- ============================================================

ALTER TABLE fnd_currencies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_currencies_select ON fnd_currencies;
CREATE POLICY pol_fnd_currencies_select ON fnd_currencies
    FOR SELECT
    USING (TRUE);
