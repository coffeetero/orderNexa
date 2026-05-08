'use client';

import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Label } from '@/components/ui/label';
import { Button } from '@/components/ui/button';
import { Search } from 'lucide-react';
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

interface OrderHeaderRowProps {
  draft: OrderEntryDraft;
  customers: CustomerOption[];
  isLoadingCustomers: boolean;
  /** External ref for the customer search <input> (used by useOrderFocus, alwaysOpen mode). */
  customerInputRef: React.RefObject<HTMLInputElement>;
  onCustomerChange: (customer: CustomerOption | null) => void;
  /** Optional — e.g. focus next control after pick (order entry defers to items-loaded focus). */
  onCustomerAfterSelect?: () => void;
  onSearchExistingOrders: () => void;
  onProductionDateChange: (value: string) => void;
  onFieldChange: <K extends keyof OrderEntryDraft>(field: K, value: OrderEntryDraft[K]) => void;
}

export function OrderHeaderRow({
  draft,
  customers,
  isLoadingCustomers,
  customerInputRef,
  onCustomerChange,
  onCustomerAfterSelect,
  onSearchExistingOrders,
  onProductionDateChange,
  onFieldChange,
}: OrderHeaderRowProps) {
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
            getLabel={(c) =>
              c.customer_number
                ? `${c.customer_number} — ${c.customer_name}`
                : c.customer_name
            }
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
            contentClassName="[&_[cmdk-group]]:!p-0 [&_[cmdk-group-items]]:!space-y-0 [&_[cmdk-item]]:!h-[20px] [&_[cmdk-item]]:!min-h-0 [&_[cmdk-item]]:!py-0 [&_[cmdk-item]]:!my-0 [&_[cmdk-item]]:!text-xs [&_[cmdk-item]]:!leading-none [&_[cmdk-item]_span]:!leading-none [&_[cmdk-item]_svg]:!h-3 [&_[cmdk-item]_svg]:!w-3"
            contextParentsSelectable={false}
          />
        </div>

        {/* Location/Event */}
        <div className="flex flex-col gap-1 flex-1 min-w-[220px]">
          <Label htmlFor="location-event" className="text-xs font-semibold text-muted-foreground tracking-wide">
            Location/Event
          </Label>
          <input
            id="location-event"
            type="text"
            className={cn(
              'h-9 w-full rounded-md border border-input bg-background px-2 text-sm text-foreground',
              'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
            )}
            value={draft.location_event}
            onChange={(e) => onFieldChange('location_event', e.target.value)}
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
            onValueChange={(v) => onFieldChange('production_code', v as ProductionCode)}
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

        {/* Order Number */}
        <div className="flex flex-col gap-1 w-[173px] min-w-0 shrink-0">
          <Label htmlFor="order-number-display" className="text-center text-xs font-semibold text-muted-foreground tracking-wide">
            Order Number
          </Label>
          <div
            id="order-number-display"
            className={cn(
              'flex h-9 w-full items-center rounded-md border border-input bg-muted/30 px-3 text-sm text-foreground',
              !draft.order_number && 'text-muted-foreground',
            )}
            aria-label="Order number"
          >
            <span className="truncate">{draft.order_number || 'No order'}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
