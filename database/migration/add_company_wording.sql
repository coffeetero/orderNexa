-- Client-facing wording: "Tenant" becomes "Company". Data only, no table or column changes.
-- Needed only where the access-model migrations were applied before this wording change.
UPDATE bps.fnd_roles SET role_name = 'Company Administrator' WHERE role_name = 'Tenant Administrator' AND is_system;
UPDATE bps.fnd_areas SET area_name = 'Company Roles' WHERE area_key = 'admin.roles';

-- New tenants must be seeded with the new name too.
DO $$
DECLARE d TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'bps' AND p.proname = 'fnd_tenant_access_seed';
  IF d LIKE '%Tenant Administrator%' THEN EXECUTE replace(d, 'Tenant Administrator', 'Company Administrator'); END IF;
END $$;
