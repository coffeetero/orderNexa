-- ============================================================
-- SEED: Alpine Bakery tenant + bootstrap contacts
-- Target: Supabase (PostgreSQL 15+)
--
-- Run after (schema objects exist):
--   fnd_entity_id_seq.sql, fnd_tenants.sql, fnd_customers.sql,
--   fnd_users.sql, fnd_user_tenants.sql,
--   fnd_people.sql, fnd_contact_points.sql
--
-- Idempotent: safe to re-run.
--
-- Tenant row: INSERT runs only when no row exists with tenant_name = 'Alpine Bakery',
-- so an existing Alpine Bakery row (and its stable BIGINT tenant_id) is never duplicated.
-- ============================================================

-- Optional: skip audit triggers during bulk seed (see fn_audit_log in fnd_tenants.sql).
-- is_local = false so the flag applies across statements when not in a single transaction.
SELECT set_config('app.audit_enabled', 'false', false);

-- ----------------------------------------------------------------
-- 1. First tenant: Alpine Bakery
-- ----------------------------------------------------------------

INSERT INTO fnd_tenants (tenant_name, plan)
SELECT 'Alpine Bakery', 'PRO'
WHERE NOT EXISTS (
    SELECT 1 FROM fnd_tenants tnt WHERE tnt.tenant_name = 'Alpine Bakery'
);

-- ----------------------------------------------------------------
-- 2. People for Alpine Bakery
-- ----------------------------------------------------------------

INSERT INTO fnd_people (
    first_name,
    last_name,
    display_name,
    primary_phone,
    primary_email,
    tenant_id
)
SELECT
    v.first_name,
    v.last_name,
    v.display_name,
    v.primary_phone,
    v.primary_email,
    tnt.tenant_id
FROM (
    VALUES
        ('Glen',  'Mora', 'Glen Mora',  '407-242-6380', 'moraglen@gmail.com'),
        ('Maria', 'Mora', 'Maria Mora', '407-242-6381', 'moraglen@yahoo.com')
) AS v(first_name, last_name, display_name, primary_phone, primary_email)
CROSS JOIN LATERAL (
    SELECT tnt.tenant_id
    FROM fnd_tenants tnt
    WHERE tnt.tenant_name = 'Alpine Bakery'
    LIMIT 1
) AS tnt (tenant_id)
WHERE NOT EXISTS (
    SELECT 1
    FROM fnd_people prsn
    WHERE prsn.tenant_id = tnt.tenant_id
      AND prsn.primary_email = v.primary_email
);

-- ----------------------------------------------------------------
-- 3. Contact points (entity_id = first customer in tenant, else 0)
-- ----------------------------------------------------------------

INSERT INTO fnd_contact_points (
    entity_id,
    person_id,
    label,
    is_primary,
    tenant_id
)
SELECT
    COALESCE(
        (SELECT MIN(cus.customer_id) FROM fnd_customers cus WHERE cus.tenant_id = prsn.tenant_id),
        0::BIGINT
    ),
    prsn.person_id,
    NULL,
    TRUE,
    prsn.tenant_id
FROM fnd_people prsn
INNER JOIN fnd_tenants tnt ON tnt.tenant_id = prsn.tenant_id AND tnt.tenant_name = 'Alpine Bakery'
WHERE prsn.primary_email IN ('moraglen@gmail.com', 'moraglen@yahoo.com')
  AND NOT EXISTS (
        SELECT 1
        FROM fnd_contact_points cntctPnt
        WHERE cntctPnt.tenant_id = prsn.tenant_id
          AND cntctPnt.person_id = prsn.person_id
    );


-- ----------------------------------------------------------------
-- 4. Seed fnd_users from auth.users for Alpine Bakery tenant
-- ----------------------------------------------------------------

INSERT INTO fnd_users (
    tenant_id,
    auth_user_id,
    user_name,
    email,
    is_active,
    last_login_at
)
SELECT
    tnt.tenant_id,
    authUsr.id,
    COALESCE(NULLIF(TRIM(BOTH FROM authUsr.raw_user_meta_data ->> 'user_name'), ''), authUsr.email),
    authUsr.email,
    TRUE,
    authUsr.last_sign_in_at
FROM auth.users authUsr
INNER JOIN fnd_tenants tnt
    ON tnt.tenant_name = 'Alpine Bakery'
WHERE NOT EXISTS (
    SELECT 1
    FROM fnd_users usr
    WHERE usr.auth_user_id = authUsr.id
);

-- ----------------------------------------------------------------
-- 5. Seed fnd_user_tenants for all users from fnd_users
-- ----------------------------------------------------------------

INSERT INTO fnd_user_tenants (
    tenant_id,
    user_id,
    is_active,
    is_customer_restricted
)
SELECT
    usr.tenant_id,
    usr.user_id,
    TRUE,
    FALSE
FROM fnd_users usr
WHERE NOT EXISTS (
        SELECT 1
        FROM fnd_user_tenants usrTnt
        WHERE usrTnt.tenant_id = usr.tenant_id
          AND usrTnt.user_id = usr.user_id
    );

-- Enforce requested restriction flags by user identifier.
UPDATE fnd_user_tenants usrTnt
SET is_customer_restricted = FALSE
FROM fnd_users usr
WHERE usr.user_id = usrTnt.user_id
  AND usrTnt.tenant_id = usr.tenant_id
  AND (LOWER(COALESCE(usr.user_name, '')) = 'moraglen@gmail.com'
       OR LOWER(COALESCE(usr.email, '')) = 'moraglen@gmail.com');

UPDATE fnd_user_tenants usrTnt
SET is_customer_restricted = TRUE
FROM fnd_users usr
WHERE usr.user_id = usrTnt.user_id
  AND usrTnt.tenant_id = usr.tenant_id
  AND (LOWER(COALESCE(usr.user_name, '')) = 'maria@bps.com'
       OR LOWER(COALESCE(usr.email, '')) = 'maria@bps.com');

-- Seed customer restrictions for maria@bps.com every run from live customer query.
INSERT INTO fnd_user_customers (
    user_id,
    customer_id,
    tenant_id,
    is_active
)
SELECT
    usr.user_id,
    q.customer_id,
    usr.tenant_id,
    TRUE
FROM fnd_users usr
JOIN (
    SELECT cus.customer_id
    FROM fnd_customers cus
    INNER JOIN fnd_tenants tnt ON tnt.tenant_id = cus.tenant_id AND tnt.tenant_name = 'Alpine Bakery'
    WHERE cus.customer_type = 'ACCOUNT'
      AND cus.customer_parent_id IS NULL
      AND EXISTS (
          SELECT 1
          FROM om_orders ordr
          WHERE ordr.customer_id = cus.customer_id
      )
    ORDER BY cus.customer_id
    LIMIT 20
) q ON TRUE
WHERE (LOWER(COALESCE(usr.user_name, '')) = 'maria@bps.com'
       OR LOWER(COALESCE(usr.email, '')) = 'maria@bps.com')
  AND usr.tenant_id = (SELECT tnt.tenant_id FROM fnd_tenants tnt WHERE tnt.tenant_name = 'Alpine Bakery' LIMIT 1)
  AND NOT EXISTS (
        SELECT 1
        FROM fnd_user_customers usrCus
        WHERE usrCus.user_id = usr.user_id
          AND usrCus.customer_id = q.customer_id
          AND usrCus.tenant_id = usr.tenant_id
    );

SELECT set_config('app.audit_enabled', 'true', false);
