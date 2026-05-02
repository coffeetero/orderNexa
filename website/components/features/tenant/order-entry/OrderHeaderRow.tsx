'use client';

import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { cn } from '@/lib/utils';
import type { DeliveryWindow, OrderEntryDraft } from '@/lib/types';

/** Slim customer shape used for the customer combobox. */
export interface CustomerOption {
  customer_id: number;
  customer_parent_id: number | null;
  customer_name: string;
  customer_number: string | null;
  sort_path: string;
}

/** Slim order option shape used for the Order No. combobox search — wired to real data later. */
export interface OrderRefOption {
  order_id: number;
  order_number: string;
  customer_name: string;
}

interface OrderHeaderRowProps {
  draft: OrderEntryDraft;
  customers: CustomerOption[];
  isLoadingCustomers: boolean;
  /** Items for the Order No. combobox — pass [] until the search-orders API is wired. */
  orderRefItems?: OrderRefOption[];
  /** External ref for the customer search <input> (used by useOrderFocus, alwaysOpen mode). */
  customerInputRef: React.RefObject<HTMLInputElement>;
  onCustomerChange: (customer: CustomerOption | null) => void;
  onCustomerAfterSelect: () => void;
  onOrderRefChange?: (order: OrderRefOption | null) => void;
  onFieldChange: <K extends keyof OrderEntryDraft>(field: K, value: OrderEntryDraft[K]) => void;
}

export function OrderHeaderRow({
  draft,
  customers,
  isLoadingCustomers,
  orderRefItems = [],
  customerInputRef,
  onCustomerChange,
  onCustomerAfterSelect,
  onOrderRefChange,
  onFieldChange,
}: OrderHeaderRowProps) {
  return (
    <div className="border-b border-border/60 bg-card px-3 py-2">
      {/* Single row: Customer + Dates + Invoice + Financial strip */}
      <div className="flex flex-wrap items-end gap-2">
        {/* Customer */}
        <div className="flex flex-col gap-1 flex-1 min-w-[200px]">
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
            contextParentsSelectable={false}
          />
        </div>

        {/* Production Date */}
        <div className="flex flex-col gap-1 w-36 shrink-0">
          <Label htmlFor="delivery-date" className="text-xs font-semibold text-muted-foreground tracking-wide">
            Production Date
          </Label>
          <input
            id="delivery-date"
            type="date"
            className={cn(
              'h-9 w-full rounded-md border border-input bg-background px-2 text-sm text-foreground',
              'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
            )}
            value={draft.delivery_date}
            onChange={(e) => onFieldChange('delivery_date', e.target.value)}
            onFocus={(e) => e.target.select()}
          />
        </div>

        {/* Production Time */}
        <div className="flex flex-col gap-1 w-28 shrink-0">
          <Label className="text-xs font-semibold text-muted-foreground tracking-wide">
            Production Time
          </Label>
          <Select
            value={draft.delivery_window}
            onValueChange={(v) => onFieldChange('delivery_window', v as DeliveryWindow)}
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

        {/* Invoice No */}
        <div className="flex flex-col gap-1 w-32 shrink-0">
          <Label htmlFor="invoice-no" className="text-xs font-semibold text-muted-foreground tracking-wide">
            Invoice No.
          </Label>
          <input
            id="invoice-no"
            type="text"
            className={cn(
              'h-9 w-full rounded-md border border-input bg-background px-2 text-sm text-foreground tabular-nums',
              'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
            )}
            value={draft.order_number}
            placeholder="e.g. 523310"
            onChange={(e) => onFieldChange('order_number', e.target.value)}
            onFocus={(e) => e.target.select()}
          />
        </div>

        {/* Order No. */}
        <div className="flex flex-col gap-1 w-36 shrink-0">
          <Label htmlFor="order-ref" className="text-xs font-semibold text-muted-foreground tracking-wide">
            Order No.
          </Label>
          <EntityComboBox<OrderRefOption>
            items={orderRefItems}
            value={draft.order_ref ? Number(draft.order_ref) || null : null}
            onChange={(order) => {
              onFieldChange('order_ref', order ? String(order.order_number) : '');
              onOrderRefChange?.(order);
            }}
            getId={(o) => o.order_id}
            getLabel={(o) => `${o.order_number} — ${o.customer_name}`}
            getSearchText={(o) => `${o.order_number} ${o.customer_name}`}
            getParentId={() => null}
            getSortKey={(o) => o.order_number}
            placeholder="Search orders…"
            emptyText="Type to search orders."
            clearable
            triggerId="order-ref"
            triggerClassName="h-9 text-sm font-normal"
          />
        </div>

        {/* Divider */}
        <div className="self-stretch w-px bg-border/60 mx-1" />

        {/* Credit (display-only) */}
        <div className="flex flex-col gap-0.5 shrink-0">
          <span className="text-[10px] font-semibold text-muted-foreground tracking-wide">
            Credit
          </span>
          <span
            className="h-9 flex items-center tabular-nums text-sm font-medium text-foreground px-1"
            tabIndex={-1}
          >
            ${draft.customer_credit.toFixed(2)}
          </span>
        </div>

        {/* Delivery $ */}
        <div className="flex flex-col gap-1 w-24 shrink-0">
          <label
            htmlFor="delivery-amount"
            className="text-[10px] font-semibold text-muted-foreground tracking-wide"
          >
            Dlvry $
          </label>
          <input
            id="delivery-amount"
            type="number"
            className={cn(
              'h-9 w-full rounded-md border border-input bg-background px-2 text-sm text-right tabular-nums',
              'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
              '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none',
              '[&::-webkit-inner-spin-button]:appearance-none',
            )}
            value={draft.delivery_amount === 0 ? '' : draft.delivery_amount}
            placeholder="0.00"
            min={0}
            step={0.01}
            onFocus={(e) => e.target.select()}
            onChange={(e) => {
              const v = parseFloat(e.target.value);
              onFieldChange('delivery_amount', isNaN(v) ? 0 : v);
            }}
          />
        </div>

        {/* Ttl Order (display-only, highlighted) */}
        <div className="flex flex-col gap-1 shrink-0">
          <span className="text-[10px] font-semibold text-muted-foreground tracking-wide">
            Ttl Order
          </span>
          <span
            className={cn(
              'h-9 flex items-center tabular-nums text-base font-bold px-2',
              'rounded bg-amber-50 dark:bg-amber-950/40',
              'border border-amber-200 dark:border-amber-800',
              'text-amber-800 dark:text-amber-300',
            )}
            tabIndex={-1}
            aria-label="Total Order"
          >
            ${(draft.total_amount + draft.delivery_amount).toFixed(2)}
          </span>
        </div>
      </div>
    </div>
  );
}
