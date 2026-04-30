'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus } from 'lucide-react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { createClient } from '@/lib/supabase/client';

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

type CustomerFormState = {
  customer_id: number | null;
  tenant_id: number;
  customer_parent_id: number | null;
  customer_name: string;
  customer_number: string;
  customer_type: string;
  legacy_id: string;
  invoice_copy_count: string;
  is_standing_order: boolean;
  is_signature_required: boolean;
  is_active: boolean;
  is_label_required: boolean;
  is_invoice_required: boolean;
  is_cost_on_invoice: boolean;
  is_cost_on_bill_of_lading: boolean;
  is_returns_allowed: boolean;
};

type SetCustomerResult = {
  success?: boolean;
  customer_id?: number;
  message?: string;
};

type CustomerManagementPageProps = {
  tenants: TenantOption[];
  initialTenantId: number | null;
  initialCustomers: CustomerRow[];
  initialMessage?: string | null;
};

const CUSTOMER_TYPES = ['ACCOUNT', 'SITE', 'LOCATION'] as const;

/** Focus first text/select control in the visible tab panel (for post–customer-select navigation). */
function focusFirstEditableInActiveTabPanel() {
  requestAnimationFrame(() => {
    const panel = document.querySelector('[role="tabpanel"][data-state="active"]');
    if (!panel) return;
    const el = panel.querySelector<HTMLElement>(
      'input:not([disabled]):not([type="hidden"]), textarea:not([disabled]), button[role="combobox"]:not([disabled]), select:not([disabled])'
    );
    el?.focus();
  });
}

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

function emptyForm(tenantId: number): CustomerFormState {
  return {
    customer_id: null,
    tenant_id: tenantId,
    customer_parent_id: null,
    customer_name: '',
    customer_number: '',
    customer_type: 'ACCOUNT',
    legacy_id: '',
    invoice_copy_count: '1',
    is_standing_order: false,
    is_signature_required: false,
    is_active: true,
    is_label_required: false,
    is_invoice_required: false,
    is_cost_on_invoice: false,
    is_cost_on_bill_of_lading: false,
    is_returns_allowed: true,
  };
}

function toFormState(customer: CustomerRow): CustomerFormState {
  return {
    customer_id: customer.customer_id,
    tenant_id: customer.tenant_id,
    customer_parent_id: customer.customer_parent_id,
    customer_name: customer.customer_name,
    customer_number: customer.customer_number ?? '',
    customer_type: customer.customer_type,
    legacy_id: customer.legacy_id === null ? '' : String(customer.legacy_id),
    invoice_copy_count: String(customer.invoice_copy_count),
    is_standing_order: customer.is_standing_order,
    is_signature_required: customer.is_signature_required,
    is_active: customer.is_active,
    is_label_required: customer.is_label_required,
    is_invoice_required: customer.is_invoice_required,
    is_cost_on_invoice: customer.is_cost_on_invoice,
    is_cost_on_bill_of_lading: customer.is_cost_on_bill_of_lading,
    is_returns_allowed: customer.is_returns_allowed,
  };
}

function normalizeCustomerRows(rows: unknown[]): CustomerRow[] {
  return rows
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

export function CustomerManagementPage({
  tenants,
  initialTenantId,
  initialCustomers,
  initialMessage = null,
}: CustomerManagementPageProps) {
  const supabase = useMemo(() => createClient(), []);

  const [tenantId, setTenantId] = useState<number | null>(initialTenantId);
  const [customers, setCustomers] = useState<CustomerRow[]>(initialCustomers);
  const [selectedCustomerId, setSelectedCustomerId] = useState<number | null>(null);
  const [selectedOriginal, setSelectedOriginal] = useState<CustomerRow | null>(null);
  const [formState, setFormState] = useState<CustomerFormState>(() =>
    emptyForm(initialTenantId ?? tenants[0]?.tenant_id ?? 0)
  );
  const [isSaving, setIsSaving] = useState(false);
  const [isLoadingCustomers, setIsLoadingCustomers] = useState(false);
  const [statusMessage, setStatusMessage] = useState<string | null>(initialMessage);

  const fetchCustomers = useCallback(
    async (nextTenantId: number) => {
      setIsLoadingCustomers(true);
      setStatusMessage(null);

      const { data, error } = await supabase.rpc('fnd_get_customer_hier', {
        tenant_id: nextTenantId,
      });

      if (error) {
        setCustomers([]);
        setStatusMessage(error.message);
        setIsLoadingCustomers(false);
        return [] as CustomerRow[];
      }

      const normalized = normalizeCustomerRows(Array.isArray(data) ? data : []);
      setCustomers(normalized);
      setSelectedCustomerId(null);
      setSelectedOriginal(null);
      setFormState(emptyForm(nextTenantId));
      setIsLoadingCustomers(false);
      return normalized;
    },
    [supabase]
  );

  useEffect(() => {
    if (!tenantId) return;
    setFormState((prev) => ({ ...prev, tenant_id: tenantId }));
  }, [tenantId]);

  const handleTenantChange = async (value: string) => {
    const parsed = Number(value);
    if (!Number.isInteger(parsed)) return;
    setTenantId(parsed);
    await fetchCustomers(parsed);
  };

  const handleSelectCustomer = (customer: CustomerRow) => {
    setSelectedCustomerId(customer.customer_id);
    setSelectedOriginal(customer);
    setFormState(toFormState(customer));
    setStatusMessage(null);
  };

  const handleCreateClick = () => {
    if (!tenantId) return;
    setSelectedCustomerId(null);
    setSelectedOriginal(null);
    setFormState(emptyForm(tenantId));
    setStatusMessage('Creating a new customer.');
  };

  const toggleField = (field: keyof CustomerFormState, checked: boolean) => {
    setFormState((prev) => ({ ...prev, [field]: checked }));
  };

  const updateField = (field: keyof CustomerFormState, value: string | number | null) => {
    setFormState((prev) => ({ ...prev, [field]: value }));
  };

  const handleSave = async () => {
    if (!tenantId) {
      setStatusMessage('Select a tenant first.');
      return;
    }

    if (!formState.customer_name.trim()) {
      setStatusMessage('Customer name is required.');
      return;
    }

    if (!formState.customer_type.trim()) {
      setStatusMessage('Customer type is required.');
      return;
    }

    const isCreate = selectedCustomerId === null;
    const payload: Record<string, unknown> = {
      customer_name: formState.customer_name.trim(),
      customer_number: formState.customer_number.trim() || null,
      customer_type: formState.customer_type.trim(),
      customer_parent_id: formState.customer_parent_id,
      legacy_id: formState.legacy_id.trim() ? Number(formState.legacy_id) : null,
      invoice_copy_count: Number(formState.invoice_copy_count || 1),
      is_standing_order: formState.is_standing_order,
      is_signature_required: formState.is_signature_required,
      is_active: formState.is_active,
      is_label_required: formState.is_label_required,
      is_invoice_required: formState.is_invoice_required,
      is_cost_on_invoice: formState.is_cost_on_invoice,
      is_cost_on_bill_of_lading: formState.is_cost_on_bill_of_lading,
      is_returns_allowed: formState.is_returns_allowed,
    };

    const updatePayload = isCreate
      ? payload
      : Object.fromEntries(
          Object.entries(payload).filter(([key, value]) => {
            if (!selectedOriginal) return true;
            const oldValue = (selectedOriginal as unknown as Record<string, unknown>)[key];
            return oldValue !== value;
          })
        );

    setIsSaving(true);
    setStatusMessage(null);

    const { data, error } = await supabase.rpc('set_customer', {
      p_tenant_id: tenantId,
      p_customer_id: selectedCustomerId,
      p_action: isCreate ? 'create' : 'update',
      p_payload: updatePayload,
    });

    if (error) {
      setStatusMessage(error.message);
      setIsSaving(false);
      return;
    }

    const result = (data ?? {}) as SetCustomerResult;
    const nextSelectedId = typeof result.customer_id === 'number' ? result.customer_id : null;

    const refreshedCustomers = await fetchCustomers(tenantId);

    if (nextSelectedId !== null) {
      const selected = refreshedCustomers.find((customer) => customer.customer_id === nextSelectedId);
      if (selected) {
        handleSelectCustomer(selected);
      }
    }

    setStatusMessage(result.message ?? 'Saved successfully.');
    setIsSaving(false);
  };

  const tenantSelectHidden = tenants.length <= 1;
  const titleNumber = formState.customer_number.trim();
  const titleName = formState.customer_name.trim();
  const formTitle =
    titleNumber || titleName
      ? `${titleNumber || 'New'} - ${titleName || 'Customer'}`
      : 'Customer Form';
  const selectedCustomerLabel = titleNumber || titleName ? formTitle : 'No customer selected';

  return (
    <div className="space-y-6">
      <div className={`grid gap-6 ${tenantSelectHidden ? 'lg:grid-cols-1' : 'lg:grid-cols-[300px_1fr]'}`}>
        {!tenantSelectHidden ? (
          <Card className="border-border/60 lg:h-[calc(100vh-12rem)]">
            <CardContent className="flex h-full flex-col gap-[6px] p-4">
              <div className="space-y-1.5">
                <Label htmlFor="tenant">Tenant</Label>
                <Select value={tenantId === null ? '' : String(tenantId)} onValueChange={handleTenantChange}>
                  <SelectTrigger id="tenant">
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

        <div className="flex min-h-0 flex-1 flex-col gap-4">
          <div className="grid grid-cols-3 gap-3 items-start">
            <div className="col-span-2 flex min-h-0 flex-col gap-1.5">
              <Label htmlFor="customer-combobox">Search Customer</Label>
              <EntityComboBox<CustomerRow>
                alwaysOpen
                collapseOnSelect
                clearSearchOnFocus
                triggerId="customer-combobox"
                items={customers}
                value={selectedCustomerId}
                onChange={(customer) => {
                  if (customer) {
                    handleSelectCustomer(customer);
                  }
                }}
                onAfterSelect={() => {
                  focusFirstEditableInActiveTabPanel();
                }}
                getId={(c) => c.customer_id}
                getLabel={(c) => `${c.customer_number ?? ''} - ${c.customer_name}`}
                getSearchText={(c) =>
                  `${c.customer_number ?? ''} ${c.customer_name}`.trim()
                }
                getParentId={(c) => c.customer_parent_id}
                getSortKey={(c) => c.sort_path}
                placeholder="Search number or name"
                disabled={!tenantId}
                loading={isLoadingCustomers}
                emptyText={tenantId ? 'No customers found.' : 'Select a tenant first.'}
                className="w-full"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-6">
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={handleCreateClick}
                  disabled={!tenantId}
                >
                  <Plus className="mr-1 h-3.5 w-3.5" />
                  Customer
                </Button>
                <Button type="button" onClick={handleSave} size="sm" disabled={isSaving || !tenantId}>
                  {isSaving ? 'Saving...' : 'Save'}
                </Button>
              </div>
            </div>
          </div>

          <Tabs defaultValue="profile" className="space-y-0">
            <TabsList className="relative z-0 h-auto w-fit justify-start gap-0.5 rounded-none bg-transparent p-0">
              <TabsTrigger
                value="profile"
                className="relative z-0 -mb-px rounded-b-none rounded-t-lg border border-muted bg-muted/70 px-4 py-1.5 data-[state=active]:z-10 data-[state=active]:translate-y-[1px] data-[state=active]:border-border/60 data-[state=active]:border-b-transparent data-[state=active]:bg-card"
              >
                Profile
              </TabsTrigger>
              <TabsTrigger
                value="contacts"
                className="relative z-0 -mb-px rounded-b-none rounded-t-lg border border-muted bg-muted/70 px-4 py-1.5 data-[state=active]:z-10 data-[state=active]:translate-y-[1px] data-[state=active]:border-border/60 data-[state=active]:border-b-transparent data-[state=active]:bg-card"
              >
                Contacts
              </TabsTrigger>
              <TabsTrigger
                value="pricing"
                className="relative z-0 -mb-px rounded-b-none rounded-t-lg border border-muted bg-muted/70 px-4 py-1.5 data-[state=active]:z-10 data-[state=active]:translate-y-[1px] data-[state=active]:border-border/60 data-[state=active]:border-b-transparent data-[state=active]:bg-card"
              >
                Pricing
              </TabsTrigger>
              <TabsTrigger
                value="settings"
                className="relative z-0 -mb-px rounded-b-none rounded-t-lg border border-muted bg-muted/70 px-4 py-1.5 data-[state=active]:z-10 data-[state=active]:translate-y-[1px] data-[state=active]:border-border/60 data-[state=active]:border-b-transparent data-[state=active]:bg-card"
              >
                Settings
              </TabsTrigger>
            </TabsList>

            <Card className="rounded-b-lg border border-border/60 border-t-0">
              <CardContent className="pt-4">
                <h2 className="text-base font-semibold tracking-tight">{formTitle}</h2>
                <TabsContent value="profile" className="space-y-6">
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-1.5">
                    <Label htmlFor="customer_number">Customer Number</Label>
                    <Input
                      id="customer_number"
                      value={formState.customer_number}
                      onChange={(event) => updateField('customer_number', event.target.value)}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="customer_name">Customer Name</Label>
                    <Input
                      id="customer_name"
                      value={formState.customer_name}
                      onChange={(event) => updateField('customer_name', event.target.value)}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="customer_type">Customer Type</Label>
                    <Select
                      value={formState.customer_type}
                      onValueChange={(value) => updateField('customer_type', value)}
                    >
                      <SelectTrigger id="customer_type">
                        <SelectValue placeholder="Select type" />
                      </SelectTrigger>
                      <SelectContent>
                        {CUSTOMER_TYPES.map((type) => (
                          <SelectItem key={type} value={type}>
                            {type}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="parent_id">Parent Customer ID</Label>
                    <Input
                      id="parent_id"
                      type="number"
                      value={formState.customer_parent_id ?? ''}
                      onChange={(event) =>
                        updateField(
                          'customer_parent_id',
                          event.target.value === '' ? null : Number(event.target.value)
                        )
                      }
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="legacy_id">Legacy ID</Label>
                    <Input
                      id="legacy_id"
                      type="number"
                      value={formState.legacy_id}
                      onChange={(event) => updateField('legacy_id', event.target.value)}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="invoice_copy_count">Invoice Copy Count</Label>
                    <Input
                      id="invoice_copy_count"
                      type="number"
                      min={1}
                      value={formState.invoice_copy_count}
                      onChange={(event) => updateField('invoice_copy_count', event.target.value)}
                    />
                  </div>
                </div>

                <div className="h-2" />

                <div className="grid gap-3 sm:grid-cols-2">
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_standing_order}
                      onCheckedChange={(checked) => toggleField('is_standing_order', checked === true)}
                    />
                    Standing Order
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_signature_required}
                      onCheckedChange={(checked) => toggleField('is_signature_required', checked === true)}
                    />
                    Signature Required
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_active}
                      onCheckedChange={(checked) => toggleField('is_active', checked === true)}
                    />
                    Active
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_label_required}
                      onCheckedChange={(checked) => toggleField('is_label_required', checked === true)}
                    />
                    Label Required
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_invoice_required}
                      onCheckedChange={(checked) => toggleField('is_invoice_required', checked === true)}
                    />
                    Invoice Required
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_cost_on_invoice}
                      onCheckedChange={(checked) => toggleField('is_cost_on_invoice', checked === true)}
                    />
                    Cost On Invoice
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_cost_on_bill_of_lading}
                      onCheckedChange={(checked) => toggleField('is_cost_on_bill_of_lading', checked === true)}
                    />
                    Cost On Bill Of Lading
                  </label>
                  <label className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={formState.is_returns_allowed}
                      onCheckedChange={(checked) => toggleField('is_returns_allowed', checked === true)}
                    />
                    Returns Allowed
                  </label>
                </div>

                {statusMessage && <p className="text-xs text-muted-foreground">{statusMessage}</p>}
              </TabsContent>

                <TabsContent value="contacts">
                  <div className="rounded-md border border-dashed border-border p-4 text-sm text-muted-foreground">
                    Contacts grid will be added here for <span className="font-medium">{selectedCustomerLabel}</span>.
                  </div>
                </TabsContent>

                <TabsContent value="pricing">
                  <div className="rounded-md border border-dashed border-border p-4 text-sm text-muted-foreground">
                    Pricing configuration will be added here for <span className="font-medium">{selectedCustomerLabel}</span>.
                  </div>
                </TabsContent>

                <TabsContent value="settings">
                  <div className="rounded-md border border-dashed border-border p-4 text-sm text-muted-foreground">
                    Customer settings will be added here for <span className="font-medium">{selectedCustomerLabel}</span>.
                  </div>
                </TabsContent>
              </CardContent>
            </Card>
          </Tabs>
        </div>
      </div>
    </div>
  );
}

