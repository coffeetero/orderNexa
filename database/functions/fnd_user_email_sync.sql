-- ============================================================
-- fnd_user_email_sync: keeps fnd_users.email in step with the sign-in account (auth.users.email).
-- When a person's sign-in email changes (Profile › Change email, or any other way, such as the Supabase dashboard), their
-- BPS user record gets the same address. Access never depends on the email: roles, companies and history hang off
-- fnd_users.user_id / auth_user_id.
-- fnd_users.email is unique across BPS (fnd_users_email_key), so a change to an address another BPS user already has
-- fails here and the sign-in change is rolled back with it; the website checks this first and explains.
-- fnd_email_available(p_email, p_auth_user_id): that check, for the website (service role only).
-- SECURITY DEFINER (runs as the owner: the trigger fires on Supabase's auth schema). No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_user_email_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email AND NEW.email IS NOT NULL THEN
    UPDATE bps.fnd_users SET email = NEW.email WHERE auth_user_id = NEW.id AND email IS DISTINCT FROM NEW.email;
  END IF;
  RETURN NEW;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_email_sync() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_auth_users_bps_email_sync ON auth.users;
CREATE TRIGGER trg_auth_users_bps_email_sync AFTER UPDATE OF email ON auth.users
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_user_email_sync();

CREATE OR REPLACE FUNCTION bps.fnd_email_available(p_email text, p_auth_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
  SELECT NOT EXISTS (SELECT 1 FROM bps.fnd_users u WHERE lower(u.email) = lower(btrim(p_email)) AND u.deleted_at IS NULL
                       AND u.auth_user_id IS DISTINCT FROM p_auth_user_id)
     AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE lower(a.email) = lower(btrim(p_email)) AND a.id <> p_auth_user_id)
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_email_available(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.fnd_email_available(text, uuid) TO service_role, bps_dev;
