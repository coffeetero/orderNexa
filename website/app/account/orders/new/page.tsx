import { headers } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import { OrderEntryForm } from '@/components/features/tenant/order-entry/OrderEntryForm';
import type { CustomerOption } from '@/components/features/tenant/order-entry/OrderHeaderRow';

export const metadata = {
  title: 'New Order — Order Entry',
};

export default async function NewOrderPage() {
  const supabase = createClient();

  // Resolve tenant via RPC (same pattern as /account/customers/page.tsx)
  const { data: tenantData } = await supabase.rpc('fnd_get_tenants');
  const tenants = Array.isArray(tenantData) ? tenantData : [];
  const tenantId: number | null = tenants.length > 0 ? tenants[0].tenant_id : null;

  // Pre-load customers server-side so the form renders with data immediately
  let initialCustomers: CustomerOption[] = [];

  if (tenantId !== null) {
    const h = headers();
    const host = h.get('host');
    const proto = h.get('x-forwarded-proto') ?? 'http';
    const cookie = h.get('cookie') ?? '';
    const apiUrl = `${proto}://${host}/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`;

    try {
      const response = await fetch(apiUrl, {
        headers: { cookie },
        cache: 'no-store',
      });
      const json = (await response.json().catch(() => ({}))) as { data?: unknown };
      if (response.ok && Array.isArray(json.data)) {
        initialCustomers = json.data as CustomerOption[];
      }
    } catch {
      // Non-fatal: the form will show an empty list and can retry client-side
    }
  }

  return (
    <div className="h-full overflow-hidden -mx-[10px] -my-[1px]">
      <OrderEntryForm
        mode="new"
        serverTenantId={tenantId ?? undefined}
        serverCustomers={initialCustomers}
      />
    </div>
  );
}
