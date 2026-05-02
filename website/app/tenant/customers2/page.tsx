import { headers } from 'next/headers';
import { Customers2Page } from '@/components/features/tenant/Customers2Page';
import { createClient } from '@/lib/supabase/server';

type TenantOption = {
  tenant_id: number;
  tenant_name: string;
};

type CustomerHierarchyRow = {
  tenant_id: number;
  customer_id: number;
  customer_parent_id: number | null;
  customer_number: string | null;
  customer_name: string;
  level: number;
  sort_path: string;
};

function toNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function normalizeTenants(data: unknown): TenantOption[] {
  if (!Array.isArray(data)) return [];
  return data
    .map((tenant) => {
      const candidate = tenant as Partial<TenantOption>;
      const tenantId = toNumber(candidate.tenant_id);
      if (tenantId === null) return null;
      return {
        tenant_id: tenantId,
        tenant_name: candidate.tenant_name ?? `Tenant ${tenantId}`,
      };
    })
    .filter((tenant): tenant is TenantOption => tenant !== null);
}

function normalizeCustomerHierarchy(data: unknown): CustomerHierarchyRow[] {
  if (!Array.isArray(data)) return [];
  return data
    .map((row) => {
      const candidate = row as Partial<CustomerHierarchyRow>;
      const customerId = toNumber(candidate.customer_id);
      const tenantId = toNumber(candidate.tenant_id);
      if (customerId === null || tenantId === null) return null;
      return {
        tenant_id: tenantId,
        customer_id: customerId,
        customer_parent_id: toNumber(candidate.customer_parent_id),
        customer_number: candidate.customer_number ?? null,
        customer_name: candidate.customer_name ?? '',
        level: toNumber(candidate.level) ?? 0,
        sort_path: candidate.sort_path ?? '',
      };
    })
    .filter((row): row is CustomerHierarchyRow => row !== null)
    .sort((a, b) => a.sort_path.localeCompare(b.sort_path));
}

export default async function Customers2Route() {
  const supabase = createClient();
  let initialMessage: string | null = null;

  const { data: tenantData, error: tenantError } = await supabase.rpc('fnd_get_tenants');
  if (tenantError) {
    initialMessage = tenantError.message;
  }

  const tenants = normalizeTenants(tenantData);
  const initialTenantId = tenants.length === 1 ? tenants[0].tenant_id : null;

  let initialCustomers: CustomerHierarchyRow[] = [];
  if (initialTenantId !== null) {
    const h = headers();
    const host = h.get('host');
    const proto = h.get('x-forwarded-proto') ?? 'http';
    const cookie = h.get('cookie') ?? '';
    const apiUrl = `${proto}://${host}/api/customers?tenant_id=${initialTenantId}&hierarchy=true&active=true`;

    try {
      const response = await fetch(apiUrl, {
        headers: { cookie },
        cache: 'no-store',
      });

      const json = (await response.json().catch(() => ({}))) as {
        data?: unknown;
        error?: string;
      };

      if (!response.ok) {
        initialMessage = json.error ?? response.statusText;
      } else {
        initialCustomers = normalizeCustomerHierarchy(json.data);
      }
    } catch (error) {
      initialMessage = error instanceof Error ? error.message : 'Customer fetch failed';
    }
  }

  return (
    <Customers2Page
      tenants={tenants}
      initialTenantId={initialTenantId}
      initialCustomers={initialCustomers}
      initialMessage={initialMessage}
    />
  );
}
