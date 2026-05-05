'use client';

import type { ReactNode } from 'react';
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
import type { OrderEntryDraft, ProductionCode } from '@/lib/types';

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
  /** Optional — e.g. focus next control after pick (order entry defers to items-loaded focus). */
  onCustomerAfterSelect?: () => void;
  onOrderRefChange?: (order: OrderRefOption | null) => void;
  onFieldChange: <K extends keyof OrderEntryDraft>(field: K, value: OrderEntryDraft[K]) => void;
  /** Placed to the right of the Order No. control (e.g. Retrieve). */
  orderRefToolbar?: ReactNode;
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
  orderRefToolbar,
}: OrderHeaderRowProps) {
  return (
    <div className="border-b border-border/60 bg-card px-3 py-2">
      {/* Single row: Customer + dates + Order No. (+ optional toolbar) */}
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
            onChange={(e) => onFieldChange('production_date', e.target.value)}
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

        {/* Order No. + toolbar (e.g. Retrieve) */}
        <div className="flex items-end gap-2 shrink-0">
          <div className="flex flex-col gap-1 w-36 min-w-0">
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
              getLabel={(o) =>
                o.order_id === 0
                  ? 'New Order'
                  : o.customer_name
                  ? `${o.order_number} — ${o.customer_name}`
                  : o.order_number
              }
              getSearchText={(o) => `${o.order_number} ${o.customer_name}`}
              getParentId={() => null}
              getSortKey={(o) => (o.order_id === 0 ? '\u0000' : o.order_number)}
              placeholder="Search orders…"
              emptyText="No orders found."
              clearable
              triggerId="order-ref"
              triggerClassName="h-9 text-sm font-normal"
            />
          </div>
          {orderRefToolbar != null && (
            <div className="flex flex-col gap-1 shrink-0 pb-px">
              <span
                className="text-[10px] font-semibold text-muted-foreground tracking-wide invisible pointer-events-none select-none"
                aria-hidden
              >
                &nbsp;
              </span>
              <div className="h-9 flex items-center">{orderRefToolbar}</div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
