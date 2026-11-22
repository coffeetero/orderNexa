-- ============================================================
-- fnd_session_get_timeout
-- Purpose: inactivity timeout (minutes) for the customer portal session.
--   Called by website/app/[account_slug]/layout.tsx via rpc().
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- NOTE: this file previously had no .sql extension and was never deployed.
-- ============================================================

create or replace function fnd_session_get_timeout(p_user_id bigint)
returns integer
language plpgsql
stable
as $$
begin
  -- future: lookup by user / tenant / role
  return 60;
end;
$$;
