'use client';

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
  onSelect: (row: OrderHeaderListRow) => void;
}

export function OrderPickSheet({
  open,
  onOpenChange,
  candidates,
  onSelect,
}: OrderPickSheetProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        className={cn(
          'flex flex-col w-full sm:max-w-md',
          'overflow-hidden gap-0 p-0 pt-6',
        )}
      >
        <SheetHeader className="space-y-1 px-6 pr-14">
          <SheetTitle className="text-base">Choose an order</SheetTitle>
          <SheetDescription>
            Several orders match this customer and production slot. Pick one to load its lines.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 flex-1 overflow-auto px-6 pb-6">
          <div className="rounded-md border border-border/80 divide-y divide-border/60 overflow-hidden bg-card">
            {candidates.map((row) => (
              <button
                key={row.order_id}
                type="button"
                className={cn(
                  'w-full text-left px-3 py-3 text-sm transition-colors',
                  'hover:bg-accent/80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 ring-offset-background',
                )}
                onClick={() => onSelect(row)}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 space-y-0.5">
                    <p className="font-medium text-foreground truncate">
                      {row.order_number || `Order #${row.order_id}`}
                    </p>
                    <p className="text-xs text-muted-foreground tabular-nums">
                      Customer {row.customer_id}
                      {' · '}
                      {row.production_date}
                      {' · '}
                      {row.production_code}
                    </p>
                  </div>
                  <span className="shrink-0 text-sm font-semibold tabular-nums text-foreground">
                    {Number(row.amount ?? 0).toLocaleString(undefined, {
                      minimumFractionDigits: 2,
                      maximumFractionDigits: 2,
                    })}
                  </span>
                </div>
              </button>
            ))}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
