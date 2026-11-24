'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface CodeRow {
  production_code: string;
  label: string;
  cutoff_time: string | null;
  cutoff_days_before: number | null;
  delivery_days_after: number | null;
  is_active: boolean | null;
}
interface MethodRow {
  delivery_method_code: string;
  delivery_method_name: string;
  is_own_fleet: boolean;
  requires_tracking: boolean;
  is_active: boolean;
}
interface SequenceRow {
  sequence_name: string;
  label: string;
  is_configured: boolean;
  mask: string;
  start_value: number;
  next_value: number;
  increment_by: number;
  reset_period: string;
  requires_gapless: boolean;
}
interface RunRow {
  production_run_id: number;
  production_date: string;
  production_code: string;
  delivery_date: string;
  cutoff_local: string;
  time_zone: string;
  run_status: string;
  order_count: number;
}

type Notify = (text: string, type: 'success' | 'error') => void;

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const json = (await res.json()) as { data?: T; error?: string };
  if (!res.ok || json.error) throw new Error(json.error ?? 'Request failed');
  return json.data as T;
}

const post = (url: string, body: unknown) =>
  call<unknown>(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

type CodeDraft = { time: string; before: string; after: string; active: boolean };
const toDraft = (r: CodeRow): CodeDraft => ({
  time: r.cutoff_time ?? '', before: String(r.cutoff_days_before ?? 1),
  after: String(r.delivery_days_after ?? 1), active: r.is_active ?? true,
});

function CodesEditor({ rows, tenantId, notify }: { rows: CodeRow[]; tenantId: number; notify: Notify }) {
  const [drafts, setDrafts] = useState<Record<string, CodeDraft>>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setDrafts(Object.fromEntries(rows.map((r) => [r.production_code, toDraft(r)])));
  }, [rows]);

  const set = (code: string, patch: Partial<CodeDraft>) =>
    setDrafts((d) => ({ ...d, [code]: { ...d[code], ...patch } }));

  const save = async () => {
    setBusy(true);
    try {
      for (const r of rows) {
        const d = drafts[r.production_code];
        if (!d) continue;
        await post('/api/admin/production-codes', {
          tenant_id: tenantId, production_code: r.production_code, cutoff_time: d.time,
          cutoff_days_before: Number(d.before), delivery_days_after: Number(d.after), is_active: d.active,
        });
      }
      notify('Production codes saved.', 'success');
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  const incomplete = rows.some((r) => !drafts[r.production_code]?.time);

  return (
    <>
      <div className="mb-1 flex items-start justify-between gap-3">
        <h2 className="text-lg font-medium">Production codes</h2>
        <Button size="sm" onClick={save} disabled={busy || incomplete}>Save</Button>
      </div>
      <p className="mb-2 text-xs text-muted-foreground">The code list itself is the PRODUCTIONCODE value list. Cutoff of 16:00 and 1 day before means 4:00 PM the day before.</p>
      {rows.map((row) => {
        const d = drafts[row.production_code];
        if (!d) return null;
        return (
          <div key={row.production_code} className="grid grid-cols-2 items-end gap-3 border-b py-3 sm:grid-cols-[10rem_8rem_8rem_8rem_auto]">
            <div className="col-span-2 sm:col-span-1">
              <div className="font-medium">{row.label}</div>
              <div className="text-xs text-muted-foreground">{row.production_code}</div>
            </div>
            <div>
              <Label className="text-xs">Cutoff time</Label>
              <Input type="time" value={d.time} onChange={(e) => set(row.production_code, { time: e.target.value })} />
            </div>
            <div>
              <Label className="text-xs">Days before production</Label>
              <Input type="number" min={0} value={d.before} onChange={(e) => set(row.production_code, { before: e.target.value })} />
            </div>
            <div>
              <Label className="text-xs">Delivery days after</Label>
              <Input type="number" min={0} value={d.after} onChange={(e) => set(row.production_code, { after: e.target.value })} />
            </div>
            <label className="flex items-center gap-2 text-sm">
              <Checkbox checked={d.active} onCheckedChange={(v) => set(row.production_code, { active: v === true })} /> Active
            </label>
          </div>
        );
      })}
    </>
  );
}

type MethodDraft = { code: string; name: string; fleet: boolean; tracking: boolean; active: boolean };
const toMethodDraft = (m: MethodRow): MethodDraft => ({
  code: m.delivery_method_code, name: m.delivery_method_name, fleet: m.is_own_fleet, tracking: m.requires_tracking, active: m.is_active,
});
const blankMethod: MethodDraft = { code: '', name: '', fleet: false, tracking: false, active: true };

function MethodsEditor({ rows, tenantId, notify, onSaved }: { rows: MethodRow[]; tenantId: number; notify: Notify; onSaved: () => void }) {
  const [drafts, setDrafts] = useState<MethodDraft[]>([]);
  const [fresh, setFresh] = useState<MethodDraft>(blankMethod);
  const [busy, setBusy] = useState(false);

  useEffect(() => { setDrafts(rows.map(toMethodDraft)); }, [rows]);

  const patch = (i: number, p: Partial<MethodDraft>) => setDrafts((d) => d.map((x, k) => (k === i ? { ...x, ...p } : x)));
  const addNew = fresh.code.trim() !== '' || fresh.name.trim() !== '';
  const invalid = drafts.some((d) => !d.name.trim()) || (addNew && (!fresh.code.trim() || !fresh.name.trim()));

  const save = async () => {
    setBusy(true);
    try {
      for (const d of [...drafts, ...(addNew ? [fresh] : [])]) {
        await post('/api/admin/delivery-methods', {
          tenant_id: tenantId, delivery_method_code: d.code, delivery_method_name: d.name,
          is_own_fleet: d.fleet, requires_tracking: d.tracking, is_active: d.active,
        });
      }
      notify('Delivery methods saved.', 'success');
      setFresh(blankMethod);
      onSaved();
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  const line = (d: MethodDraft, isNew: boolean, set: (p: Partial<MethodDraft>) => void, key: string) => (
    <div key={key} className="grid grid-cols-2 items-end gap-3 border-b py-3 sm:grid-cols-[9rem_1fr_auto_auto_auto]">
      <div>
        <Label className="text-xs">Code</Label>
        <Input value={d.code} disabled={!isNew} onChange={(e) => set({ code: e.target.value.toUpperCase() })} placeholder="OWN_TRUCK" />
      </div>
      <div>
        <Label className="text-xs">Name</Label>
        <Input value={d.name} onChange={(e) => set({ name: e.target.value })} />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox checked={d.fleet} onCheckedChange={(v) => set({ fleet: v === true })} /> Own fleet
      </label>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox checked={d.tracking} onCheckedChange={(v) => set({ tracking: v === true })} /> Tracking
      </label>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox checked={d.active} onCheckedChange={(v) => set({ active: v === true })} /> Active
      </label>
    </div>
  );

  return (
    <>
      <div className="mb-1 flex items-start justify-between gap-3">
        <h2 className="text-lg font-medium">Delivery methods</h2>
        <Button size="sm" onClick={save} disabled={busy || invalid}>Save</Button>
      </div>
      <p className="mb-2 text-xs text-muted-foreground">Own fleet methods appear on the driver&apos;s delivery sheet. Methods are never deleted; uncheck Active instead. Fill in the empty row at the bottom to add a method, then Save.</p>
      {drafts.map((d, i) => line(d, false, (p) => patch(i, p), d.code))}
      {line(fresh, true, (p) => setFresh((f) => ({ ...f, ...p })), 'new')}
    </>
  );
}

type SeqDraft = { mask: string; next: string; reset: string; gapless: boolean };
const toSeqDraft = (q: SequenceRow): SeqDraft => ({ mask: q.mask, next: String(q.next_value), reset: q.reset_period, gapless: q.requires_gapless });

function FormatsEditor({ rows, tenantId, notify }: { rows: SequenceRow[]; tenantId: number; notify: Notify }) {
  const [drafts, setDrafts] = useState<Record<string, SeqDraft>>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => { setDrafts(Object.fromEntries(rows.map((q) => [q.sequence_name, toSeqDraft(q)]))); }, [rows]);

  const set = (name: string, p: Partial<SeqDraft>) => setDrafts((d) => ({ ...d, [name]: { ...d[name], ...p } }));
  const invalid = rows.some((q) => !drafts[q.sequence_name]?.mask.includes('#'));

  const save = async () => {
    setBusy(true);
    try {
      for (const q of rows) {
        const d = drafts[q.sequence_name];
        if (!d) continue;
        await post('/api/admin/sequences', {
          tenant_id: tenantId, sequence_name: q.sequence_name, mask: d.mask, start_value: q.start_value,
          next_value: Number(d.next), increment_by: q.increment_by, reset_period: d.reset, requires_gapless: d.gapless,
        });
      }
      notify('Formats saved.', 'success');
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <div className="mb-1 flex items-start justify-between gap-3">
        <h2 className="text-lg font-medium">Formats</h2>
        <Button size="sm" onClick={save} disabled={busy || invalid}>Save</Button>
      </div>
      <p className="mb-2 text-xs text-muted-foreground">Masks may use [YYYY], [YYYYMM], [YYYYMMDD] and # for digits, for example INV-######. Numbers are never reused; the next number can only be raised. Invoice numbers are assigned when the Packaging List is printed.</p>
      {rows.map((q) => {
        const d = drafts[q.sequence_name];
        if (!d) return null;
        return (
          <div key={q.sequence_name} className="grid grid-cols-2 items-end gap-3 border-b py-3 sm:grid-cols-[10rem_1fr_8rem_9rem_auto]">
            <div>
              <div className="font-medium">{q.label}</div>
              <div className="text-xs text-muted-foreground">{q.is_configured ? q.sequence_name : `${q.sequence_name} (not set up yet)`}</div>
            </div>
            <div>
              <Label className="text-xs">Mask (# = digit)</Label>
              <Input value={d.mask} onChange={(e) => set(q.sequence_name, { mask: e.target.value })} />
            </div>
            <div>
              <Label className="text-xs">Next number</Label>
              <Input type="number" min={0} value={d.next} onChange={(e) => set(q.sequence_name, { next: e.target.value })} />
            </div>
            <div>
              <Label className="text-xs">Restart</Label>
              <select className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm" value={d.reset} onChange={(e) => set(q.sequence_name, { reset: e.target.value })}>
                {['NEVER', 'DAILY', 'MONTHLY', 'YEARLY'].map((x) => <option key={x} value={x}>{x.charAt(0) + x.slice(1).toLowerCase()}</option>)}
              </select>
            </div>
            <label className="flex items-center gap-2 text-sm">
              <Checkbox checked={d.gapless} onCheckedChange={(v) => set(q.sequence_name, { gapless: v === true })} /> Gapless
            </label>
          </div>
        );
      })}
    </>
  );
}

function RunRowEditor({ row, tenantId, notify }: { row: RunRow; tenantId: number; notify: Notify }) {
  const [cutoff, setCutoff] = useState(row.cutoff_local);
  const [busy, setBusy] = useState(false);
  const open = row.run_status === 'OPEN';

  const save = async () => {
    setBusy(true);
    try {
      await post('/api/admin/production-runs', { tenant_id: tenantId, production_run_id: row.production_run_id, cutoff_local: cutoff });
      notify(`Cutoff for ${row.production_code} ${row.production_date} saved.`, 'success');
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid grid-cols-2 items-end gap-3 border-b py-3 sm:grid-cols-[8rem_8rem_8rem_6rem_5rem_1fr_auto]">
      <div className="text-sm">{row.production_date}</div>
      <div className="text-sm font-medium">{row.production_code}</div>
      <div className="text-sm text-muted-foreground">Delivery {row.delivery_date}</div>
      <div className="text-sm">{row.run_status}</div>
      <div className="text-sm text-muted-foreground">{row.order_count} orders</div>
      <div>
        <Label className="text-xs">Cutoff ({row.time_zone})</Label>
        <Input type="datetime-local" value={cutoff} disabled={!open} onChange={(e) => setCutoff(e.target.value)} />
      </div>
      <Button size="sm" onClick={save} disabled={busy || !open || cutoff === row.cutoff_local}>Save</Button>
    </div>
  );
}

type PrintFormats = { customer_number_mask: string; item_number_mask: string; invoice_footer_note: string; invoice_tagline: string };
const EMPTY_FORMATS: PrintFormats = { customer_number_mask: '', item_number_mask: '', invoice_footer_note: '', invoice_tagline: '' };

/** Number masks (statements, invoices) and the invoice footer wording. */
function CustomerNumberMaskEditor({ tenantId, notify }: { tenantId: number; notify: Notify }) {
  const [f, setF] = useState<PrintFormats>(EMPTY_FORMATS);
  const [saved, setSaved] = useState<PrintFormats>(EMPTY_FORMATS);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    call<Partial<Record<keyof PrintFormats, string | null>>>(`/api/admin/format-settings?tenant_id=${tenantId}`)
      .then((d) => {
        const v: PrintFormats = {
          customer_number_mask: d.customer_number_mask ?? '', item_number_mask: d.item_number_mask ?? '',
          invoice_footer_note: d.invoice_footer_note ?? '', invoice_tagline: d.invoice_tagline ?? '',
        };
        setF(v); setSaved(v);
      })
      .catch((e) => notify((e as Error).message, 'error'));
  }, [tenantId, notify]);

  const trimmed: PrintFormats = {
    customer_number_mask: f.customer_number_mask.trim(), item_number_mask: f.item_number_mask.trim(),
    invoice_footer_note: f.invoice_footer_note.trim(), invoice_tagline: f.invoice_tagline.trim(),
  };
  const save = async () => {
    setBusy(true);
    try {
      await post('/api/admin/format-settings', {
        tenant_id: tenantId,
        customer_number_mask: trimmed.customer_number_mask || null, item_number_mask: trimmed.item_number_mask || null,
        invoice_footer_note: trimmed.invoice_footer_note || null, invoice_tagline: trimmed.invoice_tagline || null,
      });
      setSaved(trimmed);
      notify('Print formats saved.', 'success');
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  const badMask = (m: string) => m !== '' && (!m.includes('#') || m.length > 30);
  const bad = badMask(trimmed.customer_number_mask) || badMask(trimmed.item_number_mask);
  const unchanged = (Object.keys(trimmed) as (keyof PrintFormats)[]).every((k) => trimmed[k] === saved[k]);
  const set = (k: keyof PrintFormats) => (e: React.ChangeEvent<HTMLInputElement>) => setF((p) => ({ ...p, [k]: e.target.value }));
  return (
    <div className="mt-6 border-t pt-4">
      <div className="mb-1 flex items-start justify-between gap-3">
        <h3 className="text-base font-medium">Print formats</h3>
        <Button size="sm" onClick={save} disabled={busy || bad || unchanged}>Save</Button>
      </div>
      <p className="mb-3 text-xs text-muted-foreground">How numbers print on statements and invoices. Each # takes the next digit; other characters print as typed; digits beyond the mask are left off (###-## prints 11200 as 112-00). Leave a mask empty to print the number as stored. The footer note and tagline print at the bottom of every invoice page; leave empty to print nothing.</p>
      <div className="grid gap-3 text-sm sm:grid-cols-2">
        <div className="flex items-center gap-2">
          <Label htmlFor="cust-mask" className="w-36 text-xs">Customer number mask</Label>
          <Input id="cust-mask" className="w-40" maxLength={30} placeholder="###-##" value={f.customer_number_mask} onChange={set('customer_number_mask')} />
        </div>
        <div className="flex items-center gap-2">
          <Label htmlFor="item-mask" className="w-36 text-xs">Item number mask</Label>
          <Input id="item-mask" className="w-40" maxLength={30} placeholder="###-##" value={f.item_number_mask} onChange={set('item_number_mask')} />
        </div>
        <div className="flex items-center gap-2 sm:col-span-2">
          <Label htmlFor="inv-note" className="w-36 shrink-0 text-xs">Invoice footer note</Label>
          <Input id="inv-note" maxLength={300} placeholder="e.g. allergen statement" value={f.invoice_footer_note} onChange={set('invoice_footer_note')} />
        </div>
        <div className="flex items-center gap-2 sm:col-span-2">
          <Label htmlFor="inv-tagline" className="w-36 shrink-0 text-xs">Invoice tagline</Label>
          <Input id="inv-tagline" className="max-w-sm" maxLength={100} value={f.invoice_tagline} onChange={set('invoice_tagline')} />
        </div>
      </div>
    </div>
  );
}

function PricingEditor({ tenantId, notify }: { tenantId: number; notify: Notify }) {
  const [years, setYears] = useState('1');
  const [saved, setSaved] = useState('1');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    call<{ pricebook_unused_years: number }>(`/api/admin/pricing-settings?tenant_id=${tenantId}`)
      .then((d) => { setYears(String(d.pricebook_unused_years)); setSaved(String(d.pricebook_unused_years)); })
      .catch((e) => notify((e as Error).message, 'error'));
  }, [tenantId, notify]);

  const save = async () => {
    setBusy(true);
    try {
      await post('/api/admin/pricing-settings', { tenant_id: tenantId, pricebook_unused_years: Number(years) });
      setSaved(years);
      notify('Pricing settings saved.', 'success');
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  const bad = !Number.isInteger(Number(years)) || Number(years) < 1 || Number(years) > 50;
  return (
    <>
      <div className="mb-1 flex items-start justify-between gap-3">
        <h2 className="text-lg font-medium">Pricing</h2>
        <Button size="sm" onClick={save} disabled={busy || bad || years === saved}>Save</Button>
      </div>
      <p className="mb-3 text-xs text-muted-foreground">Stale: a pricing book is stale when none of its customers has ordered in this many years, and an item is stale when it has not been ordered in this many years. Used by the Stale filters and the health checks.</p>
      <div className="flex items-center gap-2 text-sm">
        <Label htmlFor="pb-years" className="text-xs">Stale after (years without orders)</Label>
        <Input id="pb-years" type="number" min={1} max={50} step={1} className="w-24" value={years} onChange={(e) => setYears(e.target.value)} />
      </div>
    </>
  );
}

export type ProductionSection = 'codes' | 'methods' | 'numbering' | 'pricing' | 'runs';

export function ProductionSettings({ tenantId, section = 'codes' }: { tenantId: number; section?: ProductionSection }) {
  const [codes, setCodes] = useState<CodeRow[]>([]);
  const [methods, setMethods] = useState<MethodRow[]>([]);
  const [runs, setRuns] = useState<RunRow[]>([]);
  const [sequences, setSequences] = useState<SequenceRow[]>([]);
  const [message, setMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);

  const notify: Notify = useCallback((text, type) => setMessage({ text, type }), []);

  const load = useCallback(async (tid: number) => {
    try {
      const [c, m, r, q] = await Promise.all([
        call<CodeRow[]>(`/api/admin/production-codes?tenant_id=${tid}`),
        call<MethodRow[]>(`/api/admin/delivery-methods?tenant_id=${tid}`),
        call<RunRow[]>(`/api/admin/production-runs?tenant_id=${tid}&upcoming=true`),
        call<SequenceRow[]>(`/api/admin/sequences?tenant_id=${tid}`),
      ]);
      setCodes(c);
      setMethods(m);
      setRuns([...r].reverse());
      setSequences(q);
    } catch (e) {
      notify((e as Error).message, 'error');
    }
  }, [notify]);

  useEffect(() => {
    void load(tenantId);
  }, [load, tenantId]);

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Application settings</h1>
        <p className="text-sm text-muted-foreground">
          Cutoffs stop customers from entering or changing orders. A run&apos;s cutoff is the production date minus
          the days before, at the cutoff time (tenant time zone). Staff are never blocked.
        </p>
      </div>

      {message && (
        <div role="status" className={message.type === 'error' ? 'text-sm text-destructive' : 'text-sm text-success'}>
          {message.text}
        </div>
      )}

      {section === 'codes' && (
      <Card><CardContent className="pt-6">
        <CodesEditor rows={codes} tenantId={tenantId} notify={notify} />
      </CardContent></Card>
      )}

      {section === 'methods' && (
      <Card><CardContent className="pt-6">
        <MethodsEditor rows={methods} tenantId={tenantId} notify={notify} onSaved={() => load(tenantId)} />
      </CardContent></Card>
      )}

      {section === 'numbering' && (
      <Card><CardContent className="pt-6">
        <FormatsEditor rows={sequences} tenantId={tenantId} notify={notify} />
        <CustomerNumberMaskEditor tenantId={tenantId} notify={notify} />
      </CardContent></Card>
      )}

      {section === 'pricing' && (
      <Card><CardContent className="pt-6">
        <PricingEditor tenantId={tenantId} notify={notify} />
      </CardContent></Card>
      )}

      {section === 'runs' && (
      <Card><CardContent className="pt-6">
        <h2 className="mb-1 text-lg font-medium">Upcoming runs</h2>
        <p className="mb-2 text-xs text-muted-foreground">A run is created when its first order is entered. Change a cutoff here for holidays or special runs (open runs only).</p>
        {runs.length === 0 && <p className="py-3 text-sm text-muted-foreground">No runs yet.</p>}
        {runs.map((r) => <RunRowEditor key={`${r.production_run_id}-${r.cutoff_local}`} row={r} tenantId={tenantId} notify={notify} />)}
      </CardContent></Card>
      )}
    </div>
  );
}
