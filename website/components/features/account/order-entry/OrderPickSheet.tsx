'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Input } from '@/components/ui/input';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';
import type { OrderHeaderListRow } from '@/lib/types';
import { cn } from '@/lib/utils';

interface OrderPickSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  candidates: OrderHeaderListRow[];
  loading?: boolean;
  onNewOrder: () => void;
  onSelect: (row: OrderHeaderListRow) => void;
}

export function OrderPickSheet({
  open,
  onOpenChange,
  candidates,
  loading = false,
  onSelect,
}: OrderPickSheetProps) {
  const [activeIndex, setActiveIndex] = useState(-1);
  const [customerSearch, setCustomerSearch] = useState('');
  const containerRef = useRef<HTMLDivElement | null>(null);
  const searchInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (!open) return;
    setActiveIndex(-1);
    setCustomerSearch('');
    requestAnimationFrame(() => searchInputRef.current?.focus());
  }, [open, candidates.length]);

  const rowsWithOption = useMemo(() => {
    const q = customerSearch.trim().toLowerCase();
    const filtered = q
      ? candidates.filter((row) =>
          [
            row.customer_name,
            row.department_event,
            row.order_number,
          ]
            .filter(Boolean)
            .join(' ')
            .toLowerCase()
            .includes(q),
        )
      : candidates;

    return filtered.map((row, index) => ({ row, optionIndex: index }));
  }, [candidates, customerSearch]);

  const groupedRows = useMemo(() => {
    const groups: Array<{
      customerName: string;
      rows: typeof rowsWithOption;
    }> = [];
    const groupByCustomer = new Map<string, { customerName: string; rows: typeof rowsWithOption }>();

    for (const option of rowsWithOption) {
      const customerName = option.row.customer_name?.trim() || 'Unknown Customer';
      const key = customerName.toUpperCase();
      let group = groupByCustomer.get(key);
      if (!group) {
        group = { customerName, rows: [] };
        groupByCustomer.set(key, group);
        groups.push(group);
      }
      group.rows.push(option);
    }

    return groups;
  }, [rowsWithOption]);

  const optionCount = rowsWithOption.length;

  const selectActiveChoice = useCallback(() => {
    const choice = rowsWithOption[activeIndex];
    if (!choice) return;
    onSelect(choice.row);
  }, [activeIndex, rowsWithOption, onSelect]);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        if (optionCount === 0) {
          setActiveIndex(-1);
          return;
        }
        setActiveIndex((current) => Math.min(current + 1, Math.max(optionCount - 1, 0)));
        return;
      }
      if (event.key === 'ArrowUp') {
        event.preventDefault();
        if (optionCount === 0) {
          setActiveIndex(-1);
          return;
        }
        setActiveIndex((current) => {
          if (current < 0) return Math.max(optionCount - 1, 0);
          return Math.max(current - 1, 0);
        });
        return;
      }
      if (event.key === 'Home') {
        event.preventDefault();
        setActiveIndex(optionCount > 0 ? 0 : -1);
        return;
      }
      if (event.key === 'End') {
        event.preventDefault();
        setActiveIndex(optionCount > 0 ? optionCount - 1 : -1);
        return;
      }
      if (event.key === 'Enter') {
        event.preventDefault();
        selectActiveChoice();
      }
    },
    [optionCount, selectActiveChoice],
  );

  const panelContent = (
    <>
      <div className="px-4 pb-3 lg:px-3">
        <Input
          ref={searchInputRef}
          value={customerSearch}
          onChange={(event) => {
            setCustomerSearch(event.target.value);
            setActiveIndex(-1);
          }}
          placeholder="Search Customer, Department/Event or Order.."
          className="h-8 text-sm"
          onKeyDown={(event) => {
            if (['ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter'].includes(event.key)) {
              event.stopPropagation();
            }
            handleKeyDown(event);
          }}
        />
      </div>

      <div className="min-h-0 flex-1 overflow-auto px-4 pb-4 lg:px-3 lg:pb-3">
        <div
          ref={containerRef}
          tabIndex={0}
          role="listbox"
          aria-label="Existing orders"
          aria-activedescendant={activeIndex >= 0 ? `order-pick-${activeIndex}` : undefined}
          className="overflow-hidden rounded-md border border-border/80 bg-card divide-y divide-border/60 ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
          onKeyDown={handleKeyDown}
        >
          {loading && (
            <div className="px-3 py-3 text-sm text-muted-foreground">
              Loading existing orders...
            </div>
          )}
          {!loading && rowsWithOption.length === 0 && (
            <div className="px-3 py-3 text-sm text-muted-foreground">
              No matching existing orders.
            </div>
          )}
          {!loading && groupedRows.map((group) => (
            <div key={group.customerName}>
              <div className="bg-background px-3 py-1 text-sm font-semibold uppercase tracking-normal text-foreground">
                {group.customerName}
              </div>
              {group.rows.map(({ row, optionIndex }) => {
                const active = activeIndex === optionIndex;
                return (
                  <button
                    key={row.order_id}
                    id={`order-pick-${optionIndex}`}
                    type="button"
                    role="option"
                    aria-selected={active}
                    className={cn(
                      'w-full py-0.5 pl-6 pr-3 text-left text-sm transition-colors',
                      active ? 'bg-primary text-primary-foreground' : 'hover:bg-accent/80',
                      'focus:outline-none',
                    )}
                    tabIndex={-1}
                    onClick={() => onSelect(row)}
                  >
                    <div className="grid grid-cols-[minmax(0,1fr)_5.5rem] items-center gap-2">
                      <span className="truncate text-xs font-medium">
                        {row.order_number || `Order #${row.order_id}`}
                        {row.department_event ? ` · ${row.department_event}` : ''}
                      </span>
                      <span className="text-right text-sm font-semibold tabular-nums">
                        $
                        {Number(row.amount ?? 0).toLocaleString(undefined, {
                          minimumFractionDigits: 2,
                          maximumFractionDigits: 2,
                        })}
                      </span>
                    </div>
                  </button>
                );
              })}
            </div>
          ))}
        </div>
      </div>
    </>
  );

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        className="flex w-[min(420px,100vw)] max-w-none flex-col gap-0 overflow-hidden p-0"
      >
        <SheetHeader className="space-y-1 px-4 pb-3 pt-5 pr-10">
          <SheetTitle className="text-base">Existing Orders</SheetTitle>
          <SheetDescription>
            Select an existing order.
          </SheetDescription>
        </SheetHeader>
        {panelContent}
      </SheetContent>
    </Sheet>
  );
}
