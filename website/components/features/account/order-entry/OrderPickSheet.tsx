'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { X } from 'lucide-react';
import { Input } from '@/components/ui/input';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
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
  const [activeIndex, setActiveIndex] = useState(0);
  const [customerSearch, setCustomerSearch] = useState('');
  const [isDesktop, setIsDesktop] = useState(() =>
    typeof window === 'undefined' ? false : window.matchMedia('(min-width: 1024px)').matches,
  );
  const containerRef = useRef<HTMLDivElement | null>(null);
  const searchInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    const query = window.matchMedia('(min-width: 1024px)');
    const handleChange = () => setIsDesktop(query.matches);
    handleChange();
    query.addEventListener('change', handleChange);
    return () => query.removeEventListener('change', handleChange);
  }, []);

  useEffect(() => {
    if (!open) return;
    setActiveIndex(0);
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
        setActiveIndex((current) => Math.min(current + 1, Math.max(optionCount - 1, 0)));
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
        setActiveIndex(Math.max(optionCount - 1, 0));
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
            setActiveIndex(0);
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
          aria-activedescendant={`order-pick-${activeIndex}`}
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
              <div className="bg-muted/70 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-normal text-muted-foreground">
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
                      'w-full px-3 py-0.5 text-left text-sm transition-colors',
                      active ? 'bg-primary text-primary-foreground' : 'hover:bg-accent/80',
                      'focus:outline-none',
                    )}
                    tabIndex={-1}
                    onMouseEnter={() => setActiveIndex(optionIndex)}
                    onClick={() => onSelect(row)}
                  >
                    <div className="grid grid-cols-[minmax(0,1fr)_5.5rem] items-center gap-2">
                      <span className="truncate font-medium">
                        {row.department_event || `Order #${row.order_id}`}
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
    <>
      {!isDesktop && (
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
      )}

      {isDesktop && open && (
        <aside className="flex h-full w-[420px] shrink-0 flex-col overflow-hidden border-l border-border/60 bg-card">
          <div className="flex items-start justify-between gap-3 px-3 pb-3 pt-3">
            <div className="min-w-0 space-y-1">
              <h3 className="text-base font-semibold text-foreground">Existing Orders</h3>
              <p className="text-sm text-muted-foreground">
                Select an existing order.
              </p>
            </div>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-8 w-8 shrink-0"
              onClick={() => onOpenChange(false)}
              aria-label="Close existing orders"
            >
              <X className="h-4 w-4" />
            </Button>
          </div>
          {panelContent}
        </aside>
      )}
    </>
  );
}
