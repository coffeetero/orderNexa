'use client';

import { forwardRef, useCallback, useEffect, useImperativeHandle, useMemo, useRef, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

interface Row { item_id: number; item_number: string; item_name: string; is_active: boolean; quantity: string }
interface Candidate { item_id: number; item_number: string; item_name: string; is_active: boolean; is_compound?: boolean }

export interface ItemComponentsTabHandle {
  /** Saves the component list. Returns true on success (error already toasted). */
  save: () => Promise<boolean>;
  /** Puts the list back to the last loaded state. */
  reset: () => void;
  /** How many components are on the list right now (unsaved changes included). */
  count: () => number;
  /** Empties the list (applied when saved). */
  clear: () => void;
}

interface Props {
  tenantId: number;
  itemId: number | null;
  /** Every item; simple ones other than this item can be added. */
  candidates: Candidate[];
  disabled?: boolean;
  onDirtyChange: (dirty: boolean) => void;
}

const snap = (rows: Row[]) => JSON.stringify(rows.map((r) => [r.item_id, r.quantity]));
const qtyBad = (r: Row) => r.quantity.trim() === '' || !Number.isFinite(Number(r.quantity)) || Number(r.quantity) <= 0;

export const ItemComponentsTab = forwardRef<ItemComponentsTabHandle, Props>(function ItemComponentsTab({ tenantId, itemId, candidates, disabled, onDirtyChange }, ref) {
  const [rows, setRows] = useState<Row[]>([]);
  const [original, setOriginal] = useState<Row[]>([]);
  const [q, setQ] = useState('');
  const rowsRef = useRef(rows);
  const originalRef = useRef(original);
  rowsRef.current = rows;
  originalRef.current = original;

  const load = useCallback(async () => {
    if (!itemId) { setRows([]); setOriginal([]); return; }
    const res = await fetch(`/api/items/components?tenant_id=${tenantId}&item_id=${itemId}`);
    const json = (await res.json()) as { data?: { item_id: number; item_number: string; item_name: string; is_active: boolean; quantity: number }[]; error?: string };
    if (!res.ok || json.error) { toast.error(json.error ?? 'Could not load components.', { duration: Infinity }); return; }
    const mapped = (json.data ?? []).map((c) => ({ ...c, quantity: String(c.quantity) }));
    setRows(mapped);
    setOriginal(mapped);
  }, [tenantId, itemId]);

  useEffect(() => { void load(); }, [load]);

  const dirty = snap(rows) !== snap(original);
  const prevDirty = useRef(false);
  const onDirtyRef = useRef(onDirtyChange);
  onDirtyRef.current = onDirtyChange;
  // The tab unmounts when Compound item is turned off: clear its dirty flag with it.
  useEffect(() => () => onDirtyRef.current(false), []);
  useEffect(() => {
    if (dirty !== prevDirty.current) { prevDirty.current = dirty; onDirtyChange(dirty); }
  }, [dirty, onDirtyChange]);

  useImperativeHandle(ref, () => ({
    save: async () => {
      if (snap(rowsRef.current) === snap(originalRef.current)) return true;
      if (rowsRef.current.some(qtyBad)) { toast.error('Every component needs a quantity above 0.'); return false; }
      const res = await fetch('/api/items/components', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, item_id: itemId, entries: rowsRef.current.map((r) => ({ item_id: r.item_id, quantity: Number(r.quantity) })) }),
      });
      const json = (await res.json()) as { error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not save components.', { duration: Infinity }); return false; }
      await load();
      return true;
    },
    reset: () => setRows(originalRef.current),
    count: () => rowsRef.current.length,
    clear: () => setRows([]),
  }), [tenantId, itemId, load]);

  const inList = useMemo(() => new Set(rows.map((r) => r.item_id)), [rows]);
  const matches = useMemo(() => {
    const t = q.trim().toLowerCase();
    if (!t) return [];
    return candidates.filter((c) => !c.is_compound && c.item_id !== itemId && !inList.has(c.item_id) && `${c.item_number} ${c.item_name}`.toLowerCase().includes(t)).slice(0, 8);
  }, [q, candidates, itemId, inList]);

  if (!itemId) return <p className="py-4 text-sm text-muted-foreground">Save the item first, then add its components.</p>;

  return (
    <div className="space-y-3">
      <div className="relative">
        <Input value={q} disabled={disabled} onChange={(e) => setQ(e.target.value)} placeholder="Add a component: type a number or name" aria-label="Add a component" />
        {matches.length > 0 && (
          <ul className="absolute z-10 mt-1 max-h-64 w-full overflow-y-auto rounded-md border bg-popover shadow">
            {matches.map((c) => (
              <li key={c.item_id}>
                <button type="button" className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm hover:bg-muted"
                  onClick={() => { setRows((rs) => [...rs, { item_id: c.item_id, item_number: c.item_number, item_name: c.item_name, is_active: c.is_active, quantity: '1' }]); setQ(''); }}>
                  <Plus className="h-3.5 w-3.5" />{c.item_number} {c.item_name}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      <div className="overflow-x-auto rounded-md border">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left text-xs"><tr><th className="px-3 py-2">Component</th><th className="w-32 px-3 py-2 text-right">Quantity</th><th className="w-8" /></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.item_id} className="border-t">
                <td className="px-3 py-1.5">{r.item_number} {r.item_name}{!r.is_active && <span className="ml-2 text-xs text-warning">Inactive</span>}</td>
                <td className="px-3 py-1.5">
                  <Input type="number" min={0} step="any" value={r.quantity} disabled={disabled} aria-label={`Quantity of ${r.item_name}`}
                    onChange={(e) => setRows((rs) => rs.map((x) => (x.item_id === r.item_id ? { ...x, quantity: e.target.value } : x)))}
                    className={cn('h-8 text-right', qtyBad(r) && 'border-destructive')} />
                </td>
                <td className="px-1">
                  <button type="button" disabled={disabled} aria-label={`Remove ${r.item_name}`} onClick={() => setRows((rs) => rs.filter((x) => x.item_id !== r.item_id))}
                    className="rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"><Trash2 className="h-3.5 w-3.5" /></button>
                </td>
              </tr>
            ))}
            {rows.length === 0 && <tr><td colSpan={3} className="px-3 py-4 text-muted-foreground">No components yet. Search above to add one.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  );
});
