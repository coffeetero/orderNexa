'use client';

import { useState, useEffect, useCallback, useRef, forwardRef, useImperativeHandle } from 'react';
import { Trash2, Plus, ChevronDown, GripVertical } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { cn } from '@/lib/utils';

const ASSIGNMENT_TYPES = ['Default', 'Seasonal', 'Promotional', 'Introductory'] as const;
const STATUSES = ['Draft', 'Pending Approval', 'Scheduled', 'Expired', 'Archived'] as const;

interface Pricebook { pricebook_id: number; pricebook_name: string; }

interface AssignmentRow {
  _key: string;
  customer_pricebook_id: number | null;
  pricebook_id: number | null;
  pricebook_name: string;
  assignment_type: string;
  status: string;
  effective_start_date: string;
  effective_end_date: string;
  is_active: boolean;
  precedence: number;
}

export interface CustomerPricebooksTabHandle {
  save: () => Promise<void>;
  cancel: () => void;
}

interface CustomerPricebooksTabProps {
  tenantId: number;
  customerId: number | null;
  onDirtyChange: (dirty: boolean) => void;
}

let _seq = 0;
const genKey = () => `r${++_seq}`;

function emptyRow(): AssignmentRow {
  return {
    _key: genKey(), customer_pricebook_id: null,
    pricebook_id: null, pricebook_name: '',
    assignment_type: 'Default', status: 'Draft',
    effective_start_date: '', effective_end_date: '',
    is_active: true, precedence: 0,
  };
}

function fromRaw(r: Record<string, unknown>): AssignmentRow {
  return {
    _key:                  genKey(),
    customer_pricebook_id: r.customer_pricebook_id as number,
    pricebook_id:          r.pricebook_id as number,
    pricebook_name:        r.pricebook_name as string,
    assignment_type:       r.assignment_type as string,
    status:                r.status as string,
    effective_start_date:  (r.effective_start_date as string) ?? '',
    effective_end_date:    (r.effective_end_date as string) ?? '',
    is_active:             r.is_active as boolean,
    precedence:            (r.precedence as number) ?? 0,
  };
}

function PricebookCell({
  pricebooks, value, name, onChange,
}: {
  pricebooks: Pricebook[];
  value: number | null;
  name: string;
  onChange: (id: number, name: string) => void;
}) {
  const [open, setOpen]                           = useState(false);
  const [search, setSearch]                       = useState('');
  const [dropdownRect, setDropdownRect]           = useState<DOMRect | null>(null);
  const triggerRef                                = useRef<HTMLButtonElement>(null);
  const inputRef                                  = useRef<HTMLInputElement>(null);
  const listRef                                   = useRef<HTMLDivElement>(null);

  const openDropdown = () => {
    if (triggerRef.current) setDropdownRect(triggerRef.current.getBoundingClientRect());
    setSearch('');
    setOpen(true);
  };

  useEffect(() => {
    if (!open) return;
    const handlePointer = (e: MouseEvent) => {
      if (
        !triggerRef.current?.contains(e.target as Node) &&
        !inputRef.current?.contains(e.target as Node) &&
        !listRef.current?.contains(e.target as Node)
      ) setOpen(false);
    };
    document.addEventListener('mousedown', handlePointer);
    return () => document.removeEventListener('mousedown', handlePointer);
  }, [open]);

  const filtered = pricebooks.filter((pb) =>
    pb.pricebook_name.toLowerCase().includes(search.toLowerCase())
  );

  const ITEM_HEIGHT = 32;
  const MAX_ITEMS   = 10;
  const listHeight  = Math.min(filtered.length, MAX_ITEMS) * ITEM_HEIGHT;

  return (
    <div className="relative w-full">
      {open ? (
        <input
          ref={inputRef}
          autoFocus
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search…"
          className="w-full rounded border border-input bg-background px-2 py-1 text-sm focus:outline-none"
        />
      ) : (
        <button
          ref={triggerRef}
          type="button"
          onClick={openDropdown}
          className="flex w-full items-center justify-between rounded border border-input bg-background px-2 py-1 text-sm hover:bg-muted/50"
        >
          <span className={cn(!name && 'text-muted-foreground')}>{name || 'Select…'}</span>
          <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
        </button>
      )}
      {open && filtered.length > 0 && dropdownRect && (
        <div
          ref={listRef}
          style={{
            position: 'fixed',
            top:    dropdownRect.bottom + 2,
            left:   dropdownRect.left,
            width:  Math.max(dropdownRect.width, 220),
            height: listHeight,
            zIndex: 9999,
          }}
          className="overflow-y-auto rounded-md border border-border bg-popover shadow-md"
        >
          {filtered.map((pb) => (
            <button
              key={pb.pricebook_id}
              type="button"
              onMouseDown={(e) => {
                e.preventDefault();
                onChange(pb.pricebook_id, pb.pricebook_name);
                setOpen(false);
                setSearch('');
              }}
              className={cn(
                'w-full px-3 py-1.5 text-left text-sm hover:bg-muted',
                pb.pricebook_id === value && 'bg-muted font-medium',
              )}
            >
              {pb.pricebook_name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export const CustomerPricebooksTab = forwardRef<CustomerPricebooksTabHandle, CustomerPricebooksTabProps>(
  function CustomerPricebooksTab({ tenantId, customerId, onDirtyChange }, ref) {
    const [rows, setRows]             = useState<AssignmentRow[]>([]);
    const [original, setOriginal]     = useState<AssignmentRow[]>([]);
    const [pricebooks, setPricebooks] = useState<Pricebook[]>([]);
    const [isLoading, setIsLoading]   = useState(false);
    const [isSaving, setIsSaving]     = useState(false);
    const [draggingKey, setDraggingKey] = useState<string | null>(null);
    const [dragOverKey, setDragOverKey] = useState<string | null>(null);
    const loadedId                    = useRef<number | null | undefined>(undefined);

    const isDirty = JSON.stringify(rows) !== JSON.stringify(original);

    useEffect(() => { onDirtyChange(isDirty); }, [isDirty, onDirtyChange]);

    useEffect(() => {
      fetch(`/api/customers/pricebooks?tenant_id=${tenantId}`)
        .then((r) => r.json() as Promise<{ data?: { pricebooks: Pricebook[] }; error?: string }>)
        .then((json) => { if (json.data?.pricebooks) setPricebooks(json.data.pricebooks); })
        .catch(() => {});
    }, [tenantId]);

    const load = useCallback(async () => {
      if (!customerId) return;
      setIsLoading(true);
      try {
        const res  = await fetch(`/api/customers/pricebooks?tenant_id=${tenantId}&customer_id=${customerId}`);
        const json = await res.json() as { data?: { assignments: unknown[]; pricebooks: Pricebook[] }; error?: string };
        if (!res.ok || json.error) { toast.error(json.error ?? 'Could not load pricebooks.', { duration: Infinity }); return; }
        const loaded = (json.data?.assignments ?? []).map((r) => fromRaw(r as Record<string, unknown>));
        setRows(loaded);
        setOriginal(loaded);
        loadedId.current = customerId;
      } finally {
        setIsLoading(false);
      }
    }, [tenantId, customerId]);

    useEffect(() => {
      if (customerId !== loadedId.current) load();
    }, [customerId, load]);

    const setField = (key: string, field: keyof AssignmentRow, value: unknown) =>
      setRows((prev) => prev.map((r) => r._key === key ? { ...r, [field]: value } : r));

    const handleDragStart = (key: string) => setDraggingKey(key);
    const handleDragOver  = (e: React.DragEvent, key: string) => {
      e.preventDefault();
      if (key !== draggingKey) setDragOverKey(key);
    };
    const handleDrop = (key: string) => {
      if (!draggingKey || draggingKey === key) return;
      setRows((prev) => {
        const from = prev.findIndex((r) => r._key === draggingKey);
        const to   = prev.findIndex((r) => r._key === key);
        if (from === -1 || to === -1) return prev;
        const next = [...prev];
        const [moved] = next.splice(from, 1);
        next.splice(to, 0, moved);
        return next;
      });
      setDraggingKey(null);
      setDragOverKey(null);
    };
    const handleDragEnd = () => { setDraggingKey(null); setDragOverKey(null); };

    const save = useCallback(async () => {
      if (!customerId) return;
      const invalid = rows.find((r) => !r.pricebook_id || !r.effective_start_date);
      if (invalid) { toast.error('Each row needs a pricebook and a start date.'); return; }

      setIsSaving(true);
      try {
        const res  = await fetch('/api/customers/pricebooks', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ tenant_id: tenantId, customer_id: customerId, entries: rows.map((r, i) => ({ ...r, precedence: i + 1 })) }),
        });
        const json = await res.json() as { data?: unknown; error?: string };
        if (!res.ok || json.error) { toast.error(json.error ?? 'Could not save.', { duration: Infinity }); return; }
        await load();
        toast.success('Pricebook assignments saved.');
      } finally {
        setIsSaving(false);
      }
    }, [customerId, rows, load, tenantId]);

    const cancel = useCallback(() => {
      setRows(original);
    }, [original]);

    useImperativeHandle(ref, () => ({ save, cancel }), [save, cancel]);

    const addRow = () => setRows((prev) => [...prev, emptyRow()]);
    const removeRow = (key: string) => setRows((prev) => prev.filter((r) => r._key !== key));

    if (!customerId) {
      return <p className="py-4 text-sm text-muted-foreground">Select a customer to manage pricebooks.</p>;
    }

    return (
      <div className="space-y-3">
        {/* Tab header */}
        <div className="flex flex-wrap justify-end items-center gap-2">
          <Button type="button" variant="ghost" size="sm" onClick={addRow} className="h-7 gap-1 text-xs">
            <Plus className="h-3.5 w-3.5" />Pricebook
          </Button>
          <Button type="button" variant="outline" size="sm" onClick={cancel} disabled={!isDirty} className="h-7">
            Cancel
          </Button>
          <Button type="button" size="sm" onClick={save} disabled={isSaving || !isDirty} className="h-7">
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
        </div>

        {/* Grid */}
        {isLoading ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : (
          <div className="overflow-x-auto rounded-md border border-border/60" style={{ minHeight: '420px' }}>
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border/60 bg-muted/40">
                  <th className="w-6" />
                  <th className="px-3 py-2 text-left font-medium text-muted-foreground">Pricing Book</th>
                  <th className="px-3 py-2 text-left font-medium text-muted-foreground whitespace-nowrap">From Date</th>
                  <th className="px-3 py-2 text-left font-medium text-muted-foreground whitespace-nowrap">End Date</th>
                  <th className="px-3 py-2 text-center font-medium text-muted-foreground">Active</th>
                  <th className="px-3 py-2 text-left font-medium text-muted-foreground">Type</th>
                  <th className="px-3 py-2 text-left font-medium text-muted-foreground">Status</th>
                  <th className="w-8" />
                </tr>
              </thead>
              <tbody>
                {rows.length === 0 && (
                  <tr>
                    <td colSpan={8} className="px-3 py-6 text-center text-muted-foreground">
                      No assignments — click + Pricebook to add one.
                    </td>
                  </tr>
                )}
                {rows.map((row) => (
                  <tr
                    key={row._key}
                    draggable
                    onDragStart={() => handleDragStart(row._key)}
                    onDragOver={(e) => handleDragOver(e, row._key)}
                    onDrop={() => handleDrop(row._key)}
                    onDragEnd={handleDragEnd}
                    className={cn(
                      'border-b border-border/40 last:border-0',
                      draggingKey === row._key ? 'opacity-40' : 'hover:bg-muted/20',
                      dragOverKey === row._key && draggingKey !== row._key && 'border-t-2 border-t-primary',
                    )}
                  >
                    <td className="pl-1 py-1.5 cursor-grab text-muted-foreground/50 hover:text-muted-foreground">
                      <GripVertical className="h-3.5 w-3.5" />
                    </td>
                    <td className="px-3 py-1.5 min-w-[180px]">
                      <PricebookCell
                        pricebooks={pricebooks}
                        value={row.pricebook_id}
                        name={row.pricebook_name}
                        onChange={(id, name) => setRows((prev) =>
                          prev.map((r) => r._key === row._key ? { ...r, pricebook_id: id, pricebook_name: name } : r)
                        )}
                      />
                    </td>
                    <td className="px-3 py-1.5">
                      <input
                        type="date"
                        value={row.effective_start_date}
                        onChange={(e) => setField(row._key, 'effective_start_date', e.target.value)}
                        className="rounded border border-input bg-background px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </td>
                    <td className="px-3 py-1.5">
                      <input
                        type="date"
                        value={row.effective_end_date}
                        onChange={(e) => setField(row._key, 'effective_end_date', e.target.value)}
                        className="rounded border border-input bg-background px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
                      />
                    </td>
                    <td className="px-3 py-1.5 text-center">
                      <Checkbox
                        checked={row.is_active}
                        onCheckedChange={(v) => setField(row._key, 'is_active', !!v)}
                      />
                    </td>
                    <td className="px-3 py-1.5">
                      <select
                        value={row.assignment_type}
                        onChange={(e) => setField(row._key, 'assignment_type', e.target.value)}
                        className="rounded border border-input bg-background px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
                      >
                        {ASSIGNMENT_TYPES.map((t) => <option key={t}>{t}</option>)}
                      </select>
                    </td>
                    <td className="px-3 py-1.5">
                      <select
                        value={row.status}
                        onChange={(e) => setField(row._key, 'status', e.target.value)}
                        className="rounded border border-input bg-background px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
                      >
                        {STATUSES.map((s) => <option key={s}>{s}</option>)}
                      </select>
                    </td>
                    <td className="px-1 py-1.5">
                      {row.customer_pricebook_id === null && (
                        <button
                          type="button"
                          onClick={() => removeRow(row._key)}
                          className="rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    );
  }
);
