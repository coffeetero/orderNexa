'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { CheckSquare, ChevronDown, Square, Wheat } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel,
  AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';

const DEFAULT_CODES = ['MORNING', 'LUNCH', 'DINNER'];
const LABEL_CLASS = 'text-xs font-semibold text-muted-foreground tracking-wide text-center';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Candidate {
  customer_id:     number;
  customer_number: string;
  customer_name:   string;
  production_code: string;
  already_posted:  boolean;
  is_context_only?: boolean; // parent injected for display only — not postable
  // set after posting
  status?:       'POSTED' | 'FAILED';
  order_number?: string;
  message?:      string;
}

interface PostStandingOrdersPageProps {
  initialTenantId: number | null;
  defaultDate:     string;
}

const STATUS_LABEL: Record<string, string> = {
  POSTED: '✓ Posted',
  FAILED: '✗ Failed',
};
const STATUS_CLASS: Record<string, string> = {
  POSTED: 'text-emerald-600 dark:text-emerald-400',
  FAILED: 'text-destructive',
};

// ── Component ─────────────────────────────────────────────────────────────────

export function PostStandingOrdersPage({ initialTenantId, defaultDate }: PostStandingOrdersPageProps) {
  const tenantId = initialTenantId;

  // Filters
  const [productionDate, setProductionDate] = useState(defaultDate);
  const [selectedCodes, setSelectedCodes] = useState<string[]>(DEFAULT_CODES);

  // Hierarchy lookup: full customer data keyed by customer_id
  const hierarchyRef = useRef<Map<number, {
    level: number; sort_path: string; customer_type: string;
    customer_parent_id: number | null;
    customer_name: string; customer_number: string | null;
  }>>(new Map());

  // Grid state
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [checked,    setChecked]    = useState<Set<string>>(new Set()); // key = customer_id|code
  const [isLoading,  setIsLoading]  = useState(false);
  const [isPosting,  setIsPosting]  = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [posted, setPosted] = useState(false);

  const abortRef = useRef<AbortController | null>(null);

  // ── Load candidates ────────────────────────────────────────────────────────

  const load = useCallback(async (date: string, codes: string[]) => {
    if (!tenantId || !date || codes.length === 0) {
      setCandidates([]); setChecked(new Set()); return;
    }
    abortRef.current?.abort();
    abortRef.current = new AbortController();
    setIsLoading(true);
    setCandidates([]); setChecked(new Set()); setPosted(false);
    try {
      const params = new URLSearchParams({
        tenant_id:        String(tenantId),
        production_date:  date,
        production_codes: codes.join(','),
      });
      const res  = await fetch(`/api/post-standing-orders?${params}`, { signal: abortRef.current.signal });
      const json = await res.json() as { data?: Candidate[]; availableCodes?: string[]; error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not load.'); return; }

      const rows = json.data ?? [];
      setCandidates(rows);
      // Pre-check all non-posted candidates
      setChecked(new Set(rows.filter(r => !r.already_posted).map(r => rowKey(r))));
    } catch (err) {
      if ((err as Error).name !== 'AbortError') toast.error('Failed to load candidates.');
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  // Initial load: hierarchy first (sequential) so context rows inject on first render
  useEffect(() => {
    if (!tenantId) return;
    (async () => {
      // 1. Load hierarchy
      const hRes  = await fetch(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`);
      const hJson = await hRes.json() as { data?: { customer_id: number; level: number; sort_path: string; customer_type: string; customer_parent_id: number | null; customer_name: string; customer_number: string | null }[] };
      const map   = new Map<number, { level: number; sort_path: string; customer_type: string; customer_parent_id: number | null; customer_name: string; customer_number: string | null }>();
      (hJson.data ?? []).forEach(c => map.set(c.customer_id, {
        level: c.level ?? 0, sort_path: c.sort_path ?? '',
        customer_type: c.customer_type ?? '',
        customer_parent_id: c.customer_parent_id ?? null,
        customer_name: c.customer_name ?? '', customer_number: c.customer_number ?? null,
      }));
      hierarchyRef.current = map;

      // 2. Load candidates with defaults
      const params = new URLSearchParams({
        tenant_id:        String(tenantId),
        production_date:  productionDate,
        production_codes: selectedCodes.join(','),
      });
      const cRes  = await fetch(`/api/post-standing-orders?${params}`);
      const cJson = await cRes.json() as { data?: Candidate[] };
      const rows  = cJson.data ?? [];
      setCandidates(rows);
      setChecked(new Set(rows.filter(r => !r.already_posted).map(r => rowKey(r))));
    })().catch(() => {});
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId]);

  // Auto-retrieve when date or codes change (after initial load)
  const isFirstLoad = useRef(true);
  useEffect(() => {
    if (isFirstLoad.current) { isFirstLoad.current = false; return; }
    void load(productionDate, selectedCodes);
  }, [productionDate, selectedCodes, load]);

  // ── Helpers ────────────────────────────────────────────────────────────────

  const rowKey = (r: Pick<Candidate, 'customer_id' | 'production_code'>) =>
    `${r.customer_id}|${r.production_code}`;

  const postable = candidates.filter(r => !r.already_posted && !r.is_context_only);
  const numChecked = postable.filter(r => checked.has(rowKey(r))).length;
  const numAlready = candidates.filter(r => r.already_posted).length;

  // ── Post ──────────────────────────────────────────────────────────────────

  const doPost = async () => {
    setShowConfirm(false);
    if (!tenantId) return;
    setIsPosting(true);

    const orders = postable
      .filter(r => checked.has(rowKey(r)))
      .map(r => ({ customer_id: r.customer_id, production_date: productionDate, production_code: r.production_code }));

    try {
      const res  = await fetch('/api/post-standing-orders', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, orders }),
      });
      const json = await res.json() as {
        results?: { customer_id: number; production_code: string; status: string; order_number?: string; message?: string }[];
        summary?: { posted: number; failed: number };
        error?: string;
      };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Post failed.'); return; }

      // Merge status back into candidates
      const resultMap = new Map(
        (json.results ?? []).map(r => [`${r.customer_id}|${r.production_code}`, r])
      );
      setCandidates(prev => prev.map(c => {
        const r = resultMap.get(rowKey(c));
        if (!r) return c;
        return { ...c, status: r.status as 'POSTED' | 'FAILED', order_number: r.order_number, message: r.message };
      }));

      const { posted: p = 0, failed: f = 0 } = json.summary ?? {};
      if (f === 0) toast.success(`${p} order${p !== 1 ? 's' : ''} posted.`);
      else toast.warning(`${p} posted · ${f} failed`);
      setPosted(true);
    } finally {
      setIsPosting(false);
    }
  };

  // ── Grouped grid ──────────────────────────────────────────────────────────

  const grouped = DEFAULT_CODES
    .filter(c => selectedCodes.includes(c))
    .map(code => {
      const groupRows = candidates.filter(r => r.production_code === code);
      const groupIds  = new Set(groupRows.map(r => r.customer_id));
      const ctx: Candidate[] = [];

      // Recursively inject missing ancestors for display context
      const addAncestors = (customerId: number) => {
        const h = hierarchyRef.current.get(customerId);
        if (!h?.customer_parent_id) return;
        const parentId = h.customer_parent_id;
        if (groupIds.has(parentId)) return;
        const ph = hierarchyRef.current.get(parentId);
        if (!ph) return;
        groupIds.add(parentId);
        ctx.push({
          customer_id:     parentId,
          customer_number: ph.customer_number ?? '',
          customer_name:   ph.customer_name,
          production_code: code,
          already_posted:  false,
          is_context_only: true,
        });
        addAncestors(parentId); // walk up further if needed
      };

      groupRows.forEach(r => addAncestors(r.customer_id));

      const allRows = [...groupRows, ...ctx].sort((a, b) => {
        const sa = hierarchyRef.current.get(a.customer_id)?.sort_path ?? a.customer_number;
        const sb = hierarchyRef.current.get(b.customer_id)?.sort_path ?? b.customer_number;
        return sa.localeCompare(sb);
      });

      return { code, rows: allRows };
    })
    .filter(g => g.rows.length > 0);

  const dowLabel = (() => {
    const d = new Date(productionDate + 'T00:00:00');
    return d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
  })();

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="mx-auto w-fit space-y-4 p-4">

      {/* Filter row */}
      <div className="flex flex-wrap items-end gap-4 rounded-lg border border-border/60 bg-card px-4 py-3">
        {/* Production Date */}
        <div className="flex flex-col gap-1">
          <Label className={LABEL_CLASS}>Production Date</Label>
          <input
            type="date"
            value={productionDate}
            onChange={e => setProductionDate(e.target.value)}
            className="h-9 rounded-md border border-input bg-background px-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
          />
        </div>

        {/* Production Time multi-select dropdown */}
        <div className="flex flex-col gap-1">
          <Label className={LABEL_CLASS}>Production Time</Label>
          <Popover>
            <PopoverTrigger asChild>
              <button className="flex h-9 min-w-[180px] items-center justify-between rounded-md border border-input bg-background px-3 text-sm hover:bg-muted/50 focus:outline-none focus:ring-2 focus:ring-primary">
                <span className="truncate">
                  {selectedCodes.length === 0
                    ? 'None selected'
                    : selectedCodes.length === DEFAULT_CODES.length
                    ? 'All'
                    : selectedCodes.map(c => c.charAt(0) + c.slice(1).toLowerCase()).join(', ')}
                </span>
                <ChevronDown className="ml-2 h-4 w-4 shrink-0 text-muted-foreground" />
              </button>
            </PopoverTrigger>
            <PopoverContent className="w-48 p-1.5" align="start">
              {DEFAULT_CODES.map(code => (
                <label key={code} className="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-muted select-none">
                  <Checkbox
                    checked={selectedCodes.includes(code)}
                    onCheckedChange={v =>
                      setSelectedCodes(prev =>
                        v ? [...prev, code] : prev.filter(c => c !== code)
                      )
                    }
                  />
                  {code.charAt(0) + code.slice(1).toLowerCase()}
                </label>
              ))}
            </PopoverContent>
          </Popover>
        </div>

        {/* Actions */}
        <div className="flex items-end gap-2 pb-0.5">
          <Button variant="outline" size="sm"
            onClick={() => setChecked(new Set())}
            disabled={isLoading || isPosting || numChecked === 0}>
            <Square className="mr-1.5 h-3.5 w-3.5" />Clear All
          </Button>
          <Button variant="outline" size="sm"
            onClick={() => setChecked(new Set(postable.map(rowKey)))}
            disabled={isLoading || isPosting || postable.length === 0}>
            <CheckSquare className="mr-1.5 h-3.5 w-3.5" />Select All
          </Button>
          <Button size="sm"
            disabled={isLoading || isPosting || numChecked === 0 || posted}
            onClick={() => setShowConfirm(true)}>
            {isPosting ? 'Posting…' : `Post (${numChecked})`}
          </Button>
        </div>
      </div>

      {/* Grid */}
      <div className="rounded-lg border border-border/60 overflow-hidden">
        {isLoading && (
          <div className="flex items-center justify-center py-10">
            <Wheat className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        )}

        {!isLoading && candidates.length === 0 && (
          <p className="px-4 py-8 text-center text-sm text-muted-foreground">
            No standing order customers found for the selected date and codes.
          </p>
        )}

        {!isLoading && grouped.map(({ code, rows }) => (
          <div key={code}>
            {/* Group header */}
            <div className="bg-emerald-100 dark:bg-emerald-950/50 px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-emerald-800 dark:text-emerald-300 border-b border-emerald-200 dark:border-emerald-800">
              {code.charAt(0) + code.slice(1).toLowerCase()}
            </div>

            {/* Column headers */}
            <div className="grid border-b border-border/60 bg-muted/20 px-3 py-1.5 text-xs font-semibold text-muted-foreground"
              style={{ gridTemplateColumns: '1fr 140px 36px' }}>
              <span>Customer</span>
              <span />
              <span />
            </div>

            {rows.map(row => {
              const key       = rowKey(row);
              const isChecked = checked.has(key);
              const canCheck  = !row.already_posted && !row.is_context_only && !posted;

              return (
                <div key={key}
                  className={cn(
                    'grid items-center border-b border-border/40 px-3 py-1.5 transition-colors',
                    row.already_posted ? 'opacity-50' : 'hover:bg-muted/20',
                    isChecked && !row.already_posted ? 'bg-primary/5' : '',
                  )}
                  style={{ gridTemplateColumns: '1fr 140px 36px' }}
                >
                  {(() => {
                    const h     = hierarchyRef.current.get(row.customer_id);
                    const level = h?.level ?? 0;
                    const type  = (h?.customer_type ?? '').toUpperCase();
                    const nameClass = type === 'DEPARTMENT' ? 'text-foreground/50' : 'text-foreground';
                    const label = row.customer_number
                      ? `${row.customer_number} - ${row.customer_name}`
                      : row.customer_name;
                    return (
                      <span className={cn('truncate text-sm', nameClass)}
                        style={{ paddingLeft: level * 12 }}>
                        {label}
                      </span>
                    );
                  })()}
                  <span className={cn('text-xs', row.status ? STATUS_CLASS[row.status] : 'text-muted-foreground/60')}>
                    {row.status
                      ? `${STATUS_LABEL[row.status]}${row.order_number ? ` #${row.order_number}` : ''}${row.message ? ` — ${row.message}` : ''}`
                      : row.already_posted ? '— Already posted' : ''}
                  </span>
                  {row.is_context_only ? (
                    <div />
                  ) : (
                    <div className="flex items-center justify-center">
                      <Checkbox
                        checked={isChecked}
                        disabled={!canCheck}
                        onCheckedChange={v => {
                          setChecked(prev => {
                            const next = new Set(prev);
                            if (v) next.add(key); else next.delete(key);
                            return next;
                          });
                        }}
                      />
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        ))}

        {!isLoading && candidates.length > 0 && (
          <div className="flex items-center justify-between border-t border-border/60 bg-muted/20 px-4 py-2 text-xs text-muted-foreground">
            <span>{candidates.length} customer{candidates.length !== 1 ? 's' : ''}</span>
            {numAlready > 0 && <span>{numAlready} already posted</span>}
            <span>{numChecked} selected</span>
          </div>
        )}
      </div>

      {/* Confirm dialog */}
      <AlertDialog open={showConfirm} onOpenChange={setShowConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Post Standing Orders</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-1 text-sm">
                <p>Post standing orders for <strong>{dowLabel}</strong>?</p>
                <p><strong>{numChecked}</strong> customer{numChecked !== 1 ? 's' : ''} selected.</p>
                {numAlready > 0 && (
                  <p className="text-muted-foreground">{numAlready} already posted will be skipped.</p>
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={doPost}>Post Orders</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
