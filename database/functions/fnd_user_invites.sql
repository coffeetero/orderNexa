-- ============================================================
-- User invites: add a user, prepare and record an invite, password-reset lookup, sign-in landing.
-- The website sends the email; these decide who may do what and from which sender.
-- Sender rule: staff emails come from OrderNexa (sender_address NULL = the app's OrderNexa address);
-- customer emails come from the tenancy (fnd_tenants.email_from_address, else OrderNexa's address under the tenancy's name).
-- ============================================================

-- Sender of the emails a user receives: { sender_name, sender_address, reply_to }.
CREATE OR REPLACE FUNCTION bps.fnd_email_sender_get(p_tenant_id bigint, p_user_type text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE WHEN p_user_type = 'CUSTOMER_USER'
              THEN jsonb_build_object('sender_name', t.tenant_name, 'sender_address', t.email_from_address, 'reply_to', t.email_reply_to)
              ELSE jsonb_build_object('sender_name', 'OrderNexa', 'sender_address', NULL, 'reply_to', NULL) END
    FROM bps.fnd_tenants t WHERE t.tenant_id = p_tenant_id
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_email_sender_get(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.fnd_email_sender_get(bigint, text) TO service_role, bps_dev;

-- Has this login ever signed in (accepted an invite)?
CREATE OR REPLACE FUNCTION bps.fnd_auth_user_signed_in(p_auth_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
  SELECT COALESCE((SELECT a.last_sign_in_at IS NOT NULL FROM auth.users a WHERE a.id = p_auth_user_id), false)
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_auth_user_signed_in(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_auth_user_signed_in(uuid) TO authenticated, service_role, bps_dev;

-- Adds a user to the tenancy (or attaches an existing BPS user with that email from another tenancy) with roles,
-- and for staff their customer groups. A customer user belongs to one customer account, which gets a portal
-- address (account_slug) from its name when it has none. Needs admin.users write. Returns the user_id.
CREATE OR REPLACE FUNCTION bps.fnd_user_create(p_tenant_id bigint, p_email text, p_user_name text, p_user_type text,
                                               p_customer_id bigint, p_role_ids bigint[], p_group_ids bigint[])
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_email text := lower(btrim(p_email));
    v_name  text := NULLIF(btrim(p_user_name), '');
    v_type  text := upper(btrim(p_user_type));
    v_me    bigint := bps.fnd_current_user_id();
    v_uid   bigint;
    v_old   record;
    v_cus   record;
    v_slug  text;
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF NOT bps.fnd_has_access('admin.users', 'W') THEN
        RAISE EXCEPTION 'You are not allowed to add users' USING ERRCODE = '42501';
    END IF;
    IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'A valid email is required'; END IF;
    IF v_name IS NULL THEN RAISE EXCEPTION 'A name is required'; END IF;
    IF v_type NOT IN ('TENANCY_USER', 'CUSTOMER_USER') THEN RAISE EXCEPTION 'Unknown user type %', p_user_type; END IF;
    IF v_type = 'CUSTOMER_USER' THEN
        SELECT customer_id, customer_name, customer_number, account_slug INTO v_cus
          FROM bps.fnd_customers WHERE customer_id = p_customer_id AND tenant_id = p_tenant_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Choose the customer account this user belongs to'; END IF;
    END IF;

    SELECT user_id, user_type INTO v_old FROM bps.fnd_users WHERE lower(email) = v_email AND deleted_at IS NULL;
    IF FOUND THEN
        IF EXISTS (SELECT 1 FROM bps.fnd_user_tenants WHERE user_id = v_old.user_id AND tenant_id = p_tenant_id) THEN
            RAISE EXCEPTION 'A user with this email already exists';
        END IF;
        IF v_old.user_type IS DISTINCT FROM v_type THEN
            RAISE EXCEPTION 'This email is already used by a different kind of user';
        END IF;
        v_uid := v_old.user_id;
    ELSE
        INSERT INTO bps.fnd_users (tenant_id, user_name, email, user_type, is_active, created_by, updated_by)
        VALUES (p_tenant_id, v_name, v_email, v_type, true, v_me, v_me)
        RETURNING user_id INTO v_uid;
    END IF;

    INSERT INTO bps.fnd_user_tenants (tenant_id, user_id, is_active, created_by, updated_by) VALUES (p_tenant_id, v_uid, true, v_me, v_me);

    IF v_type = 'CUSTOMER_USER' THEN
        INSERT INTO bps.fnd_user_customers (user_id, customer_id, tenant_id, created_by, updated_by) VALUES (v_uid, v_cus.customer_id, p_tenant_id, v_me, v_me);
        IF v_cus.account_slug IS NULL THEN
            v_slug := btrim(regexp_replace(lower(v_cus.customer_name), '[^a-z0-9]+', '-', 'g'), '-');
            IF v_slug = '' OR EXISTS (SELECT 1 FROM bps.fnd_customers WHERE tenant_id = p_tenant_id AND account_slug = v_slug) THEN
                v_slug := btrim(v_slug || '-' || lower(regexp_replace(v_cus.customer_number, '[^a-zA-Z0-9]+', '', 'g')), '-');
            END IF;
            UPDATE bps.fnd_customers SET account_slug = v_slug WHERE customer_id = v_cus.customer_id;
        END IF;
    END IF;

    PERFORM bps.fnd_user_access_save(p_tenant_id, v_uid, p_role_ids, p_group_ids, true);
    RETURN v_uid;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_create(bigint, text, text, text, bigint, bigint[], bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_create(bigint, text, text, text, bigint, bigint[], bigint[]) TO authenticated, service_role, bps_dev;

-- What the website needs to send an invite to a user of the tenancy:
-- { user_id, email, user_name, user_type, auth_user_id, signed_in, tenant_name, sender_name, sender_address, reply_to }.
CREATE OR REPLACE FUNCTION bps.fnd_user_invite_prepare(p_tenant_id bigint, p_user_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_out jsonb;
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF NOT bps.fnd_has_access('admin.users', 'W') THEN
        RAISE EXCEPTION 'You are not allowed to invite users' USING ERRCODE = '42501';
    END IF;
    SELECT jsonb_build_object('user_id', u.user_id, 'email', u.email, 'user_name', u.user_name, 'user_type', u.user_type,
                              'auth_user_id', u.auth_user_id, 'signed_in', bps.fnd_auth_user_signed_in(u.auth_user_id),
                              'tenant_name', t.tenant_name)
           || bps.fnd_email_sender_get(p_tenant_id, u.user_type)
      INTO v_out
      FROM bps.fnd_users u
      JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id
      JOIN bps.fnd_tenants t ON t.tenant_id = p_tenant_id
     WHERE u.user_id = p_user_id;
    IF v_out IS NULL THEN RAISE EXCEPTION 'User not found in this tenancy'; END IF;
    IF NOT (SELECT u.is_active AND u.deleted_at IS NULL AND ut.is_active FROM bps.fnd_users u JOIN bps.fnd_user_tenants ut
              ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id WHERE u.user_id = p_user_id) THEN
        RAISE EXCEPTION 'Activate the user before inviting them';
    END IF;
    IF NULLIF(v_out ->> 'email', '') IS NULL THEN RAISE EXCEPTION 'The user has no email'; END IF;
    RETURN v_out;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_invite_prepare(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_invite_prepare(bigint, bigint) TO authenticated, service_role, bps_dev;

-- Records a sent invite: links the user to their login (first invite) and stamps invited_at / invited_by.
CREATE OR REPLACE FUNCTION bps.fnd_user_invite_record(p_tenant_id bigint, p_user_id bigint, p_auth_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_auth uuid;
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF NOT bps.fnd_has_access('admin.users', 'W') THEN
        RAISE EXCEPTION 'You are not allowed to invite users' USING ERRCODE = '42501';
    END IF;
    SELECT u.auth_user_id INTO v_auth FROM bps.fnd_users u
      JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id WHERE u.user_id = p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'User not found in this tenancy'; END IF;
    IF v_auth IS NOT NULL AND v_auth IS DISTINCT FROM p_auth_user_id THEN
        RAISE EXCEPTION 'This user is already linked to a different login';
    END IF;
    UPDATE bps.fnd_users SET auth_user_id = p_auth_user_id, invited_at = now(), invited_by = bps.fnd_current_user_id(), updated_at = now()
     WHERE user_id = p_user_id;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_invite_record(bigint, bigint, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_invite_record(bigint, bigint, uuid) TO authenticated, service_role, bps_dev;

-- Forgot password: the login behind an email, and who the reset email comes from (the tenancy of the address the
-- request came from when the user belongs to it, else the user's home tenancy). NULL when there is no active user
-- with a login. Server only (service role): the website never tells the visitor whether the email exists.
CREATE OR REPLACE FUNCTION bps.fnd_user_reset_prepare(p_email text, p_host_slug text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
  SELECT jsonb_build_object('auth_user_id', u.auth_user_id, 'email', u.email, 'user_name', u.user_name, 'user_type', u.user_type,
                            'tenant_name', t.tenant_name) || bps.fnd_email_sender_get(t.tenant_id, u.user_type)
    FROM bps.fnd_users u
    JOIN LATERAL (
          SELECT t.tenant_id, t.tenant_name FROM bps.fnd_user_tenants ut JOIN bps.fnd_tenants t ON t.tenant_id = ut.tenant_id
           WHERE ut.user_id = u.user_id AND ut.is_active
           ORDER BY (t.tenant_slug = p_host_slug) DESC NULLS LAST, (t.tenant_id = u.tenant_id) DESC
           LIMIT 1) t ON true
   WHERE lower(u.email) = lower(btrim(p_email)) AND u.deleted_at IS NULL AND u.is_active AND u.auth_user_id IS NOT NULL
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_reset_prepare(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.fnd_user_reset_prepare(text, text) TO service_role, bps_dev;

-- Where a signed-in user lands: { user_type, account_slug } (account_slug for customer users, from their customer).
CREATE OR REPLACE FUNCTION bps.fnd_user_landing_get()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
  SELECT jsonb_build_object('user_type', u.user_type, 'account_slug',
           (SELECT c.account_slug FROM bps.fnd_user_customers uc JOIN bps.fnd_customers c ON c.customer_id = uc.customer_id
             WHERE uc.user_id = u.user_id AND uc.is_active
             ORDER BY (uc.tenant_id = bps.fnd_active_tenant_id()) DESC NULLS LAST LIMIT 1))
    FROM bps.fnd_users u WHERE u.auth_user_id = auth.uid()
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_landing_get() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_landing_get() TO authenticated, service_role, bps_dev;
