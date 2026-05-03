'use client';

import { useCallback } from 'react';
import { Trash2 } from 'lucide-react';
import { Checkbox } from '@/components/ui/checkbox';
import { cn } from '@/lib/utils';
import type { OrderEntryLine } from '@/lib/types';

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
            <th className="px-1.5 py-1.5 text-center font-semibold text-muted-foreground w-7">SL</th>
            <th className="px-1.5 py-1.5 text-center font-semibold text-muted-foreground w-7">W</th>
            <th className="px-1.5 py-1.5 text-center font-semibold text-muted-foreground w-7">CV</th>
            <th className="px-1.5 py-1.5 text-center font-semibold text-muted-foreground w-7">CS</th>
            <th className="px-2 py-1.5 text-right font-semibold text-muted-foreground w-16">Qty</th>
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
                colSpan={11}
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
                {/* Item No */}
                <td className="px-2 py-1 font-mono text-muted-foreground whitespace-nowrap">
                  {line.item_number}
                </td>

                {/* Item Description */}
                <td className="px-2 py-1 font-medium text-foreground">
                  {line.item_description}
                </td>

                {/* SL */}
                <td className="px-1.5 py-1 text-center">
                  <Checkbox
                    checked={line.is_sliced}
                    disabled={!line.can_slice}
                    onCheckedChange={(checked) =>
                      onLineUpdate(line.tempId, { is_sliced: Boolean(checked) })
                    }
                    className="h-3.5 w-3.5"
                    aria-label="Sliced"
                  />
                </td>

                {/* W */}
                <td className="px-1.5 py-1 text-center">
                  <Checkbox
                    checked={line.is_wrapped}
                    disabled={!line.can_wrap}
                    onCheckedChange={(checked) =>
                      onLineUpdate(line.tempId, { is_wrapped: Boolean(checked) })
                    }
                    className="h-3.5 w-3.5"
                    aria-label="Wrapped"
                  />
                </td>

                {/* CV */}
                <td className="px-1.5 py-1 text-center">
                  <Checkbox
                    checked={line.is_covered}
                    disabled={!line.can_cover}
                    onCheckedChange={(checked) =>
                      onLineUpdate(line.tempId, { is_covered: Boolean(checked) })
                    }
                    className="h-3.5 w-3.5"
                    aria-label="Covered"
                  />
                </td>

                {/* CS */}
                <td className="px-1.5 py-1 text-center">
                  <Checkbox
                    checked={line.is_scored}
                    disabled={!line.can_score}
                    onCheckedChange={(checked) =>
                      onLineUpdate(line.tempId, { is_scored: Boolean(checked) })
                    }
                    className="h-3.5 w-3.5"
                    aria-label="Scored"
                  />
                </td>

                {/* Qty */}
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

                {/* Price */}
                <td className="px-1 py-0.5">
                  <CellInput
                    value={line.unit_price}
                    inputRef={(el) => registerGridCell(line.tempId, 'price', el)}
                    onChange={(v) => onLineUpdate(line.tempId, { unit_price: v })}
                  />
                </td>

                {/* Discount */}
                <td className="px-1 py-0.5">
                  <CellInput
                    value={line.unit_discount}
                    inputRef={(el) => registerGridCell(line.tempId, 'discount', el)}
                    onChange={(v) => onLineUpdate(line.tempId, { unit_discount: v })}
                    onEnter={onDiscountEnter}
                  />
                </td>

                {/* Total */}
                <td className="px-2 py-1 text-right tabular-nums font-semibold text-foreground">
                  {line.extended_amount === 0 ? (
                    <span className="text-muted-foreground">—</span>
                  ) : (
                    line.extended_amount.toFixed(2)
                  )}
                </td>

                {/* Remove */}
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

        {/* Footer totals */}
        {lines.length > 0 && (
          <tfoot>
            <tr className="border-t border-border/60 bg-muted/30 font-semibold">
              <td colSpan={6} className="px-2 py-1.5 text-xs text-muted-foreground">
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
