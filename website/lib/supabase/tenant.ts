import { createClient } from '@/lib/supabase/server';

/** The signed-in user's tenant id, resolved on the server (the browser token carries allowed_tenant_ids, not a tenant_id). */
export async function getCurrentTenantId(): Promise<number | null> {
  const { data } = await (await createClient()).rpc('fnd_tenants_get');
  const tenants = Array.isArray(data) ? data : [];
  return tenants.length > 0 ? (tenants[0].tenant_id as number) : null;
}
