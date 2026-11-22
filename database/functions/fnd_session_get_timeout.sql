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
