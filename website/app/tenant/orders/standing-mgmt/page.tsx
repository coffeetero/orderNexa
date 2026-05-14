import { headers } from 'next/headers';
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

  // Tenants
  const { data: tenantData } = await supabase.rpc('fnd_tenants_get');
  const tenants: { tenant_id: number; tenant_name: string }[] = Array.isArray(tenantData)
    ? (tenantData as Record<string, unknown>[]).flatMap((t) => {
        const id = toNumber(t.tenant_id);
        return id !== null ? [{ tenant_id: id, tenant_name: String(t.tenant_name ?? '') }] : [];
      })
    : [];

  const initialTenantId = tenants[0]?.tenant_id ?? null;

  // Customers (active, with hierarchy)
  let initialCustomers: { customer_id: number; customer_name: string; customer_number: string | null; customer_parent_id: number | null; sort_path: string }[] = [];

  if (initialTenantId !== null) {
    const h = headers();
    const proto = h.get('x-forwarded-proto') ?? 'http';
    const host  = h.get('host') ?? '';
    const cookie = h.get('cookie') ?? '';
    try {
      const res  = await fetch(`${proto}://${host}/api/customers?tenant_id=${initialTenantId}&hierarchy=true&active=true`, { headers: { cookie }, cache: 'no-store' });
      const json = await res.json() as { data?: unknown[] };
      initialCustomers = (json.data ?? []).flatMap((r) => {
        const row = r as Record<string, unknown>;
        const id  = toNumber(row.customer_id);
        return id !== null ? [{
          customer_id:        id,
          customer_name:      String(row.customer_name ?? ''),
          customer_number:    row.customer_number != null ? String(row.customer_number) : null,
          customer_parent_id: toNumber(row.customer_parent_id),
          sort_path:          String(row.sort_path ?? ''),
        }] : [];
      });
    } catch { /* leave empty */ }
  }

  return (
    <StandingOrderMgtPage
      tenants={tenants}
      initialTenantId={initialTenantId}
      initialCustomers={initialCustomers}
    />
  );
}
