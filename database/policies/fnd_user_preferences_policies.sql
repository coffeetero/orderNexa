-- ============================================================
-- FND_USER_PREFERENCES — Row Level Security
-- A user can only see and change their own row (user_id = app_user_id claim).
-- Run after: fnd_user_preferences.sql, functions/fnd_nav_app_user_id.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_user_preferences TO authenticated;
GRANT ALL ON TABLE fnd_user_preferences TO bps_dev;

ALTER TABLE fnd_user_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_preferences_owner ON fnd_user_preferences;
CREATE POLICY pol_fnd_user_preferences_owner ON fnd_user_preferences
    FOR ALL
    USING      (user_id = bps.fnd_nav_app_user_id())
    WITH CHECK (user_id = bps.fnd_nav_app_user_id());
