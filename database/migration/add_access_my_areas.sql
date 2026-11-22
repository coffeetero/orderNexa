-- Areas the signed-in user may read (drives which top-menu entries are shown). SECURITY INVOKER; fnd_has_access does the check.
CREATE OR REPLACE FUNCTION bps.fnd_my_areas() RETURNS text[]
LANGUAGE sql STABLE SET search_path = bps, public AS
$$ SELECT COALESCE(array_agg(a.area_key ORDER BY a.area_key), '{}') FROM bps.fnd_areas a WHERE bps.fnd_has_access(a.area_key, 'R') $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_my_areas() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION bps.fnd_my_areas() TO authenticated, service_role, bps_dev;
