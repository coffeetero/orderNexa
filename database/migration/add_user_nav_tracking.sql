-- Per-user navigation tracking (Quick Access + recent records). Generated from the files below; apply in this order.
-- Schema: SET search_path = bps, public;  (NOT yet applied to the cloud project.)
SET search_path = bps, public;

-- ===== schema/fnd_user_menu_actions.sql =====
-- ============================================================
-- FND_USER_MENU_ACTIONS  –  Per-user menu action usage + pinned Quick Access
--
-- One row per (user, menu action). Usage follows the PERSON, not the tenant, so there is no tenant_id.
-- action_key is the canonical staff nav href (e.g. '/orders', '/customers').
-- Up to 3 actions can be pinned (pin_order 1..3); everything else is ranked by use_count / last_used_at.
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_users.sql. Policies: ../policies/fnd_user_menu_actions_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_user_menu_actions (
    user_id       BIGINT       NOT NULL REFERENCES fnd_users(user_id) ON DELETE CASCADE,
    action_key    TEXT         NOT NULL,
    use_count     INTEGER      NOT NULL DEFAULT 0,
    last_used_at  TIMESTAMPTZ,
    is_pinned     BOOLEAN      NOT NULL DEFAULT FALSE,
    pin_order     SMALLINT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_fnd_user_menu_actions PRIMARY KEY (user_id, action_key),
    CONSTRAINT ck_fnd_user_menu_actions_key CHECK (action_key ~ '^/[a-z0-9/_-]*$' AND length(action_key) <= 120),
    CONSTRAINT ck_fnd_user_menu_actions_count CHECK (use_count >= 0),
    CONSTRAINT ck_fnd_user_menu_actions_pin CHECK (
        (is_pinned AND pin_order BETWEEN 1 AND 3) OR (NOT is_pinned AND pin_order IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_user_menu_actions_pin_order
    ON fnd_user_menu_actions (user_id, pin_order) WHERE is_pinned;

COMMENT ON TABLE fnd_user_menu_actions IS
    'Per-user menu action usage counts and pinned Quick Access actions (max 3). Not tenant-scoped.';

-- ===== schema/fnd_user_recent_records.sql =====
-- ============================================================
-- FND_USER_RECENT_RECORDS  –  Per-user, per-tenant recently accessed records
--
-- Drives the sidebar "Recent ..." lists. label/sublabel are snapshots taken when the record was last
-- opened, so the sidebar needs no joins. The functions keep at most 20 rows per (user, tenant, type).
-- record_key is text: ids for customer/order/item, 'YYYY-MM-DD|CODE' for production_run.
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_users.sql, fnd_tenants.sql. Policies: ../policies/fnd_user_recent_records_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_user_recent_records (
    user_id           BIGINT       NOT NULL REFERENCES fnd_users(user_id)     ON DELETE CASCADE,
    tenant_id         BIGINT       NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    record_type       TEXT         NOT NULL,
    record_key        TEXT         NOT NULL,
    label             TEXT         NOT NULL,
    sublabel          TEXT,
    access_count      INTEGER      NOT NULL DEFAULT 1,
    last_accessed_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_fnd_user_recent_records PRIMARY KEY (user_id, tenant_id, record_type, record_key),
    CONSTRAINT ck_fnd_user_recent_records_type CHECK (record_type IN ('customer', 'order', 'item', 'production_run')),
    CONSTRAINT ck_fnd_user_recent_records_key CHECK (length(record_key) BETWEEN 1 AND 64),
    CONSTRAINT ck_fnd_user_recent_records_label CHECK (length(label) BETWEEN 1 AND 200),
    CONSTRAINT ck_fnd_user_recent_records_sublabel CHECK (sublabel IS NULL OR length(sublabel) <= 200)
);

CREATE INDEX IF NOT EXISTS idx_fnd_user_recent_records_lookup
    ON fnd_user_recent_records (user_id, tenant_id, record_type, last_accessed_at DESC);

COMMENT ON TABLE fnd_user_recent_records IS
    'Recently opened customers/orders/items/production runs per user and tenant (max 20 per type).';

-- ===== functions/fnd_nav_app_user_id.sql =====
-- ============================================================
-- fnd_nav_app_user_id
-- Returns the BPS user id (fnd_users.user_id) from the JWT claim app_metadata.app_user_id that the
-- access-token hook (bps_access_token_hook) puts into every token. NULL when absent (e.g. anon).
-- Used by the per-user navigation tables' RLS policies and functions.
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_app_user_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SET search_path = bps, public
AS $$
  SELECT NULLIF(
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' ->> 'app_user_id'),
    'null'
  )::BIGINT
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_app_user_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_app_user_id() TO authenticated, bps_dev, service_role;

-- ===== policies/fnd_user_menu_actions_policies.sql =====
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

-- ===== policies/fnd_user_recent_records_policies.sql =====
-- ============================================================
-- FND_USER_RECENT_RECORDS — Row Level Security
-- A user sees only their own rows, and only for tenants named in allowed_tenant_ids.
-- Run after: fnd_user_recent_records.sql, functions/fnd_nav_app_user_id.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_user_recent_records TO authenticated;
GRANT ALL ON TABLE fnd_user_recent_records TO bps_dev;

ALTER TABLE fnd_user_recent_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_recent_records_owner ON fnd_user_recent_records;
CREATE POLICY pol_fnd_user_recent_records_owner ON fnd_user_recent_records
    FOR ALL
    USING (
        user_id = bps.fnd_nav_app_user_id()
        AND tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
            )
        ))
    )
    WITH CHECK (
        user_id = bps.fnd_nav_app_user_id()
        AND tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
            )
        ))
    );

-- ===== functions/fnd_nav_touch.sql =====
-- ============================================================
-- fnd_nav_touch
-- Records navigation activity for the signed-in user (fire-and-forget from the app):
--   • p_action_key  -> bumps fnd_user_menu_actions.use_count (Quick Access ranking)
--   • p_record_type -> upserts fnd_user_recent_records for (user, tenant, type, key) and prunes the
--                      list to the 20 most recent per (user, tenant, type)
-- SECURITY INVOKER: RLS on both tables enforces "own rows only" and allowed tenants; the tenant is also
-- validated here for a clear error. Prerequisites: fnd_user_menu_actions.sql, fnd_user_recent_records.sql,
-- fnd_nav_app_user_id.sql and both policy files.
-- clock_timestamp() (not NOW()) so ordering is exact even for several touches inside one transaction.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_touch(
  p_tenant_id   BIGINT,
  p_action_key  TEXT DEFAULT NULL,
  p_record_type TEXT DEFAULT NULL,
  p_record_key  TEXT DEFAULT NULL,
  p_label       TEXT DEFAULT NULL,
  p_sublabel    TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  IF p_tenant_id IS NULL OR NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  IF p_action_key IS NOT NULL THEN
    INSERT INTO fnd_user_menu_actions (user_id, action_key, use_count, last_used_at)
    VALUES (v_user_id, p_action_key, 1, clock_timestamp())
    ON CONFLICT (user_id, action_key) DO UPDATE
      SET use_count    = fnd_user_menu_actions.use_count + 1,
          last_used_at = clock_timestamp(),
          updated_at   = clock_timestamp();
  END IF;

  IF p_record_type IS NOT NULL THEN
    IF NULLIF(BTRIM(p_record_key), '') IS NULL OR NULLIF(BTRIM(p_label), '') IS NULL THEN
      RAISE EXCEPTION 'p_record_key and p_label are required when p_record_type is set';
    END IF;

    INSERT INTO fnd_user_recent_records (user_id, tenant_id, record_type, record_key, label, sublabel, last_accessed_at)
    VALUES (v_user_id, p_tenant_id, p_record_type, BTRIM(p_record_key),
            LEFT(BTRIM(p_label), 200), LEFT(NULLIF(BTRIM(COALESCE(p_sublabel, '')), ''), 200), clock_timestamp())
    ON CONFLICT (user_id, tenant_id, record_type, record_key) DO UPDATE
      SET label            = EXCLUDED.label,
          sublabel         = EXCLUDED.sublabel,
          access_count     = fnd_user_recent_records.access_count + 1,
          last_accessed_at = clock_timestamp();

    DELETE FROM fnd_user_recent_records r
     WHERE r.user_id = v_user_id AND r.tenant_id = p_tenant_id AND r.record_type = p_record_type
       AND r.record_key NOT IN (
         SELECT k.record_key FROM fnd_user_recent_records k
          WHERE k.user_id = v_user_id AND k.tenant_id = p_tenant_id AND k.record_type = p_record_type
          ORDER BY k.last_accessed_at DESC
          LIMIT 20
       );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_touch(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_touch(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, bps_dev, service_role;

-- ===== functions/fnd_nav_sidebar_get.sql =====
-- ============================================================
-- fnd_nav_sidebar_get
-- One round trip for the sidebar: the user's menu action usage/pins (all tenants) and the user's recent
-- records for p_tenant_id (optionally limited to p_types, at most p_limit per type).
-- Ranking/defaults are applied in the app (website/lib/quick-access.ts).
-- SECURITY INVOKER: RLS limits rows to the caller and the tenants in allowed_tenant_ids.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_sidebar_get(
  p_tenant_id BIGINT,
  p_types     TEXT[] DEFAULT NULL,
  p_limit     INTEGER DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  IF p_tenant_id IS NULL OR NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  RETURN jsonb_build_object(
    'actions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'action_key',   a.action_key,
               'use_count',    a.use_count,
               'last_used_at', a.last_used_at,
               'is_pinned',    a.is_pinned,
               'pin_order',    a.pin_order
             ) ORDER BY a.is_pinned DESC, a.pin_order, a.use_count DESC, a.last_used_at DESC NULLS LAST)
        FROM (SELECT * FROM fnd_user_menu_actions WHERE user_id = v_user_id LIMIT 100) a
    ), '[]'::jsonb),
    'recents', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'record_type',      r.record_type,
               'record_key',       r.record_key,
               'label',            r.label,
               'sublabel',         r.sublabel,
               'last_accessed_at', r.last_accessed_at
             ) ORDER BY r.record_type, r.last_accessed_at DESC)
        FROM (
          SELECT x.*, ROW_NUMBER() OVER (PARTITION BY x.record_type ORDER BY x.last_accessed_at DESC) AS rn
            FROM fnd_user_recent_records x
           WHERE x.user_id = v_user_id AND x.tenant_id = p_tenant_id
             AND (p_types IS NULL OR x.record_type = ANY (p_types))
        ) r
       WHERE r.rn <= GREATEST(1, LEAST(COALESCE(p_limit, 5), 20))
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_sidebar_get(BIGINT, TEXT[], INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_sidebar_get(BIGINT, TEXT[], INTEGER) TO authenticated, bps_dev, service_role;

-- ===== functions/fnd_nav_pins_set.sql =====
-- ============================================================
-- fnd_nav_pins_set
-- Replaces the signed-in user's pinned Quick Access actions with p_action_keys (ordered, max 3, unique).
-- Pass an empty array to unpin everything. Usage counts are preserved; actions without a row get one.
-- SECURITY INVOKER: RLS limits the rows to the caller.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_pins_set(p_action_keys TEXT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
  v_keys    TEXT[] := COALESCE(p_action_keys, ARRAY[]::TEXT[]);
  v_i       INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  IF cardinality(v_keys) > 3 THEN
    RAISE EXCEPTION 'At most 3 actions can be pinned';
  END IF;

  IF (SELECT COUNT(DISTINCT k) FROM unnest(v_keys) AS k) <> cardinality(v_keys) THEN
    RAISE EXCEPTION 'Pinned actions must be unique';
  END IF;

  UPDATE fnd_user_menu_actions
     SET is_pinned = FALSE, pin_order = NULL, updated_at = NOW()
   WHERE user_id = v_user_id AND is_pinned;

  FOR v_i IN 1 .. cardinality(v_keys) LOOP
    INSERT INTO fnd_user_menu_actions (user_id, action_key, is_pinned, pin_order)
    VALUES (v_user_id, v_keys[v_i], TRUE, v_i)
    ON CONFLICT (user_id, action_key) DO UPDATE
      SET is_pinned = TRUE, pin_order = v_i, updated_at = NOW();
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_pins_set(TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_pins_set(TEXT[]) TO authenticated, bps_dev, service_role;
