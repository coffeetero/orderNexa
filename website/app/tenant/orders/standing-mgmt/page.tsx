import { createClient } from '@/lib/supabase/server';
import { StandingOrderMgtPage } from '@/components/features/orders/StandingOrderMgtPage';

function toNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export default async function StandingOrderMgtRoute() {
  const supabase = createClient();
  const { data: tenantData } = await supabase.rpc('fnd_tenants_get');

  const tenants: { tenant_id: number; tenant_name: string }[] = Array.isArray(tenantData)
    ? (tenantData as Record<string, unknown>[]).flatMap((t) => {
        const id = toNumber(t.tenant_id);
        return id !== null ? [{ tenant_id: id, tenant_name: String(t.tenant_name ?? '') }] : [];
      })
    : [];

  const initialTenantId = tenants[0]?.tenant_id ?? null;

  return (
    <StandingOrderMgtPage
      tenants={tenants}
      initialTenantId={initialTenantId}
    />
  );
}
