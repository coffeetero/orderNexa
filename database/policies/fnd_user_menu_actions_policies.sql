-- ============================================================
-- FND_USER_MENU_ACTIONS — Row Level Security
-- A user can only see and change their own rows (user_id = app_user_id claim).
-- Run after: fnd_user_menu_actions.sql, functions/fnd_nav_app_user_id.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_user_menu_actions TO authenticated;
GRANT ALL ON TABLE fnd_user_menu_actions TO bps_dev;

ALTER TABLE fnd_user_menu_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_menu_actions_owner ON fnd_user_menu_actions;
CREATE POLICY pol_fnd_user_menu_actions_owner ON fnd_user_menu_actions
    FOR ALL
    USING      (user_id = bps.fnd_nav_app_user_id())
    WITH CHECK (user_id = bps.fnd_nav_app_user_id());
