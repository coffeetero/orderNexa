'use client';

import { useMemo } from 'react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Copy, Search } from 'lucide-react';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { cn } from '@/lib/utils';
import type { OrderEntryDraft, ProductionCode } from '@/lib/types';

/** Slim customer shape used for the customer combobox. */
export interface CustomerOption {
  customer_id: number;
  customer_parent_id: number | null;
  top_customer_id?: number | null;
  customer_name: string;
  customer_number: string | null;
  customer_type?: string | null;
  level?: number;
  sort_path: string;
}

export interface DepartmentEventOption {
  id: string;
  order_id: number | null;
  order_number: string | null;
  department_event: string;
  total_quantity: number;
  amount: number;
  is_new: boolean;
}

interface OrderHeaderRowProps {
  draft: OrderEntryDraft;
  customers: CustomerOption[];
  isLoadingCustomers: boolean;
  /** External ref for the customer search <input> (used by useOrderFocus, alwaysOpen mode). */
  customerInputRef: React.RefObject<HTMLInputElement>;
  departmentEventInputRef: React.RefObject<HTMLInputElement>;
  departmentEventOptions: DepartmentEventOption[];
  selectedDepartmentEventId: string | null;
  onCustomerChange: (customer: CustomerOption | null) => void;
  /** Optional — e.g. focus next control after pick (order entry defers to items-loaded focus). */
  onCustomerAfterSelect?: () => void;
  onSearchExistingOrders: () => void;
  onDepartmentEventInputChange: (value: string) => void;
  onDepartmentEventSelect: (option: DepartmentEventOption | null) => void;
  onDepartmentEventCommit: (value: string) => void;
  onProductionDateChange: (value: string) => void;
  onProductionCodeChange: (value: ProductionCode) => void;
  onFieldChange: <K extends keyof OrderEntryDraft>(field: K, value: OrderEntryDraft[K]) => void;
}

function addDays(dateValue: string, days: number): string {
  const [year, month, day] = dateValue.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  date.setDate(date.getDate() + days);
  const nextYear = date.getFullYear();
  const nextMonth = String(date.getMonth() + 1).padStart(2, '0');
  const nextDay = String(date.getDate()).padStart(2, '0');
  return `${nextYear}-${nextMonth}-${nextDay}`;
}

export function OrderHeaderRow({
  draft,
  customers,
  isLoadingCustomers,
  customerInputRef,
  departmentEventInputRef,
  departmentEventOptions,
  selectedDepartmentEventId,
  onCustomerChange,
  onCustomerAfterSelect,
  onSearchExistingOrders,
  onDepartmentEventInputChange,
  onDepartmentEventSelect,
  onDepartmentEventCommit,
  onProductionDateChange,
  onProductionCodeChange,
  onFieldChange,
}: OrderHeaderRowProps) {
  const maxProductionDate = addDays(draft.order_date || draft.production_date, 7);

  const customerById = useMemo(() => {
    return new Map(customers.map((customer) => [customer.customer_id, customer]));
  }, [customers]);

  const getCustomerLabel = (customer: CustomerOption) =>
    customer.customer_number
      ? `${customer.customer_number} - ${customer.customer_name}`
      : customer.customer_name;

  const getCustomerInputLabel = (customer: CustomerOption) => {
    if (customer.customer_type?.trim().toUpperCase() === 'LOCATION') {
      const parent = customer.customer_parent_id
        ? customerById.get(customer.customer_parent_id)
        : undefined;
      return parent ? getCustomerLabel(parent) : getCustomerLabel(customer);
    }
    return getCustomerLabel(customer);
  };

  const formatMoney = (amount: number) =>
    new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    }).format(amount);

  const getDepartmentEventLabel = (option: DepartmentEventOption) => {
    if (option.is_new) return option.department_event;
    const orderNo = option.order_number ?? '';
    return `${orderNo} ${option.department_event} Qty ${option.total_quantity} ${formatMoney(option.amount)}`.trim();
  };

  return (
    <div className="border-b border-border/60 bg-card px-3 py-2">
      {/* Single row: Customer + dates + Order No. (+ optional toolbar) */}
        <div className="flex flex-wrap items-end gap-2">
        {/* Customer */}
        <div className="flex flex-col gap-1 w-[346px] min-w-[346px] max-w-[346px] shrink-0">
          <Label htmlFor="customer-select" className="text-xs font-semibold text-muted-foreground tracking-wide">
            Customer
          </Label>
          <EntityComboBox<CustomerOption>
            items={customers}
            value={draft.customer_id}
            onChange={onCustomerChange}
            onAfterSelect={onCustomerAfterSelect}
            getId={(c) => c.customer_id}
            getLabel={getCustomerLabel}
            getInputLabel={getCustomerInputLabel}
            getSearchText={(c) =>
              `${c.customer_number ?? ''} ${c.customer_name}`
            }
            getParentId={(c) => c.customer_parent_id}
            getSortKey={(c) => c.sort_path}
            placeholder="Search number or name…"
            disabled={isLoadingCustomers}
            loading={isLoadingCustomers}
            emptyText="No customers found."
            clearable
            alwaysOpen
            collapseOnSelect
            clearSearchOnFocus
            inputRef={customerInputRef}
            triggerId="customer-select"
            contextParentsSelectable={false}
          />
        </div>

        {/* Department/Event */}
        <div className="flex flex-col gap-1 flex-1 min-w-[220px]">
          <Label htmlFor="department-event" className="text-xs font-semibold text-muted-foreground tracking-wide">
            Department/Event
          </Label>
          <EntityComboBox<DepartmentEventOption>
            items={departmentEventOptions}
            value={selectedDepartmentEventId}
            inputValue={draft.department_event}
            onInputValueChange={onDepartmentEventInputChange}
            onInputCommit={onDepartmentEventCommit}
            onChange={onDepartmentEventSelect}
            getId={(option) => option.id}
            getLabel={getDepartmentEventLabel}
            getInputLabel={(option) => option.department_event}
            getSearchText={(option) =>
              `${option.order_number ?? ''} ${option.department_event} ${option.total_quantity} ${option.amount}`
            }
            getParentId={() => null}
            getSortKey={(option) => (option.is_new ? '000000' : `100000-${option.department_event}-${option.order_id ?? 0}`)}
            placeholder="Department/Event"
            disabled={!draft.customer_id}
            emptyText={draft.customer_id ? 'No existing Department/Event orders.' : 'Select a customer first.'}
            clearable
            alwaysOpen
            collapseOnSelect
            clearSearchOnFocus={false}
            initialListCollapsed={departmentEventOptions.length === 0}
            inputRef={departmentEventInputRef}
            triggerId="department-event"
          />
        </div>

        {/* Production Date */}
        <div className="flex flex-col gap-1 w-36 shrink-0">
          <Label htmlFor="production-date" className="text-xs font-semibold text-muted-foreground tracking-wide">
            Production Date
          </Label>
          <input
            id="production-date"
            type="date"
            className={cn(
              'h-9 w-full rounded-md border border-input bg-background px-2 text-sm text-foreground',
              'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
            )}
            value={draft.production_date}
            max={maxProductionDate}
            onChange={(e) => onProductionDateChange(e.target.value)}
            onFocus={(e) => e.target.select()}
          />
        </div>

        {/* Production Time */}
        <div className="flex flex-col gap-1 w-28 shrink-0">
          <Label className="text-xs font-semibold text-muted-foreground tracking-wide">
            Production Time
          </Label>
          <Select
            value={draft.production_code}
            onValueChange={(v) => onProductionCodeChange(v as ProductionCode)}
          >
            <SelectTrigger className="h-9 text-sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="AM">AM</SelectItem>
              <SelectItem value="PM">PM</SelectItem>
              <SelectItem value="SPECIAL">Special</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <Button
          type="button"
          variant="outline"
          size="icon"
          className="mb-0 h-9 w-9 shrink-0"
          onClick={onSearchExistingOrders}
          aria-label="Search existing orders"
          title="Search existing orders"
        >
          <Search className="h-4 w-4" />
        </Button>

        <Button
          type="button"
          variant="outline"
          size="icon"
          className="mb-0 h-9 w-9 shrink-0"
          aria-label="Copy order"
          title="Copy order"
        >
          <Copy className="h-4 w-4" />
        </Button>

        {/* Order Number */}
        <div className="flex flex-col gap-1 w-[173px] min-w-0 shrink-0">
          <Label htmlFor="order-number-display" className="text-center text-xs font-semibold text-muted-foreground tracking-wide">
            Order Number
          </Label>
          <div
            id="order-number-display"
            className={cn(
              'flex h-9 w-full items-center justify-center rounded-md border border-input bg-muted/30 px-3 text-center text-sm text-foreground',
              !draft.order_number && 'text-muted-foreground',
            )}
            aria-label="Order number"
          >
            <span className="truncate">{draft.order_number || 'New Order'}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
