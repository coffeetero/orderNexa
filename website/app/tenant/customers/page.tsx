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
    if (value.toLowerCase() === 'true') return true;
    if (value.toLowerCase() === 'false') return false;
  }
  return fallback;
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

function normalizeCustomers(data: unknown): CustomerRow[] {
  if (!Array.isArray(data)) return [];
  return data
    .map((row) => {
      const candidate = row as Partial<CustomerRow>;
      const customerId = toNumber(candidate.customer_id);
      const tenantId = toNumber(candidate.tenant_id);
      if (customerId === null || tenantId === null) {
        return null;
      }

      return {
        customer_id: customerId,
        tenant_id: tenantId,
        customer_parent_id: toNumber(candidate.customer_parent_id),
        customer_name: candidate.customer_name ?? '',
        customer_number: candidate.customer_number ?? null,
        customer_type: candidate.customer_type ?? 'ACCOUNT',
        legacy_id: toNumber(candidate.legacy_id),
        level: toNumber(candidate.level) ?? 0,
        sort_path: candidate.sort_path ?? '',
        invoice_copy_count: toNumber(candidate.invoice_copy_count) ?? 1,
        is_standing_order: toBoolean(candidate.is_standing_order, false),
        is_signature_required: toBoolean(candidate.is_signature_required, false),
        is_active: toBoolean(candidate.is_active, true),
        is_label_required: toBoolean(candidate.is_label_required, false),
        is_invoice_required: toBoolean(candidate.is_invoice_required, false),
        is_cost_on_invoice: toBoolean(candidate.is_cost_on_invoice, false),
        is_cost_on_bill_of_lading: toBoolean(candidate.is_cost_on_bill_of_lading, false),
        is_returns_allowed: toBoolean(candidate.is_returns_allowed, true),
      };
    })
    .filter((row): row is CustomerRow => row !== null)
    .sort((a, b) => a.sort_path.localeCompare(b.sort_path));
}

export default async function ManageCustomersPage() {
  const supabase = createClient();

  let initialMessage: string | null = null;
  const { data: tenantData, error: tenantError } = await supabase.rpc('get_tenants');
  if (tenantError) {
    initialMessage = tenantError.message;
  }
  const tenants = normalizeTenants(tenantData);
  const initialTenantId = tenants.length === 1 ? tenants[0].tenant_id : null;

  let initialCustomers: CustomerRow[] = [];
  if (initialTenantId !== null) {
    const { data: customerData, error: customerError } = await supabase.rpc('fnd_get_customer_hier', {
      tenant_id: initialTenantId,
    });
    if (customerError) {
      initialMessage = customerError.message;
    }
    initialCustomers = normalizeCustomers(customerData);
  }

  return (
    <CustomerManagementPage
      tenants={tenants}
      initialTenantId={initialTenantId}
      initialCustomers={initialCustomers}
      initialMessage={initialMessage}
    />
  );
}
