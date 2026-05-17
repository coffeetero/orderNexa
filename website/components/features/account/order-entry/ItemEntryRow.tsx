'use client';

import { useCallback, useRef, useState, type ReactNode } from 'react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';
import type { OrderEntryItem } from '@/lib/types';

/** Shared label row height so control inputs align on one baseline (h-9). */
const CONTROL_LABEL =
  'text-xs font-semibold text-muted-foreground tracking-wide leading-none h-4 shrink-0 flex items-end pb-px';

interface ItemEntryRowProps {
  items: OrderEntryItem[];
  isLoadingItems: boolean;
  disabled: boolean;
  /** External ref for the item search <input> (used by useOrderFocus). */
  itemInputRef: React.RefObject<HTMLInputElement>;
  /** External ref for the qty <input>. */
  qtyRef: React.RefObject<HTMLInputElement>;
  /** Called when Enter is pressed in the Qty field with a valid quantity. */
  onCommit: (item: OrderEntryItem, quantity: number) => void;
  /** Display-only current order number/reference. */
  orderNumber: string;
  /** Customer purchase order number for this order. */
  poNumber: string;
  onPoNumberChange: (value: string) => void;
  /** Header total (lines + delivery). */
  orderTotal: number;
  /** Placed to the right of Total Order (e.g. Sample, Clear). */
  entryToolbar?: ReactNode;
}

export function ItemEntryRow({
  items,
  isLoadingItems,
  disabled,
  itemInputRef,
  qtyRef,
  onCommit,
  orderNumber,
  poNumber,
  onPoNumberChange,
  orderTotal,
  entryToolbar,
}: ItemEntryRowProps) {
  const [selectedItem, setSelectedItem] = useState<OrderEntryItem | null>(null);
  const [qtyValue, setQtyValue] = useState<string>('');
  const lastItemRef = useRef<OrderEntryItem | null>(null);

  /** Reset the row so it's ready for the next item entry. */
  const resetRow = useCallback(() => {
    setSelectedItem(null);
    setQtyValue('');
    lastItemRef.current = null;
  }, []);

  const handleItemAfterSelect = useCallback(
    (item: OrderEntryItem) => {
      lastItemRef.current = item;
      // Pre-fill qty input with 1 (or blank for user to type)
      setQtyValue('');
      // Focus the qty input
      requestAnimationFrame(() => {
        if (qtyRef.current) {
          qtyRef.current.focus();
          qtyRef.current.select();
        }
      });
    },
    [qtyRef],
  );

  const commitEntry = useCallback(() => {
    const item = lastItemRef.current ?? selectedItem;
    if (!item) return;
    const qty = parseFloat(qtyValue);
    if (!Number.isFinite(qty) || qty <= 0) return;
    onCommit(item, qty);
    resetRow();
  }, [selectedItem, qtyValue, onCommit, resetRow]);

  const handleQtyKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        commitEntry();
      }
    },
    [commitEntry],
  );

  return (
    <div className="flex flex-wrap items-start gap-x-2 gap-y-1.5 px-3 py-2 border-b border-border/60 bg-muted/20">
      {/* Item Search */}
      <div className="flex min-h-0 flex-[1.2_1_346px] min-w-[260px] flex-col gap-1">
        <Label htmlFor="item-search" className={CONTROL_LABEL}>
          Item
        </Label>
        <EntityComboBox<OrderEntryItem>
          items={items}
          value={selectedItem?.item_id ?? null}
          onChange={(item) => setSelectedItem(item)}
          onAfterSelect={handleItemAfterSelect}
          getId={(item) => item.item_id}
          getLabel={(item) => `${item.item_number} ${item.item_name}`}
          getSearchText={(item) => `${item.item_number} ${item.item_name} ${item.category ?? ''}`}
          getParentId={() => null}
          getSortKey={(item) => item.item_number}
          placeholder="Search items…"
          disabled={disabled || isLoadingItems}
          loading={isLoadingItems}
          emptyText="No items found."
          clearable
          alwaysOpen
          collapseOnSelect
          clearSearchOnFocus
          inputRef={itemInputRef}
          triggerId="item-search"
          className="!flex-none min-h-0 w-full min-w-0 self-start"
        />
      </div>

      {/* Qty — same width as Delivery (w-20) */}
      <div className="flex w-20 shrink-0 flex-col gap-1">
        <Label
          htmlFor="item-qty"
          className={cn(
            CONTROL_LABEL,
            'w-full justify-center text-center !items-center',
          )}
        >
          Quantity
        </Label>
        <input
          id="item-qty"
          ref={qtyRef}
          type="number"
          className={[
            'h-9 w-full rounded-md border border-input bg-background px-2 text-sm',
            'text-right font-bold tabular-nums text-foreground leading-none',
            'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
            '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none',
            '[&::-webkit-inner-spin-button]:appearance-none',
            disabled ? 'opacity-50 cursor-not-allowed' : '',
          ].join(' ')}
          placeholder="0"
          min={0}
          step={1}
          value={qtyValue}
          disabled={disabled}
          onFocus={(e) => e.target.select()}
          onChange={(e) => setQtyValue(e.target.value)}
          onKeyDown={handleQtyKeyDown}
          aria-label="Quantity"
        />
      </div>

      {/* PO Number */}
      <div className="flex w-36 shrink-0 flex-col gap-1">
        <Label
          htmlFor="po-number"
          className={cn(CONTROL_LABEL, 'w-full justify-center text-center !items-center')}
        >
          PO Number
        </Label>
        <input
          id="po-number"
          type="text"
          className={[
            'h-9 w-full rounded-md border border-input bg-background px-2 text-sm',
            'text-foreground leading-none',
            'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
            disabled ? 'opacity-50 cursor-not-allowed' : '',
          ].join(' ')}
          value={poNumber}
          disabled={disabled}
          onChange={(e) => onPoNumberChange(e.target.value)}
          aria-label="PO Number"
        />
      </div>

      {/* Total Order */}
      <div className="flex w-24 shrink-0 flex-col gap-1">
        <span
          className={cn(
            CONTROL_LABEL,
            'w-full justify-center text-center !items-center',
          )}
        >
          Total Order
        </span>
        <span
          className={cn(
            'block h-9 w-full rounded border px-2 text-right text-sm font-bold tabular-nums',
            'leading-9',
            'bg-amber-50 dark:bg-amber-950/40',
            'border-amber-200 dark:border-amber-800',
            'text-amber-800 dark:text-amber-300',
          )}
          tabIndex={-1}
          aria-label="Total Order"
        >
          ${orderTotal.toFixed(2)}
        </span>
      </div>

      {/* Order Number */}
      <div className="flex w-[173px] min-w-0 shrink-0 flex-col gap-1">
        <Label
          htmlFor="order-number-display"
          className={cn(CONTROL_LABEL, 'w-full justify-center text-center !items-center')}
        >
          Order Number
        </Label>
        <div
          id="order-number-display"
          className={cn(
            'flex h-9 w-full items-center justify-center rounded-md border border-input bg-background px-3 text-center text-sm text-foreground',
            !orderNumber && 'text-muted-foreground',
          )}
          aria-label="Order number"
        >
          <span className="truncate">{orderNumber || 'New Order'}</span>
        </div>
      </div>

      {entryToolbar != null && (
        <div className="flex shrink-0 flex-col gap-1">
          <span className={cn(CONTROL_LABEL, 'invisible select-none')} aria-hidden>
            &nbsp;
          </span>
          <div className="flex h-9 items-center gap-1.5">{entryToolbar}</div>
        </div>
      )}
    </div>
  );
}
