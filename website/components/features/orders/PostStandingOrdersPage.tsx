'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { localDateIso } from '@/lib/date';
import { CheckSquare, ChevronDown, RotateCcw, Square, Wheat } from 'lucide-react';
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

const DEFAULT_CODES = [
  { value: 'MORNING',  label: 'AM'        },
  { value: 'LUNCH',    label: 'PM'        },
  { value: 'DINNER',   label: 'PM2'       },
  { value: 'SPECIAL1', label: 'Special 1' },
  { value: 'SPECIAL2', label: 'Special 2' },
];
const LABEL_CLASS = 'text-xs font-semibold text-muted-foreground tracking-wide text-center';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Candidate {
  production_date: string;
  customer_id:     number;
  customer_number: string;
  customer_name:   string;
  production_code: string;
  /** NEW | POSTED (posting again only adds missing items) | POSTED_TO_AR | ORDER_DELETED (both left alone) */
  status:          string;
  already_posted:  boolean;
  order_number?:   string | null;
  is_context_only?: boolean; // parent injected for display only — not postable
  // set after posting
  result?:       string;
  lines_added?:  number;
  message?:      string | null;
}

interface PostStandingOrdersPageProps {
  initialTenantId: number | null;
  defaultDate:     string;
}

// Before posting (from the list)
const STATUS_LABEL: Record<string, string> = {
  POSTED:        'Posted',
  POSTED_TO_AR:  'Posted to AR',
  ORDER_DELETED: 'Posted, order deleted',
};
// After posting (from the post results)
const RESULT_LABEL: Record<string, string> = {
  POSTED:        '✓ Posted',
  ADDED:         '✓ Added',
  UP_TO_DATE:    'Up to date',
  POSTED_TO_AR:  'Posted to AR, left alone',
  ORDER_DELETED: 'Order deleted, left alone',
  FAILED:        '✗ Failed',
};
const RESULT_CLASS: Record<string, string> = {
  POSTED: 'text-success',
  ADDED:  'text-success',
  FAILED: 'text-destructive',
};
/** NEW rows can be posted; POSTED rows can be posted again (adds only missing items). */
const canPost = (r: Candidate) => !r.is_context_only && (r.status === 'NEW' || r.status === 'POSTED');

// ── Component ─────────────────────────────────────────────────────────────────

export function PostStandingOrdersPage({ initialTenantId, defaultDate }: PostStandingOrdersPageProps) {
  const tenantId = initialTenantId;

  // Filters
  const [productionDate, setProductionDate] = useState(defaultDate);
  const [productionDateTo, setProductionDateTo] = useState(defaultDate);
  const [availableCodes, setAvailableCodes] = useState(DEFAULT_CODES);
  const [selectedCodes, setSelectedCodes]  = useState<string[]>(DEFAULT_CODES.map(c => c.value));

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

  const load = useCallback(async (date: string, dateTo: string, codes: string[]) => {
    if (!tenantId || !date || codes.length === 0) {
      setCandidates([]); setChecked(new Set()); return;
    }
    abortRef.current?.abort();
    abortRef.current = new AbortController();
    setIsLoading(true);
    setCandidates([]); setChecked(new Set()); setPosted(false);
    try {
      const params = new URLSearchParams({
        tenant_id:          String(tenantId),
        production_date:    date,
        production_date_to: dateTo || date,
        production_codes:   codes.join(','),
      });
      const res  = await fetch(`/api/post-standing-orders?${params}`, { signal: abortRef.current.signal });
      const json = await res.json() as { data?: Candidate[]; availableCodes?: string[]; error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not load.'); return; }

      const rows = json.data ?? [];
      setCandidates(rows);
      // Pre-check all non-posted candidates
      setChecked(new Set());
    } catch (err) {
      if ((err as Error).name !== 'AbortError') toast.error('Failed to load candidates.');
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  // Load production codes from valueset
  useEffect(() => {
    if (!tenantId) return;
    fetch(`/api/valuesets?tenant_id=${tenantId}&code=PRODUCTIONCODE`)
      .then(r => r.json())
      .then((j: { data?: { value: string; label: string }[] }) => {
        const codes = j.data ?? [];
        if (codes.length > 0) {
          setAvailableCodes(codes);
          setSelectedCodes(codes.map(c => c.value));
        }
      })
      .catch(() => {});
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
        tenant_id:          String(tenantId),
        production_date:    productionDate,
        production_date_to: productionDateTo,
        production_codes:   selectedCodes.join(','),
      });
      const cRes  = await fetch(`/api/post-standing-orders?${params}`);
      const cJson = await cRes.json() as { data?: Candidate[] };
      const rows  = cJson.data ?? [];
      setCandidates(rows);
      setChecked(new Set());
    })().catch(() => {});
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId]);

  // Auto-retrieve when date or codes change (after initial load)

  // ── Helpers ────────────────────────────────────────────────────────────────

  const rowKey = (r: Pick<Candidate, 'production_date' | 'customer_id' | 'production_code'>) =>
    `${r.production_date}|${r.customer_id}|${r.production_code}`;

  const postable = candidates.filter(canPost);
  const numChecked = postable.filter(r => checked.has(rowKey(r))).length;
  const numRepost = postable.filter(r => r.status === 'POSTED' && checked.has(rowKey(r))).length;
  const numAlready = candidates.filter(r => r.already_posted).length;

  // ── Post ──────────────────────────────────────────────────────────────────

  const doPost = async () => {
    setShowConfirm(false);
    if (!tenantId) return;
    setIsPosting(true);

    const orders = postable
      .filter(r => checked.has(rowKey(r)))
      .map(r => ({ customer_id: r.customer_id, production_date: r.production_date, production_code: r.production_code }));

    try {
      const res  = await fetch('/api/post-standing-orders', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, orders, order_date: localDateIso() }),
      });
      const json = await res.json() as {
        results?: { production_date: string; customer_id: number; production_code: string; status: string; order_number?: string | null; lines_added?: number; message?: string | null }[];
        summary?: { posted: number; added: number; up_to_date: number; skipped: number; failed: number };
        error?: string;
      };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Post failed.'); return; }

      // Merge status back into candidates
      const resultMap = new Map(
        (json.results ?? []).map(r => [rowKey(r), r])
      );
      setCandidates(prev => prev.map(c => {
        const r = resultMap.get(rowKey(c));
        if (!r) return c;
        return { ...c, result: r.status, order_number: r.order_number ?? c.order_number, lines_added: r.lines_added, message: r.message };
      }));

      const { posted: p = 0, added: a = 0, failed: f = 0 } = json.summary ?? {};
      const msg = `${p} order${p !== 1 ? 's' : ''} posted${a > 0 ? ` · ${a} updated with missing items` : ''}`;
      if (f === 0) toast.success(`${msg}.`);
      else toast.warning(`${msg} · ${f} failed`);
      setPosted(true);
    } finally {
      setIsPosting(false);
    }
  };

  // ── Grouped grid ──────────────────────────────────────────────────────────

  const dates = Array.from(new Set(candidates.map(r => r.production_date))).sort();
  const grouped = dates.flatMap(date => availableCodes
    .filter(({ value }) => selectedCodes.includes(value))
    .map(({ value: code }) => {
      const groupRows = candidates.filter(r => r.production_date === date && r.production_code === code);
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
          production_date: date,
          customer_id:     parentId,
          customer_number: ph.customer_number ?? '',
          customer_name:   ph.customer_name,
          production_code: code,
          status:          'NEW',
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

      return { date, code, rows: allRows };
    })
    .filter(g => g.rows.length > 0));

  const dayLabel = (iso: string, weekday: 'long' | 'short' = 'long') =>
    new Date(iso + 'T00:00:00').toLocaleDateString('en-US', { weekday, month: weekday === 'long' ? 'long' : 'short', day: 'numeric' });
  const rangeLabel = productionDateTo && productionDateTo !== productionDate
    ? `${dayLabel(productionDate)} to ${dayLabel(productionDateTo)}`
    : dayLabel(productionDate);

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
            onChange={e => {
              const v = e.target.value;
              setProductionDate(v);
              if (!productionDateTo || productionDateTo < v) setProductionDateTo(v);
            }}
            className="h-9 rounded-md border border-input bg-background px-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary"
          />
        </div>

        {/* To date: post several days at once (e.g. Thursday for Friday to Sunday) */}
        <div className="flex flex-col gap-1">
          <Label className={LABEL_CLASS}>To</Label>
          <input
            type="date"
            value={productionDateTo}
            min={productionDate}
            onChange={e => setProductionDateTo(e.target.value)}
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
                    : selectedCodes.length === availableCodes.length
                    ? 'All'
                    : selectedCodes
                        .map(c => availableCodes.find(a => a.value === c)?.label ?? c)
                        .join(', ')}
                </span>
                <ChevronDown className="ml-2 h-4 w-4 shrink-0 text-muted-foreground" />
              </button>
            </PopoverTrigger>
            <PopoverContent className="w-48 p-1.5" align="start">
              {availableCodes.map(({ value: code, label: codeLabel }) => (
                <label key={code} className="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-muted select-none">
                  <Checkbox
                    checked={selectedCodes.includes(code)}
                    onCheckedChange={v =>
                      setSelectedCodes(prev =>
                        v ? [...prev, code] : prev.filter(c => c !== code)
                      )
                    }
                  />
                  {codeLabel}
                </label>
              ))}
            </PopoverContent>
          </Popover>
        </div>

        {/* Actions */}
        <div className="flex items-end gap-2 pb-0.5">
          <Button variant="outline" size="icon" className="h-9 w-9"
            title="Retrieve"
            disabled={isLoading || isPosting || selectedCodes.length === 0}
            onClick={() => void load(productionDate, productionDateTo, selectedCodes)}>
            <RotateCcw className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm"
            onClick={() => setChecked(new Set())}
            disabled={isLoading || isPosting || numChecked === 0}>
            <Square className="mr-1.5 h-3.5 w-3.5" />Clear All
          </Button>
          <Button variant="outline" size="sm"
            onClick={() => setChecked(new Set(postable.filter(r => r.status === 'NEW').map(rowKey)))}
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

        {!isLoading && grouped.map(({ date, code, rows }) => (
          <div key={`${date}|${code}`}>
            {/* Group header */}
            <div className="bg-success-soft px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-success border-b border-success/40">
              {dates.length > 1 ? `${dayLabel(date, 'short')} · ` : ''}{availableCodes.find(c => c.value === code)?.label ?? code}
            </div>

            {/* Column headers */}
            <div className="grid border-b border-border/60 bg-muted/20 px-3 py-1.5 text-xs font-semibold text-muted-foreground"
              style={{ gridTemplateColumns: '1fr 220px 36px' }}>
              <span>Customer</span>
              <span />
              <span />
            </div>

            {rows.map(row => {
              const key       = rowKey(row);
              const isChecked = checked.has(key);
              const canCheck  = canPost(row) && !posted;

              return (
                <div key={key}
                  className={cn(
                    'grid items-center border-b border-border/40 px-3 py-1.5 transition-colors',
                    row.already_posted && !isChecked ? 'opacity-50' : 'hover:bg-muted/20',
                    isChecked ? 'bg-primary/5' : '',
                  )}
                  style={{ gridTemplateColumns: '1fr 220px 36px' }}
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
                  <span className={cn('truncate text-xs', row.result ? RESULT_CLASS[row.result] ?? 'text-muted-foreground' : 'text-muted-foreground/60')}
                    title={row.message ?? undefined}>
                    {row.is_context_only ? '' : row.result
                      ? `${RESULT_LABEL[row.result] ?? row.result}${row.result === 'ADDED' && row.lines_added ? ` ${row.lines_added}` : ''}${row.order_number ? ` #${row.order_number}` : ''}${row.message ? ` — ${row.message}` : ''}`
                      : STATUS_LABEL[row.status]
                        ? `${STATUS_LABEL[row.status]}${row.order_number ? ` #${row.order_number}` : ''}`
                        : ''}
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
            <span>{candidates.length} standing order{candidates.length !== 1 ? 's' : ''}</span>
            {numAlready > 0 && <span>{numAlready} already posted (check one to add missing items)</span>}
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
                <p>Post standing orders for <strong>{rangeLabel}</strong>?</p>
                <p><strong>{numChecked}</strong> selected.</p>
                {numRepost > 0 && (
                  <p className="text-muted-foreground">{numRepost} already posted: only standing order items missing from the order are added; quantities already entered are not changed.</p>
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
