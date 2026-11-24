-- ============================================================
-- User invites (2026-11-24)
-- fnd_tenants.email_from_address / email_reply_to: sender of the emails a tenancy sends its customers (invites,
--   password resets). Empty = sent from OrderNexa's address under the tenancy's name.
-- fnd_users.invited_at / invited_by: the last invite sent and who sent it.
-- ============================================================
ALTER TABLE bps.fnd_tenants ADD COLUMN IF NOT EXISTS email_from_address text
  CHECK (email_from_address IS NULL OR email_from_address ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
ALTER TABLE bps.fnd_tenants ADD COLUMN IF NOT EXISTS email_reply_to text
  CHECK (email_reply_to IS NULL OR email_reply_to ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
ALTER TABLE bps.fnd_users ADD COLUMN IF NOT EXISTS invited_at timestamptz;
ALTER TABLE bps.fnd_users ADD COLUMN IF NOT EXISTS invited_by bigint REFERENCES bps.fnd_users(user_id) ON DELETE SET NULL;

-- one person = one login: emails are unique (case-insensitive) among users not deleted
CREATE UNIQUE INDEX IF NOT EXISTS fnd_users_email_key ON bps.fnd_users (lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL;

-- a user added by an administrator has no login until they accept their invite
ALTER TABLE bps.fnd_users ALTER COLUMN auth_user_id DROP NOT NULL;
