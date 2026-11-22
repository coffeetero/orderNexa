# Access model (roles, areas, data scope, one tenancy per session)

Status: built locally (steps a-d). Not applied to the cloud. Admin screens: Admin > Roles & Access, Users, Customer Groups, Phone & Messaging (API in add_access_admin_functions, add_access_my_areas.sql). Creating new users is not built.

## Rules
- One active tenancy per auth session: `app_metadata.tenant_id` (+ `tenant_slug`), issued by `bps_access_token_hook` from `fnd_user_active_tenant`
  (keyed by session id). One tenancy is auto-selected; two or more require the picker (`/select-tenant`). On a tenant address the token's tenant must
  equal the address. `allowed_tenant_ids` / `restricted_tenant_ids` now carry only the active tenant (empty until chosen).
- User -> Role -> Area access. `fnd_areas` (registry, audience TENANT or CUSTOMER), `fnd_roles` (audience; `owner_customer_id` for roles a customer
  created), `fnd_user_roles`, `fnd_role_area_access` (read, write, approve, void, delete; any action implies read). Deny by default.
  Audience of user type, role and area must match, so a customer user can never reach a staff area.
- Data scope: `fnd_customer_groups` (All Customers = flag, no members), `fnd_customer_group_members`, `fnd_customer_group_effective`
  (own groups, else nearest ancestor's; trigger maintained), `fnd_user_customer_groups` (tenant users). Customer users are scoped to their own
  customers and everything beneath (`fnd_user_customers`). A tenant user with no group sees no customers.
- RLS: every fnd_/om_/ar_ table has policies from `add_rls_access_model.sql`: active tenant AND area access AND (customer-linked rows) scope.
  anon has no access in schema bps. Former definer API functions run as the caller; remaining definer helpers assert the active tenant.

## Functions
`fnd_has_access(area, action)`, `fnd_has_access_any(areas[], action)`, `fnd_has_any_access(action)`, `fnd_scope_is_all()`, `fnd_scope_customer_ids()`,
`fnd_customer_in_scope(id)`, `fnd_assert_active_tenant(id)`, `fnd_user_tenancies_get()`, `fnd_user_select_tenant(id, host_slug)`.
In policies wrap them as `(SELECT ...)` so Postgres evaluates them once per query.

## Apply order
add_access_model_tables, add_access_model_functions, add_active_tenancy, add_rls_access_model, add_access_admin_functions, add_access_my_areas.

## Tests
`database/tests/`: access_model_test, active_tenancy_test, access_admin_test, rls_test (also scans every table and function for missing RLS or anon access).

## Open / not done
- Screens for customer admins (the portal side: their own users and roles) and creating/inviting users.
- Only the Admin top menu is hidden by area access (pages under Admin return not-found too); other menus still show every entry (RLS enforces the data).
- Older functions still contain their own allowed_tenant_ids checks; they work because the token narrows that list. Replace with `fnd_assert_active_tenant` over time.
- New tables get anon grants from Supabase default privileges: always `REVOKE ALL ... FROM anon` and enable RLS (rls_test fails otherwise).
- Cloud: apply the four migrations plus the earlier ones; the unprefixed legacy tables now have RLS on and no app access.
