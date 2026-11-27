import { createClient } from '@/lib/supabase/server';
import { localDateIso } from '@/lib/date';
import { PostStandingOrdersPage } from '@/components/features/orders/PostStandingOrdersPage';

function toNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function tomorrowIso(): string {
  return localDateIso(1);
}

export default async function PostStandingOrdersRoute() {
  const supabase = await createClient();
  const { data: tenantData } = await supabase.rpc('fnd_tenants_get');

  const tenants: { tenant_id: number; tenant_name: string }[] = Array.isArray(tenantData)
    ? (tenantData as Record<string, unknown>[]).flatMap(t => {
        const id = toNumber(t.tenant_id);
        return id !== null ? [{ tenant_id: id, tenant_name: String(t.tenant_name ?? '') }] : [];
      })
    : [];

  return (
    <PostStandingOrdersPage
      initialTenantId={tenants[0]?.tenant_id ?? null}
      defaultDate={tomorrowIso()}
    />
  );
}
