'use client';

import { useCallback, useMemo, useState } from 'react';
import { Building2, CircleAlert, Loader2, UserRound } from 'lucide-react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { createClient } from '@/lib/supabase/client';

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

type CustomerDetails = {
  customer_id: number;
  tenant_id: number;
  customer_parent_id: number | null;
  customer_number: string | null;
  customer_name: string;
  customer_type: string;
  is_active: boolean;
  is_standing_order: boolean;
  is_returns_allowed: boolean;
};

type Customers2PageProps = {
  tenants: TenantOption[];
  initialTenantId: number | null;
  initialCustomers: CustomerHierarchyRow[];
  initialMessage?: string | null;
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

function normalizeCustomerHierarchy(data: unknown): CustomerHierarchyRow[] {
  if (!Array.isArray(data)) return [];
  return data
    .map((row) => {
      const candidate = row as Partial<CustomerHierarchyRow>;
      const customerId = toNumber(candidate.customer_id);
      const tenantId = toNumber(candidate.tenant_id);
      if (customerId === null || tenantId === null) return null;
      return {
        customer_id: customerId,
        tenant_id: tenantId,
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

function normalizeCustomerDetails(data: unknown, fallback: CustomerHierarchyRow): CustomerDetails {
  const obj = (data && typeof data === 'object' && !Array.isArray(data)
    ? (data as Record<string, unknown>)
    : {}) as Record<string, unknown>;

  return {
    customer_id: toNumber(obj.customer_id) ?? fallback.customer_id,
    tenant_id: toNumber(obj.tenant_id) ?? fallback.tenant_id,
    customer_parent_id: toNumber(obj.customer_parent_id) ?? fallback.customer_parent_id,
    customer_number:
      obj.customer_number === null || obj.customer_number === undefined
        ? fallback.customer_number
        : String(obj.customer_number),
    customer_name: String(obj.customer_name ?? fallback.customer_name),
    customer_type: String(obj.customer_type ?? 'ACCOUNT'),
    is_active: toBoolean(obj.is_active, true),
    is_standing_order: toBoolean(obj.is_standing_order, false),
    is_returns_allowed: toBoolean(obj.is_returns_allowed, true),
  };
}

export function Customers2Page({
  tenants,
  initialTenantId,
  initialCustomers,
  initialMessage = null,
}: Customers2PageProps) {
  const supabase = useMemo(() => createClient(), []);
  const [tenantId, setTenantId] = useState<number | null>(initialTenantId);
  const [customers, setCustomers] = useState<CustomerHierarchyRow[]>(initialCustomers);
  const [selectedCustomerId, setSelectedCustomerId] = useState<number | null>(null);
  const [selectedCustomer, setSelectedCustomer] = useState<CustomerDetails | null>(null);
  const [isLoadingCustomers, setIsLoadingCustomers] = useState(false);
  const [isLoadingCustomer, setIsLoadingCustomer] = useState(false);
  const [statusMessage, setStatusMessage] = useState<string | null>(initialMessage);

  const isTenantSelectHidden = tenants.length <= 1;

  const fetchCustomers = useCallback(
    async (nextTenantId: number) => {
      setIsLoadingCustomers(true);
      setStatusMessage(null);
      setSelectedCustomerId(null);
      setSelectedCustomer(null);

      const { data, error } = await supabase.rpc('fnd_get_customers_hier', {
        tenant_id: nextTenantId,
      });

      if (error) {
        setCustomers([]);
        setStatusMessage(error.message);
        setIsLoadingCustomers(false);
        return;
      }

      setCustomers(normalizeCustomerHierarchy(data));
      setIsLoadingCustomers(false);
    },
    [supabase]
  );

  const loadCustomer = useCallback(
    async (row: CustomerHierarchyRow) => {
      setSelectedCustomerId(row.customer_id);
      setIsLoadingCustomer(true);
      setStatusMessage(null);

      const { data, error } = await supabase.rpc('fnd_get_customers', {
        p_customer_id: row.customer_id,
      });

      if (error) {
        setSelectedCustomer(null);
        setStatusMessage(error.message);
        setIsLoadingCustomer(false);
        return;
      }

      setSelectedCustomer(normalizeCustomerDetails(data, row));
      setIsLoadingCustomer(false);
    },
    [supabase]
  );

  const handleTenantChange = useCallback(
    async (value: string) => {
      const parsed = Number(value);
      if (!Number.isInteger(parsed)) return;
      setTenantId(parsed);
      await fetchCustomers(parsed);
    },
    [fetchCustomers]
  );

  const selectedTitle = selectedCustomer
    ? `${selectedCustomer.customer_number ?? 'No#'} - ${selectedCustomer.customer_name}`
    : 'No customer selected';

  return (
    <div className="space-y-6">
      <div className={`grid gap-6 ${isTenantSelectHidden ? 'lg:grid-cols-1' : 'lg:grid-cols-[300px_1fr]'}`}>
        {!isTenantSelectHidden ? (
          <Card className="border-border/60 lg:h-[calc(100vh-12rem)]">
            <CardContent className="flex h-full flex-col gap-2 p-4">
              <div className="space-y-1.5">
                <Label htmlFor="customers2-tenant">Select Tenant</Label>
                <Select value={tenantId === null ? '' : String(tenantId)} onValueChange={handleTenantChange}>
                  <SelectTrigger id="customers2-tenant">
                    <SelectValue placeholder="Select tenant" />
                  </SelectTrigger>
                  <SelectContent>
                    {tenants.map((tenant) => (
                      <SelectItem key={tenant.tenant_id} value={String(tenant.tenant_id)}>
                        {tenant.tenant_name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </CardContent>
          </Card>
        ) : null}

        <div className="space-y-4">
          <Card className="border-border/60">
            <CardContent className="space-y-3 p-4">
              <div className="flex items-center justify-between gap-2">
                <div>
                  <p className="text-base font-semibold tracking-tight">Customer Lookup</p>
                  <p className="text-xs text-muted-foreground">
                    Keyboard first: type to filter, arrows to navigate, Enter to select.
                  </p>
                </div>
                {tenantId ? (
                  <Badge variant="outline" className="font-medium">
                    <Building2 className="mr-1 h-3.5 w-3.5" />
                    Tenant {tenantId}
                  </Badge>
                ) : null}
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="customers2-customer">Select Customer</Label>
                <EntityComboBox<CustomerHierarchyRow>
                  alwaysOpen
                  collapseOnSelect
                  clearSearchOnFocus
                  triggerId="customers2-customer"
                  items={customers}
                  value={selectedCustomerId}
                  onChange={(customer) => {
                    if (customer) {
                      void loadCustomer(customer);
                    } else {
                      setSelectedCustomerId(null);
                      setSelectedCustomer(null);
                      setStatusMessage(null);
                    }
                  }}
                  getId={(c) => c.customer_id}
                  getParentId={(c) => c.customer_parent_id}
                  getSortKey={(c) => c.sort_path}
                  getLabel={(c) => `${c.customer_number ?? ''} - ${c.customer_name}`}
                  getSearchText={(c) => `${c.customer_number ?? ''} ${c.customer_name}`.trim()}
                  placeholder="Search number or name"
                  disabled={!tenantId}
                  loading={isLoadingCustomers}
                  emptyText={tenantId ? 'No customers found.' : 'Select a tenant first.'}
                  className="w-full"
                />
              </div>
            </CardContent>
          </Card>

          <Card className="border-border/60">
            <CardContent className="space-y-3 p-4">
              <div>
                <p className="text-base font-semibold tracking-tight">Selected Customer</p>
                <p className="text-xs text-muted-foreground">{selectedTitle}</p>
              </div>

              {isLoadingCustomer ? (
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Loading customer details...
                </div>
              ) : selectedCustomer ? (
                <div className="grid gap-3 sm:grid-cols-2">
                  <div className="space-y-1">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Customer ID</p>
                    <p className="font-mono text-sm">{selectedCustomer.customer_id}</p>
                  </div>
                  <div className="space-y-1">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Type</p>
                    <p className="text-sm">{selectedCustomer.customer_type}</p>
                  </div>
                  <div className="space-y-1">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Active</p>
                    <p className="text-sm">{selectedCustomer.is_active ? 'Yes' : 'No'}</p>
                  </div>
                  <div className="space-y-1">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Standing Order</p>
                    <p className="text-sm">{selectedCustomer.is_standing_order ? 'Yes' : 'No'}</p>
                  </div>
                  <div className="space-y-1">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Returns Allowed</p>
                    <p className="text-sm">{selectedCustomer.is_returns_allowed ? 'Yes' : 'No'}</p>
                  </div>
                  <div className="space-y-1">
                    <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Parent Customer</p>
                    <p className="text-sm">{selectedCustomer.customer_parent_id ?? 'None'}</p>
                  </div>
                </div>
              ) : (
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <UserRound className="h-4 w-4" />
                  Choose a customer to view details.
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>

      {statusMessage ? (
        <div className="flex items-start gap-2 rounded-md border border-destructive/30 bg-destructive/5 px-3 py-2 text-sm text-destructive">
          <CircleAlert className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{statusMessage}</span>
        </div>
      ) : null}
    </div>
  );
}
