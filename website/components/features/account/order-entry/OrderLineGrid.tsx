'use client';

import { useCallback } from 'react';
import { ChevronDown, Trash2 } from 'lucide-react';
import { Checkbox } from '@/components/ui/checkbox';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';
import type { OrderEntryLine, PrepOption } from '@/lib/types';

interface OrderLineGridProps {
  lines: OrderEntryLine[];
  activeLineIndex: number | null;
  onLineUpdate: (tempId: string, updates: Partial<Omit<OrderEntryLine, 'tempId' | 'extended_amount'>>) => void;
  onLineRemove: (tempId: string) => void;
  registerGridCell: (tempId: string, col: 'qty' | 'price' | 'discount', el: HTMLInputElement | null) => void;
  /** Called when user presses Enter in the Discount cell — moves focus to Item Search. */
  onDiscountEnter: () => void;
}

/** Shared cell input used for Qty, Price, and Discount columns. */
function CellInput({
  value,
  decimals = 2,
  onChange,
  onEnter,
  onTab,
  inputRef,
}: {
  value: number;
  decimals?: number;
  onChange: (n: number) => void;
  onEnter?: () => void;
  onTab?: () => void;
  inputRef?: (el: HTMLInputElement | null) => void;
}) {
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        onEnter?.();
      } else if (e.key === 'Tab') {
        // Allow natural tab but also call the callback
        onTab?.();
      }
    },
    [onEnter, onTab],
  );

  return (
    <input
      ref={inputRef}
      type="number"
      className={cn(
        'w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-right',
        'text-xs tabular-nums font-medium text-foreground',
        'focus:border-primary focus:bg-background focus:outline-none focus:ring-0',
        'hover:border-border',
        '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none',
      )}
      value={value === 0 ? '' : value}
      placeholder="0"
      step={decimals === 0 ? 1 : 0.01}
      min={0}
      onFocus={(e) => e.target.select()}
      onChange={(e) => {
        const v = parseFloat(e.target.value);
        onChange(isNaN(v) ? 0 : v);
      }}
      onKeyDown={handleKeyDown}
    />
  );
}

function PrepOptionsDropdown({
  idBase,
  allowedOptions,
  selectedOptions,
  onChange,
}: {
  idBase: string;
  allowedOptions: PrepOption[];
  selectedOptions: PrepOption[];
  onChange: (next: PrepOption[]) => void;
}) {
  const selectedValues = new Set(selectedOptions.map((option) => option.value));
  const summary = selectedOptions.length > 0
    ? selectedOptions.map((option) => option.label).join(', ')
    : 'None';

  const toggleOption = (option: PrepOption, checked: boolean) => {
    if (checked) {
      onChange([...selectedOptions.filter((selected) => selected.value !== option.value), option]);
      return;
    }
    onChange(selectedOptions.filter((selected) => selected.value !== option.value));
  };

  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          className={cn(
            'flex h-7 w-36 max-w-36 min-w-36 items-center justify-between gap-1 rounded border border-input bg-background px-2',
            'text-left text-xs text-foreground shadow-sm transition-colors hover:bg-muted/40',
            'focus:outline-none focus:ring-1 focus:ring-primary',
          )}
          title={summary}
        >
          <span className="min-w-0 truncate">{summary}</span>
          <ChevronDown className="h-3 w-3 shrink-0 text-muted-foreground" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-48 p-2">
        <div className="space-y-1">
          {allowedOptions.length === 0 ? (
            <div className="px-1.5 py-1 text-xs text-muted-foreground">
              No prep options
            </div>
          ) : (
            allowedOptions.map((option) => (
              <div
                key={option.value}
                className="flex items-center gap-2 rounded px-1.5 py-1 text-xs hover:bg-muted/50"
              >
                <Checkbox
                  id={`${idBase}-${option.value}`}
                  checked={selectedValues.has(option.value)}
                  onCheckedChange={(checked) => toggleOption(option, Boolean(checked))}
                  className="h-3.5 w-3.5"
                  aria-label={option.label}
                />
                <label htmlFor={`${idBase}-${option.value}`} className="min-w-0 truncate">
                  {option.label}
                </label>
              </div>
            ))
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}

export function OrderLineGrid({
  lines,
  activeLineIndex,
  onLineUpdate,
  onLineRemove,
  registerGridCell,
  onDiscountEnter,
}: OrderLineGridProps) {
  const totals = lines.reduce(
    (acc, l) => ({
      qty: acc.qty + l.quantity,
      price: acc.price + l.unit_price,
      amount: acc.amount + l.extended_amount,
    }),
    { qty: 0, price: 0, amount: 0 },
  );

  return (
    <div className="flex-1 overflow-auto rounded-lg border border-border/60">
      <table className="w-full border-collapse text-xs">
        <thead>
          <tr className="bg-muted/50 border-b border-border/60">
            <th className="px-2 py-1.5 text-left font-semibold text-muted-foreground whitespace-nowrap w-20">Item No.</th>
            <th className="px-2 py-1.5 text-left font-semibold text-muted-foreground">Item Description</th>
            <th className="px-2 py-1.5 text-left font-semibold text-muted-foreground w-40 min-w-40 max-w-40">Prep</th>
            <th className="px-2 py-1.5 text-right font-semibold text-muted-foreground w-20">Quantity</th>
            <th className="px-2 py-1.5 text-right font-semibold text-muted-foreground w-20">Price</th>
            <th className="px-2 py-1.5 text-right font-semibold text-muted-foreground w-20">Discnt</th>
            <th className="px-2 py-1.5 text-right font-semibold text-muted-foreground w-24">Total</th>
            <th className="w-7" aria-label="Remove" />
          </tr>
        </thead>
        <tbody>
          {lines.length === 0 && (
            <tr>
              <td
                colSpan={8}
                className="py-8 text-center text-xs text-muted-foreground italic"
              >
                No items added yet. Use the search above to add items.
              </td>
            </tr>
          )}
          {lines.map((line, idx) => {
            const isActive = idx === activeLineIndex;
            return (
              <tr
                key={line.tempId}
                className={cn(
                  'border-b border-border/40 transition-colors',
                  isActive
                    ? 'bg-primary/8 border-l-2 border-l-primary'
                    : 'hover:bg-muted/20',
                )}
              >
                <td className="px-2 py-1 font-mono text-muted-foreground whitespace-nowrap">
                  {line.item_number}
                </td>

                <td className="px-2 py-1 font-medium text-foreground">
                  {line.item_description}
                </td>

                <td className="w-40 min-w-40 max-w-40 px-1 py-0.5">
                  <PrepOptionsDropdown
                    idBase={`prep-${line.tempId}`}
                    allowedOptions={line.allowed_prep_options}
                    selectedOptions={line.prep_options}
                    onChange={(prep_options) => onLineUpdate(line.tempId, { prep_options })}
                  />
                </td>

                <td className="px-1 py-0.5">
                  <CellInput
                    value={line.quantity}
                    decimals={0}
                    inputRef={(el) => registerGridCell(line.tempId, 'qty', el)}
                    onChange={(v) => onLineUpdate(line.tempId, { quantity: v })}
                    onEnter={() => {
                      // Tab to Price
                    }}
                    onTab={() => {
                      // handled by browser tab naturally
                    }}
                  />
                </td>

                <td className="px-1 py-0.5">
                  <CellInput
                    value={line.unit_price}
                    inputRef={(el) => registerGridCell(line.tempId, 'price', el)}
                    onChange={(v) => onLineUpdate(line.tempId, { unit_price: v })}
                  />
                </td>

                <td className="px-1 py-0.5">
                  <CellInput
                    value={line.unit_discount}
                    inputRef={(el) => registerGridCell(line.tempId, 'discount', el)}
                    onChange={(v) => onLineUpdate(line.tempId, { unit_discount: v })}
                    onEnter={onDiscountEnter}
                  />
                </td>

                <td className="px-2 py-1 text-right tabular-nums font-semibold text-foreground">
                  {line.extended_amount === 0 ? (
                    <span className="text-muted-foreground">-</span>
                  ) : (
                    line.extended_amount.toFixed(2)
                  )}
                </td>

                <td className="px-1 py-1 text-center">
                  <button
                    type="button"
                    onClick={() => onLineRemove(line.tempId)}
                    className="rounded p-0.5 text-muted-foreground/50 hover:bg-destructive/10 hover:text-destructive transition-colors"
                    aria-label="Remove line"
                  >
                    <Trash2 className="h-3 w-3" />
                  </button>
                </td>
              </tr>
            );
          })}
        </tbody>

        {lines.length > 0 && (
          <tfoot>
            <tr className="border-t border-border/60 bg-muted/30 font-semibold">
              <td colSpan={3} className="px-2 py-1.5 text-xs text-muted-foreground">
                {lines.length} {lines.length === 1 ? 'item' : 'items'}
              </td>
              <td className="px-2 py-1.5 text-right tabular-nums text-xs">{totals.qty}</td>
              <td className="px-2 py-1.5" />
              <td className="px-2 py-1.5" />
              <td className="px-2 py-1.5 text-right tabular-nums text-sm font-bold text-foreground">
                ${totals.amount.toFixed(2)}
              </td>
              <td />
            </tr>
          </tfoot>
        )}
      </table>
    </div>
  );
}
