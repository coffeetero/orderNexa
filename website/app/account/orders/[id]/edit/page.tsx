import { headers } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import { OrderEntryForm } from '@/components/features/tenant/order-entry/OrderEntryForm';
import type { CustomerOption } from '@/components/features/tenant/order-entry/OrderHeaderRow';

export const metadata = {
  title: 'Edit Order — Order Entry',
};

interface EditOrderPageProps {
  params: { id: string };
}

export default async function EditOrderPage({ params }: EditOrderPageProps) {
  const orderId = parseInt(params.id, 10);

  if (isNaN(orderId)) {
    return (
      <div className="p-6 text-sm text-destructive">
        Invalid order ID.
      </div>
    );
  }

  const supabase = createClient();

  // Resolve tenant via RPC
  const { data: tenantData } = await supabase.rpc('fnd_get_tenants');
  const tenants = Array.isArray(tenantData) ? tenantData : [];
  const tenantId: number | null = tenants.length > 0 ? tenants[0].tenant_id : null;

  // Pre-load customers server-side
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
      // Non-fatal: the form will show an empty list
    }
  }

  return (
    <div className="h-full overflow-hidden -mx-[10px] -my-[1px]">
      <OrderEntryForm
        mode="edit"
        orderId={orderId}
        serverTenantId={tenantId ?? undefined}
        serverCustomers={initialCustomers}
      />
    </div>
  );
}
