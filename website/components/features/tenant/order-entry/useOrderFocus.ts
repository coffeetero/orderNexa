import { useCallback, useRef } from 'react';

/**
 * Deterministic focus machine for the Order Entry screen.
 *
 * Each public method schedules a focus via requestAnimationFrame so it
 * can be called from event handlers without fighting the browser's natural
 * focus flow.
 */
export function useOrderFocus() {
  /** Ref attached to the customer EntityComboBox internal <input> (alwaysOpen mode). */
  const customerInputRef = useRef<HTMLInputElement | null>(null);

  /** Ref attached to the item EntityComboBox internal <input> (alwaysOpen mode).
   *  Populated via the EntityComboBox `inputRef` prop. */
  const itemInputRef = useRef<HTMLInputElement | null>(null);

  /** Ref attached to the Qty <input> in ItemEntryRow. */
  const qtyRef = useRef<HTMLInputElement | null>(null);

  /**
   * Map key: `${tempId}-${col}` where col ∈ 'qty' | 'price' | 'discount'
   * Used to focus individual cells in OrderLineGrid.
   */
  const gridCellsRef = useRef<Map<string, HTMLInputElement>>(new Map());

  const focusCustomer = useCallback(() => {
    requestAnimationFrame(() => customerInputRef.current?.focus());
  }, []);

  const focusItem = useCallback(() => {
    requestAnimationFrame(() => {
      const el = itemInputRef.current;
      if (!el) return;
      el.focus();
      // clear text so the user can type a new search immediately
      el.select?.();
    });
  }, []);

  const focusQty = useCallback(() => {
    requestAnimationFrame(() => {
      const el = qtyRef.current;
      if (!el) return;
      el.focus();
      el.select();
    });
  }, []);

  const focusGridCell = useCallback(
    (tempId: string, col: 'qty' | 'price' | 'discount') => {
      const key = `${tempId}-${col}`;
      requestAnimationFrame(() => {
        const el = gridCellsRef.current.get(key);
        if (el) {
          el.focus();
          el.select();
        }
      });
    },
    [],
  );

  /**
   * Called by OrderLineGrid to register/unregister cell inputs.
   * Pass as a callback ref: ref={(el) => registerGridCell(tempId, col, el)}
   */
  const registerGridCell = useCallback(
    (tempId: string, col: 'qty' | 'price' | 'discount', el: HTMLInputElement | null) => {
      const key = `${tempId}-${col}`;
      if (el) {
        gridCellsRef.current.set(key, el);
      } else {
        gridCellsRef.current.delete(key);
      }
    },
    [],
  );

  return {
    customerInputRef,
    itemInputRef,
    qtyRef,
    focusCustomer,
    focusItem,
    focusQty,
    focusGridCell,
    registerGridCell,
  };
}

export type OrderFocusReturn = ReturnType<typeof useOrderFocus>;
