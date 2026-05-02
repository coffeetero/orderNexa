import { useCallback, useState } from 'react';
import type { DeliveryWindow, OrderEntryDraft, OrderEntryItem, OrderEntryLine } from '@/lib/types';

function calcExtended(qty: number, price: number, discount: number): number {
  return qty * (price - discount);
}

function calcTotal(lines: OrderEntryLine[]): number {
  return lines.reduce((sum, l) => sum + l.extended_amount, 0);
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function emptyDraft(): OrderEntryDraft {
  return {
    order_number: '',
    customer_id: null,
    customer_name: '',
    customer_credit: 0,
    order_date: today(),
    delivery_date: today(),
    delivery_window: 'AM',
    delivery_amount: 0,
    total_amount: 0,
    lines: [],
  };
}

export function useOrderEntryState(initial?: OrderEntryDraft) {
  const [draft, setDraft] = useState<OrderEntryDraft>(initial ?? emptyDraft());

  // ── Header field setters ─────────────────────────────────────────────────

  const setCustomer = useCallback((id: number | null, name: string) => {
    setDraft((prev) => ({ ...prev, customer_id: id, customer_name: name }));
  }, []);

  const setField = useCallback(
    <K extends keyof OrderEntryDraft>(field: K, value: OrderEntryDraft[K]) => {
      setDraft((prev) => ({ ...prev, [field]: value }));
    },
    [],
  );

  const reset = useCallback(() => setDraft(emptyDraft()), []);

  const loadOrder = useCallback((loaded: OrderEntryDraft) => setDraft(loaded), []);

  // ── Line management ──────────────────────────────────────────────────────

  /**
   * Adds a new line for the given item at the given quantity,
   * or updates the quantity if the item already exists in the grid.
   * Returns the tempId of the affected line.
   */
  const addOrUpdateLine = useCallback(
    (item: OrderEntryItem, quantity: number): string => {
      let affectedTempId = '';

      setDraft((prev) => {
        const existing = prev.lines.find((l) => l.item_id === item.item_id);

        if (existing) {
          // Update quantity on existing line
          const newLines = prev.lines.map((l) => {
            if (l.item_id !== item.item_id) return l;
            const extended = calcExtended(quantity, l.unit_price, l.unit_discount);
            affectedTempId = l.tempId;
            return { ...l, quantity, extended_amount: extended };
          });
          return { ...prev, lines: newLines, total_amount: calcTotal(newLines) };
        }

        // New line
        const tempId = crypto.randomUUID();
        affectedTempId = tempId;
        const unitPrice = item.unit_price ?? 0;
        const extended = calcExtended(quantity, unitPrice, 0);
        const newLine: OrderEntryLine = {
          tempId,
          item_id: item.item_id,
          item_number: item.item_number,
          item_description: item.item_name,
          is_sliced: item.default_sliced,
          is_wrapped: item.default_wrapped,
          is_covered: item.default_covered,
          is_scored: item.default_scored,
          can_slice: item.is_sliceable,
          can_wrap: item.is_wrappable,
          can_cover: item.is_coverable,
          can_score: item.is_scoreable,
          quantity,
          unit_price: unitPrice,
          unit_discount: 0,
          extended_amount: extended,
        };
        const newLines = [...prev.lines, newLine];
        return { ...prev, lines: newLines, total_amount: calcTotal(newLines) };
      });

      return affectedTempId;
    },
    [],
  );

  /** Updates any field(s) on an existing line by tempId. Recalculates extended_amount. */
  const updateLine = useCallback(
    (tempId: string, updates: Partial<Omit<OrderEntryLine, 'tempId' | 'extended_amount'>>) => {
      setDraft((prev) => {
        const newLines = prev.lines.map((l) => {
          if (l.tempId !== tempId) return l;
          const merged = { ...l, ...updates };
          merged.extended_amount = calcExtended(
            merged.quantity,
            merged.unit_price,
            merged.unit_discount,
          );
          return merged;
        });
        return { ...prev, lines: newLines, total_amount: calcTotal(newLines) };
      });
    },
    [],
  );

  const removeLine = useCallback((tempId: string) => {
    setDraft((prev) => {
      const newLines = prev.lines.filter((l) => l.tempId !== tempId);
      return { ...prev, lines: newLines, total_amount: calcTotal(newLines) };
    });
  }, []);

  /**
   * Returns the current quantity for an item in the grid (for prefilling Qty SLE
   * when the user selects an item that already exists in the grid).
   */
  const getLineQty = useCallback(
    (itemId: number): number | null => {
      const line = draft.lines.find((l) => l.item_id === itemId);
      return line ? line.quantity : null;
    },
    [draft.lines],
  );

  return {
    draft,
    setCustomer,
    setField,
    reset,
    loadOrder,
    addOrUpdateLine,
    updateLine,
    removeLine,
    getLineQty,
  };
}

export type OrderEntryStateReturn = ReturnType<typeof useOrderEntryState>;
