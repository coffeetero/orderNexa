'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
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

interface ItemPricebooksTabProps {
  tenantId: number;
  itemId: number | null;
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

export function ItemPricebooksTab({ tenantId, itemId }: ItemPricebooksTabProps) {
  const [rows, setRows]         = useState<PricebookRow[]>([]);
  const [original, setOriginal] = useState<PricebookRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving]   = useState(false);
  const [search, setSearch]       = useState('');
  const loadedItemId = useRef<number | null | undefined>(undefined);

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

  const updateRow = (pricebookId: number, patch: Partial<PricebookRow>) =>
    setRows((prev) => prev.map((r) => r.pricebook_id === pricebookId ? { ...r, ...patch } : r));

  const origMap = Object.fromEntries(original.map((r) => [r.pricebook_id, r]));
  const dirtyRows = rows.filter((r) => {
    const o = origMap[r.pricebook_id];
    return o && rowIsDirty(r, o);
  });
  const hasChanges = dirtyRows.length > 0;

  const handleCancel = () => {
    setRows(original);
    setSearch('');
  };

  const handleSave = async () => {
    const changes = dirtyRows
      .filter((r) => r.item_price !== '')
      .map((r) => ({
        pricebook_id:      r.pricebook_id,
        pricebook_item_id: r.pricebook_item_id,
        item_price:        parseFloat(r.item_price),
        is_active:         r.is_active ?? true,
      }));

    if (changes.length === 0) return;

    setIsSaving(true);
    try {
      const res  = await fetch('/api/items/pricebooks', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ tenant_id: tenantId, item_id: itemId, changes }),
      });
      const json = await res.json() as { data?: unknown; error?: string };
      if (!res.ok || json.error) {
        toast.error(json.error ?? 'Could not save prices.', { duration: Infinity });
        return;
      }
      toast.success('Prices saved.');
      await load();
    } finally {
      setIsSaving(false);
    }
  };

  if (!itemId) {
    return <p className="py-4 text-sm text-muted-foreground">Select an item to manage pricebook prices.</p>;
  }

  const filtered = rows.filter((r) =>
    r.pricebook_name.toLowerCase().includes(search.toLowerCase()),
  );

  return (
    <div className="space-y-3">
      {/* Toolbar */}
      <div className="flex items-center gap-2">
        <Input
          placeholder="Search pricebooks…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="h-8 max-w-xs text-sm"
        />
        <div className="ml-auto flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleCancel}
            disabled={!hasChanges || isSaving}
          >
            Cancel
          </Button>
          <Button
            size="sm"
            onClick={handleSave}
            disabled={!hasChanges || isSaving}
          >
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
        </div>
      </div>

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
              const hasRow    = row.pricebook_item_id !== null;
              const inactive  = hasRow && row.is_active === false;
              const o         = origMap[row.pricebook_id];
              const dirty     = o ? rowIsDirty(row, o) : false;

              return (
                <div
                  key={row.pricebook_id}
                  className={cn(
                    'grid grid-cols-[1fr_72px_148px] items-center border-b border-border/40 px-3 py-1.5 last:border-0 transition-colors',
                    inactive && 'opacity-50',
                    dirty && 'bg-amber-50 dark:bg-amber-950/20',
                  )}
                >
                  {/* Pricebook name */}
                  <span className="truncate pr-2 text-sm">{row.pricebook_name}</span>

                  {/* Active toggle — only when a pricebook_items row exists */}
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

                  {/* Price input — disabled on inactive rows until re-enabled */}
                  <div className="flex justify-end">
                    <Input
                      type="number"
                      step="0.01"
                      min="0"
                      disabled={inactive}
                      value={row.item_price}
                      onChange={(e) =>
                        updateRow(row.pricebook_id, { item_price: e.target.value })
                      }
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
}
