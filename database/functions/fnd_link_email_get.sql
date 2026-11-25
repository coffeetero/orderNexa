-- ============================================================
-- fnd_link_email_get (Choose your password page)
-- Whose invite or password-reset link this is, without using the link up: the page shows the email above the password
-- fields, and says at once when the link is no longer valid. Reads Supabase's own one-time link table (auth.one_time_tokens,
-- where verifyOtp looks the link up); the link is used only when the person submits the new password.
--   p_token_hash  the token_hash from the emailed link
--   p_type        'invite' or 'recovery' (the link's type parameter)
-- Returns {valid: true, email} for a link that still works, {valid: false} otherwise (unknown, already used, or older than
-- 24 hours, which is the link lifetime the emails state). Only someone holding a valid link learns its email; the hashes
-- cannot be guessed. Callable before sign-in (anon). SECURITY DEFINER: reads the auth schema. No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_link_email_get(p_token_hash text, p_type text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
  SELECT COALESCE(
    (SELECT jsonb_build_object('valid', true, 'email', t.relates_to)
       FROM auth.one_time_tokens t
      WHERE length(COALESCE(p_token_hash, '')) BETWEEN 20 AND 200
        AND t.token_hash = p_token_hash
        AND t.token_type::text = CASE WHEN p_type = 'recovery' THEN 'recovery_token' ELSE 'confirmation_token' END
        AND t.created_at > (now() AT TIME ZONE 'UTC') - interval '24 hours'
      LIMIT 1),
    jsonb_build_object('valid', false))
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_link_email_get(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_link_email_get(text, text) TO anon, authenticated, service_role, bps_dev;
