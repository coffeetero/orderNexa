'use client';

import { useCallback, useRef, useState } from 'react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Label } from '@/components/ui/label';
import type { OrderEntryItem } from '@/lib/types';

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
}

export function ItemEntryRow({
  items,
  isLoadingItems,
  disabled,
  itemInputRef,
  qtyRef,
  onCommit,
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
    <div className="flex items-end gap-2 px-3 py-2 border-b border-border/60 bg-muted/20">
      {/* Item Search */}
      <div className="flex flex-col gap-1 flex-1 min-w-0">
        <Label htmlFor="item-search" className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
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
          className="min-w-0"
          contentClassName="z-50"
        />
      </div>

      {/* Qty SLE */}
      <div className="flex flex-col gap-1 w-28 shrink-0">
        <Label htmlFor="item-qty" className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
          Qty
        </Label>
        <input
          id="item-qty"
          ref={qtyRef}
          type="number"
          className={[
            'h-9 w-full rounded-md border border-input bg-background px-3',
            'text-right text-lg font-bold tabular-nums text-foreground',
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
    </div>
  );
}
