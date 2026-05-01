import { CustomerManagementPage } from '@/components/features/tenant/CustomerManagementPage';
import { createClient } from '@/lib/supabase/server';

type TenantOption = {
  tenant_id: number;
  tenant_name: string;
};

type CustomerRow = {
  customer_id: number;
  tenant_id: number;
  customer_parent_id: number | null;
  customer_name: string;
  customer_number: string | null;
  customer_type: string;
  legacy_id: number | null;
  level: number;
  sort_path: string;
  invoice_copy_count: number;
  is_standing_order: boolean;
  is_signature_required: boolean;
  is_active: boolean;
  is_label_required: boolean;
  is_invoice_required: boolean;
  is_cost_on_invoice: boolean;
  is_cost_on_bill_of_lading: boolean;
  is_returns_allowed: boolean;
};

function toNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;

  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function toBoolean(value: unknown, fallback = false): boolean {
  if (typeof value === 'boolean') return value;

  if (typeof value === 'string') {
    const normalized = value.toLowerCase();
    if (normalized === 'true') return true;
    if (normalized === 'false') return false;
  }

  return fallback;
}

function normalizeTenants(data: unknown): TenantOption[] {
  if (!Array.isArray(data)) return [];

  return data
    .map((tenant) => {
      const row = tenant as Partial<TenantOption>;
      const tenantId = toNumber(row.tenant_id);

      if (tenantId === null) return null;

      return {
        tenant_id: tenantId,
        tenant_name: row.tenant_name ?? `Tenant ${tenantId}`,
      };
    })
    .filter((tenant): tenant is TenantOption => tenant !== null);
}

function normalizeCustomers(data: unknown): CustomerRow[] {
  if (!Array.isArray(data)) return [];

  return data
    .map((customer) => {
      const row = customer as Partial<CustomerRow>;

      const customerId = toNumber(row.customer_id);
      const tenantId = toNumber(row.tenant_id);

      if (customerId === null || tenantId === null) return null;

      return {
        customer_id: customerId,
        tenant_id: tenantId,
        customer_parent_id: toNumber(row.customer_parent_id),
        customer_name: row.customer_name ?? '',
        customer_number: row.customer_number ?? null,
        customer_type: row.customer_type ?? 'ACCOUNT',
        legacy_id: toNumber(row.legacy_id),
        level: toNumber(row.level) ?? 0,
        sort_path: row.sort_path ?? '',
        invoice_copy_count: toNumber(row.invoice_copy_count) ?? 1,
        is_standing_order: toBoolean(row.is_standing_order),
        is_signature_required: toBoolean(row.is_signature_required),
        is_active: toBoolean(row.is_active, true),
        is_label_required: toBoolean(row.is_label_required),
        is_invoice_required: toBoolean(row.is_invoice_required),
        is_cost_on_invoice: toBoolean(row.is_cost_on_invoice),
        is_cost_on_bill_of_lading: toBoolean(row.is_cost_on_bill_of_lading),
        is_returns_allowed: toBoolean(row.is_returns_allowed, true),
      };
    })
    .filter((customer): customer is CustomerRow => customer !== null)
    .sort((a, b) => {
      const sortCompare = a.sort_path.localeCompare(b.sort_path);
      if (sortCompare !== 0) return sortCompare;
      return a.customer_name.localeCompare(b.customer_name);
    });
}

function getSearchParam(
  searchParams: { [key: string]: string | string[] | undefined },
  key: string,
): string | undefined {
  const value = searchParams[key];
  return Array.isArray(value) ? value[0] : value;
}

export default async function ManageCustomersPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
  const supabase = createClient();

  const isDebug = getSearchParam(searchParams, 'debug') === 'true';
  const requestedTenantId = toNumber(getSearchParam(searchParams, 'tenantId'));

  let initialMessage: string | null = null;

  const { data: tenantData, error: tenantError } = await supabase.rpc('fnd_get_tenants');

  if (tenantError) {
    initialMessage = `Tenant RPC error: ${tenantError.message}`;
  }

  const tenants = normalizeTenants(tenantData);

  const initialTenantId =
    requestedTenantId ??
    (tenants.length > 0 ? tenants[0].tenant_id : null);

  let initialCustomers: CustomerRow[] = [];

  if (initialTenantId !== null) {
    const { data: customerData, error: customerError } = await supabase.rpc(
      'fnd_get_customers_hier',
      {
        p_tenant_id: initialTenantId,
      },
    );

    if (customerError) {
      initialMessage = `Customer hierarchy RPC error: ${customerError.message}`;
    } else {
      initialCustomers = normalizeCustomers(customerData);
    }
  }

  // if (isDebug) {
    console.debug('[tenant/customers/page.tsx] data before return', {
      tenantCount: tenants.length,
      tenants,
      requestedTenantId,
      initialTenantId,
      customerCount: initialCustomers.length,
      initialCustomersSample: initialCustomers.slice(0, 10),
      initialMessage,
    });
  // }

  return (
    <CustomerManagementPage
      tenants={tenants}
      initialTenantId={initialTenantId}
      initialCustomers={initialCustomers}
      initialMessage={initialMessage}
      isDebugActive={isDebug}
    />
  );
}