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
