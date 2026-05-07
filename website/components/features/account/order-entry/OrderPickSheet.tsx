'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import type { OrderHeaderListRow } from '@/lib/types';
import { cn } from '@/lib/utils';

interface OrderPickSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  candidates: OrderHeaderListRow[];
  onNewOrder: () => void;
  onSelect: (row: OrderHeaderListRow) => void;
}

export function OrderPickSheet({
  open,
  onOpenChange,
  candidates,
  onNewOrder,
  onSelect,
}: OrderPickSheetProps) {
  const [activeIndex, setActiveIndex] = useState(0);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const optionCount = candidates.length + 1;

  useEffect(() => {
    if (!open) return;
    setActiveIndex(0);
    requestAnimationFrame(() => containerRef.current?.focus());
  }, [open, candidates.length]);

  const choices = useMemo(
    () => [
      { kind: 'new' as const },
      ...candidates.map((row) => ({ kind: 'existing' as const, row })),
    ],
    [candidates],
  );

  const selectActiveChoice = useCallback(() => {
    const choice = choices[activeIndex];
    if (!choice) return;
    if (choice.kind === 'new') {
      onNewOrder();
      return;
    }
    onSelect(choice.row);
  }, [activeIndex, choices, onNewOrder, onSelect]);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        setActiveIndex((current) => Math.min(current + 1, optionCount - 1));
        return;
      }
      if (event.key === 'ArrowUp') {
        event.preventDefault();
        setActiveIndex((current) => Math.max(current - 1, 0));
        return;
      }
      if (event.key === 'Home') {
        event.preventDefault();
        setActiveIndex(0);
        return;
      }
      if (event.key === 'End') {
        event.preventDefault();
        setActiveIndex(optionCount - 1);
        return;
      }
      if (event.key === 'Enter') {
        event.preventDefault();
        selectActiveChoice();
      }
    },
    [optionCount, selectActiveChoice],
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className={cn(
          'flex max-h-[min(560px,calc(100vh-4rem))] flex-col overflow-hidden p-0 sm:max-w-2xl',
        )}
      >
        <DialogHeader className="space-y-1 px-5 pb-3 pt-5">
          <DialogTitle className="text-base">Choose an order</DialogTitle>
          <DialogDescription>
            Existing orders match this customer and production slot.
          </DialogDescription>
        </DialogHeader>

        <div className="flex-1 overflow-auto px-5 pb-5">
          <div
            ref={containerRef}
            tabIndex={0}
            role="listbox"
            aria-label="Existing orders"
            aria-activedescendant={`order-pick-${activeIndex}`}
            className="rounded-md border border-border/80 divide-y divide-border/60 overflow-hidden bg-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 ring-offset-background"
            onKeyDown={handleKeyDown}
          >
            <button
              id="order-pick-0"
              type="button"
              role="option"
              aria-selected={activeIndex === 0}
              className={cn(
                'w-full px-3 py-2 text-left text-sm transition-colors',
                activeIndex === 0
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-amber-50/70 hover:bg-amber-100/80 dark:bg-amber-950/30 dark:hover:bg-amber-950/50',
                'focus:outline-none',
              )}
              tabIndex={-1}
              onMouseEnter={() => setActiveIndex(0)}
              onClick={onNewOrder}
            >
              <div className="grid grid-cols-[minmax(8rem,1fr)_minmax(12rem,2fr)_6rem] items-center gap-3">
                <span className="font-semibold">New Order</span>
                <span className={cn('truncate text-xs', activeIndex === 0 ? 'text-primary-foreground/80' : 'text-muted-foreground')}>
                  Start a new order for this slot
                </span>
                <span className="text-right text-sm font-semibold tabular-nums">$0.00</span>
              </div>
            </button>
            {candidates.map((row, index) => {
              const optionIndex = index + 1;
              const active = activeIndex === optionIndex;
              return (
              <button
                key={row.order_id}
                id={`order-pick-${optionIndex}`}
                type="button"
                role="option"
                aria-selected={active}
                className={cn(
                  'w-full text-left px-3 py-2 text-sm transition-colors',
                  active ? 'bg-primary text-primary-foreground' : 'hover:bg-accent/80',
                  'focus:outline-none',
                )}
                tabIndex={-1}
                onMouseEnter={() => setActiveIndex(optionIndex)}
                onClick={() => onSelect(row)}
              >
                <div className="grid grid-cols-[minmax(8rem,1fr)_minmax(12rem,2fr)_6rem] items-center gap-3">
                  <span className="truncate font-medium">
                    {row.order_number || `Order #${row.order_id}`}
                  </span>
                  <span className={cn('truncate text-xs', active ? 'text-primary-foreground/80' : 'text-muted-foreground')}>
                    {row.location_event || row.customer_name || `Customer ${row.customer_id}`}
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
        </div>
      </DialogContent>
    </Dialog>
  );
}
