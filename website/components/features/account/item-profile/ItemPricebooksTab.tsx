'use client';

import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { toast } from 'sonner';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

interface PricebookRow {
  pricebook_id: number;
  pricebook_name: string;
  pricebook_item_id: number | null;
  item_price: string;        // '' when unpriced
  is_active: boolean | null; // null when unpriced (no row yet)
}

interface RawRow {
  pricebook_id: number;
  pricebook_name: string;
  pricebook_item_id: number | null;
  item_price: number | null;
  is_active: boolean | null;
}

export interface ItemPricebooksTabHandle {
  /** Saves all dirty rows. Returns true on success, false on failure (error already toasted). */
  save: () => Promise<boolean>;
  /** Resets all pending changes back to last-loaded state. */
  reset: () => void;
}

interface ItemPricebooksTabProps {
  tenantId: number;
  itemId: number | null;
  /** Called whenever the tab's dirty state changes, so the parent can update the global Save button. */
  onDirtyChange: (dirty: boolean) => void;
}

function toRow(d: RawRow): PricebookRow {
  return {
    pricebook_id:      d.pricebook_id,
    pricebook_name:    d.pricebook_name,
    pricebook_item_id: d.pricebook_item_id,
    item_price:        d.item_price != null ? String(d.item_price) : '',
    is_active:         d.is_active,
  };
}

function rowIsDirty(row: PricebookRow, orig: PricebookRow): boolean {
  return row.item_price !== orig.item_price || row.is_active !== orig.is_active;
}

export const ItemPricebooksTab = forwardRef<ItemPricebooksTabHandle, ItemPricebooksTabProps>(
  function ItemPricebooksTab({ tenantId, itemId, onDirtyChange }, ref) {
    const [rows, setRows]           = useState<PricebookRow[]>([]);
    const [original, setOriginal]   = useState<PricebookRow[]>([]);
    const [isLoading, setIsLoading] = useState(false);
    const [search, setSearch]       = useState('');
    const loadedItemId = useRef<number | null | undefined>(undefined);

    // Stable refs so imperative handle always sees latest state without re-creating
    const rowsRef     = useRef(rows);
    const originalRef = useRef(original);
    rowsRef.current     = rows;
    originalRef.current = original;

    const load = useCallback(async () => {
      if (!itemId) return;
      setIsLoading(true);
      try {
        const res  = await fetch(`/api/items/pricebooks?tenant_id=${tenantId}&item_id=${itemId}`);
        const json = await res.json() as { data?: RawRow[]; error?: string };
        if (!res.ok || json.error) {
          toast.error(json.error ?? 'Could not load pricebooks.', { duration: Infinity });
          return;
        }
        const mapped = (json.data ?? []).map(toRow);
        setRows(mapped);
        setOriginal(mapped);
        loadedItemId.current = itemId;
      } finally {
        setIsLoading(false);
      }
    }, [tenantId, itemId]);

    useEffect(() => {
      if (itemId !== loadedItemId.current) {
        void load();
      }
    }, [itemId, load]);

    // Notify parent whenever dirty state changes
    const origMap  = Object.fromEntries(original.map((r) => [r.pricebook_id, r]));
    const isDirty  = rows.some((r) => { const o = origMap[r.pricebook_id]; return o ? rowIsDirty(r, o) : false; });
    const prevDirty = useRef(false);
    useEffect(() => {
      if (isDirty !== prevDirty.current) {
        prevDirty.current = isDirty;
        onDirtyChange(isDirty);
      }
    }, [isDirty, onDirtyChange]);

    // Expose save() and reset() to parent via ref
    useImperativeHandle(ref, () => ({
      save: async () => {
        const currentOrigMap = Object.fromEntries(originalRef.current.map((r) => [r.pricebook_id, r]));
        const changes = rowsRef.current
          .filter((r) => { const o = currentOrigMap[r.pricebook_id]; return o ? rowIsDirty(r, o) : false; })
          .filter((r) => r.item_price !== '')
          .map((r) => ({
            pricebook_id:      r.pricebook_id,
            pricebook_item_id: r.pricebook_item_id,
            item_price:        parseFloat(r.item_price),
            is_active:         r.is_active ?? true,
          }));

        if (changes.length === 0) return true;

        try {
          const res  = await fetch('/api/items/pricebooks', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ tenant_id: tenantId, item_id: itemId, changes }),
          });
          const json = await res.json() as { data?: unknown; error?: string };
          if (!res.ok || json.error) {
            toast.error(json.error ?? 'Could not save prices.', { duration: Infinity });
            return false;
          }
          await load();
          return true;
        } catch {
          toast.error('Could not save prices.', { duration: Infinity });
          return false;
        }
      },
      reset: () => {
        setRows(originalRef.current);
        setSearch('');
      },
    }), [tenantId, itemId, load]);

    const updateRow = (pricebookId: number, patch: Partial<PricebookRow>) =>
      setRows((prev) => prev.map((r) => r.pricebook_id === pricebookId ? { ...r, ...patch } : r));

    if (!itemId) {
      return <p className="py-4 text-sm text-muted-foreground">Select an item to manage pricebook prices.</p>;
    }

    const filtered = rows.filter((r) =>
      r.pricebook_name.toLowerCase().includes(search.toLowerCase()),
    );

    return (
      <div className="space-y-3">
        {/* Search */}
        <Input
          placeholder="Search pricebooks…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="h-8 max-w-xs text-sm"
        />

        {/* Grid */}
        {isLoading ? (
          <p className="py-4 text-sm text-muted-foreground">Loading…</p>
        ) : (
          <div className="overflow-hidden rounded-md border border-border/60">
            {/* Header */}
            <div className="grid grid-cols-[1fr_72px_148px] border-b border-border/60 bg-muted/40 px-3 py-2 text-xs font-semibold text-muted-foreground">
              <span>Pricebook</span>
              <span className="text-center">Active</span>
              <span className="text-right">Price</span>
            </div>

            {/* Rows */}
            {filtered.length === 0 ? (
              <div className="px-3 py-6 text-center text-sm text-muted-foreground">
                No pricebooks found.
              </div>
            ) : (
              filtered.map((row) => {
                const hasRow   = row.pricebook_item_id !== null;
                const inactive = hasRow && row.is_active === false;
                const dirty    = origMap[row.pricebook_id] ? rowIsDirty(row, origMap[row.pricebook_id]) : false;

                return (
                  <div
                    key={row.pricebook_id}
                    className={cn(
                      'grid grid-cols-[1fr_72px_148px] items-center border-b border-border/40 px-3 py-1.5 last:border-0 transition-colors',
                      inactive && 'opacity-50',
                      dirty && 'bg-amber-50 dark:bg-amber-950/20',
                    )}
                  >
                    <span className="truncate pr-2 text-sm">{row.pricebook_name}</span>

                    <div className="flex justify-center">
                      {hasRow && (
                        <Checkbox
                          checked={row.is_active === true}
                          onCheckedChange={(checked) =>
                            updateRow(row.pricebook_id, { is_active: Boolean(checked) })
                          }
                          className="h-4 w-4"
                        />
                      )}
                    </div>

                    <div className="flex justify-end">
                      <Input
                        type="number"
                        step="0.01"
                        min="0"
                        disabled={inactive}
                        value={row.item_price}
                        onChange={(e) => updateRow(row.pricebook_id, { item_price: e.target.value })}
                        placeholder="—"
                        className="h-7 w-28 text-right text-sm"
                      />
                    </div>
                  </div>
                );
              })
            )}
          </div>
        )}
      </div>
    );
  },
);
