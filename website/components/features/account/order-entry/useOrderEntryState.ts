import { useCallback, useState } from 'react';
import type { OrderEntryDraft, OrderEntryItem, OrderEntryLine, PrepOption } from '@/lib/types';

function calcExtended(qty: number, price: number, discount: number): number {
  return qty * (price - discount);
}

export function resolveItemUnitPrice(item: OrderEntryItem): number {
  const candidate = (item as OrderEntryItem & { item_price?: unknown; price?: unknown });
  const raw =
    item.unit_price ??
    (typeof candidate.item_price === 'number' ? candidate.item_price : null) ??
    (typeof candidate.price === 'number' ? candidate.price : null);
  return typeof raw === 'number' && Number.isFinite(raw) ? raw : 0;
}

function calcTotal(lines: OrderEntryLine[]): number {
  return lines.reduce((sum, l) => sum + l.extended_amount, 0);
}

function normalizePrepOptions(options: PrepOption[] | null | undefined): PrepOption[] {
  if (!Array.isArray(options)) return [];
  return options
    .filter((option) => option && typeof option.value === 'string' && option.value.trim())
    .map((option) => ({
      value: option.value.trim(),
      label: option.label?.trim() || option.value.trim(),
    }));
}

function today(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function tomorrow(): string {
  const now = new Date();
  now.setDate(now.getDate() + 1);
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function emptyDraft(): OrderEntryDraft {
  return {
    order_number: '',
    po_number: '',
    order_ref: '',
    customer_id: null,
    customer_name: '',
    department_event: '',
    customer_credit: 0,
    order_date: today(),
    production_date: tomorrow(),
    production_code: '',
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
      setDraft((prev) =>
        // another order: its invoice is loaded with it, so never show the previous order's
        field === 'order_id' && prev.order_id !== value
          ? { ...prev, [field]: value, invoice_number: null, invoice_status: undefined }
          : { ...prev, [field]: value },
      );
    },
    [],
  );

  const reset = useCallback((options?: { preserveProductionSlot?: boolean }) => {
    setDraft((prev) => {
      const next = emptyDraft();
      if (!options?.preserveProductionSlot) return next;
      return {
        ...next,
        production_date: prev.production_date,
        production_code: prev.production_code,
      };
    });
  }, []);

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
            // Keep the line's snapshotted price from when it was first added.
            const extended = calcExtended(quantity, l.unit_price, l.unit_discount);
            affectedTempId = l.tempId;
            return { ...l, quantity, extended_amount: extended, copied: quantity === l.quantity ? l.copied : false };
          });
          return { ...prev, lines: newLines, total_amount: calcTotal(newLines) };
        }

        // New line
        const tempId = crypto.randomUUID();
        affectedTempId = tempId;
        const unitPrice = resolveItemUnitPrice(item);
        const extended = calcExtended(quantity, unitPrice, 0);
        const allowedPrepOptions = normalizePrepOptions(item.allowed_prep_options);
        const newLine: OrderEntryLine = {
          tempId,
          item_id: item.item_id,
          item_number: item.item_number,
          item_description: item.item_name,
          allowed_prep_options: allowedPrepOptions,
          prep_options: normalizePrepOptions(item.default_prep_options),
          is_scored: item.default_scored,
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
          if (updates.quantity !== undefined && updates.quantity !== l.quantity) merged.copied = false;
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

  /**
   * Copy order: adds each copied line in addition to the order. An item already on the order gets the copied
   * quantity added; a new one is priced from the current order's items. Prep options and scoring come from the copied line.
   */
  const addCopiedLines = useCallback(
    (copies: { item: OrderEntryItem; quantity: number; prep_options: PrepOption[]; is_scored: boolean }[], options?: { fromStandingOrder?: boolean }) => {
      const copied = !options?.fromStandingOrder;
      setDraft((prev) => {
        let newLines = [...prev.lines];
        for (const { item, quantity, prep_options, is_scored } of copies) {
          const existing = newLines.find((l) => l.item_id === item.item_id);
          if (existing) {
            newLines = newLines.map((l) => l === existing
              ? { ...l, quantity: l.quantity + quantity, extended_amount: calcExtended(l.quantity + quantity, l.unit_price, l.unit_discount), copied }
              : l);
            continue;
          }
          const allowed = normalizePrepOptions(item.allowed_prep_options);
          const unitPrice = resolveItemUnitPrice(item);
          newLines.push({
            tempId: crypto.randomUUID(),
            item_id: item.item_id,
            item_number: item.item_number,
            item_description: item.item_name,
            allowed_prep_options: allowed,
            prep_options: normalizePrepOptions(prep_options).filter((o) => allowed.some((a) => a.value === o.value)),
            is_scored: item.is_scoreable ? is_scored : false,
            can_score: item.is_scoreable,
            quantity,
            unit_price: unitPrice,
            unit_discount: 0,
            extended_amount: calcExtended(quantity, unitPrice, 0),
            copied,
          });
        }
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

  const zeroLinePrices = useCallback(() => {
    setDraft((prev) => ({
      ...prev,
      lines: prev.lines.map((line) => ({
        ...line,
        unit_price: 0,
        unit_discount: 0,
        extended_amount: 0,
        is_sample: true,
      })),
      total_amount: 0,
    }));
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
    addCopiedLines,
    updateLine,
    removeLine,
    zeroLinePrices,
    getLineQty,
  };
}

export type OrderEntryStateReturn = ReturnType<typeof useOrderEntryState>;
