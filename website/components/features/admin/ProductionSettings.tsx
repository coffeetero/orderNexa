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

function CodeRowEditor({ row, tenantId, notify }: { row: CodeRow; tenantId: number; notify: Notify }) {
  const [time, setTime] = useState(row.cutoff_time ?? '');
  const [before, setBefore] = useState(String(row.cutoff_days_before ?? 1));
  const [after, setAfter] = useState(String(row.delivery_days_after ?? 1));
  const [active, setActive] = useState(row.is_active ?? true);
  const [busy, setBusy] = useState(false);

  const save = async () => {
    setBusy(true);
    try {
      await post('/api/admin/production-codes', {
        tenant_id: tenantId, production_code: row.production_code, cutoff_time: time,
        cutoff_days_before: Number(before), delivery_days_after: Number(after), is_active: active,
      });
      notify(`${row.label} saved.`, 'success');
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid grid-cols-2 items-end gap-3 border-b py-3 sm:grid-cols-[10rem_8rem_8rem_8rem_auto_auto]">
      <div className="col-span-2 sm:col-span-1">
        <div className="font-medium">{row.label}</div>
        <div className="text-xs text-muted-foreground">{row.production_code}</div>
      </div>
      <div>
        <Label className="text-xs">Cutoff time</Label>
        <Input type="time" value={time} onChange={(e) => setTime(e.target.value)} />
      </div>
      <div>
        <Label className="text-xs">Days before production</Label>
        <Input type="number" min={0} value={before} onChange={(e) => setBefore(e.target.value)} />
      </div>
      <div>
        <Label className="text-xs">Delivery days after</Label>
        <Input type="number" min={0} value={after} onChange={(e) => setAfter(e.target.value)} />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox checked={active} onCheckedChange={(v) => setActive(v === true)} /> Active
      </label>
      <Button size="sm" onClick={save} disabled={busy || !time}>Save</Button>
    </div>
  );
}

function MethodRowEditor({
  row, tenantId, notify, onSaved, isNew,
}: { row: MethodRow; tenantId: number; notify: Notify; onSaved: () => void; isNew?: boolean }) {
  const [code, setCode] = useState(row.delivery_method_code);
  const [name, setName] = useState(row.delivery_method_name);
  const [fleet, setFleet] = useState(row.is_own_fleet);
  const [tracking, setTracking] = useState(row.requires_tracking);
  const [active, setActive] = useState(row.is_active);
  const [busy, setBusy] = useState(false);

  const save = async () => {
    setBusy(true);
    try {
      await post('/api/admin/delivery-methods', {
        tenant_id: tenantId, delivery_method_code: code, delivery_method_name: name,
        is_own_fleet: fleet, requires_tracking: tracking, is_active: active,
      });
      notify(`${name} saved.`, 'success');
      onSaved();
    } catch (e) {
      notify((e as Error).message, 'error');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid grid-cols-2 items-end gap-3 border-b py-3 sm:grid-cols-[9rem_1fr_auto_auto_auto_auto]">
      <div>
        <Label className="text-xs">Code</Label>
        <Input value={code} disabled={!isNew} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="OWN_TRUCK" />
      </div>
      <div>
        <Label className="text-xs">Name</Label>
        <Input value={name} onChange={(e) => setName(e.target.value)} />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox checked={fleet} onCheckedChange={(v) => setFleet(v === true)} /> Own fleet
      </label>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox checked={tracking} onCheckedChange={(v) => setTracking(v === true)} /> Tracking
      </label>
      <label className="flex items-center gap-2 text-sm">
        <Checkbox checked={active} onCheckedChange={(v) => setActive(v === true)} /> Active
      </label>
      <Button size="sm" onClick={save} disabled={busy || !code.trim() || !name.trim()}>{isNew ? 'Add' : 'Save'}</Button>
    </div>
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

export function ProductionSettings({ tenantId }: { tenantId: number }) {
  const [codes, setCodes] = useState<CodeRow[]>([]);
  const [methods, setMethods] = useState<MethodRow[]>([]);
  const [runs, setRuns] = useState<RunRow[]>([]);
  const [message, setMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const [newKey, setNewKey] = useState(0);

  const notify: Notify = useCallback((text, type) => setMessage({ text, type }), []);

  const load = useCallback(async (tid: number) => {
    try {
      const [c, m, r] = await Promise.all([
        call<CodeRow[]>(`/api/admin/production-codes?tenant_id=${tid}`),
        call<MethodRow[]>(`/api/admin/delivery-methods?tenant_id=${tid}`),
        call<RunRow[]>(`/api/admin/production-runs?tenant_id=${tid}&upcoming=true`),
      ]);
      setCodes(c);
      setMethods(m);
      setRuns([...r].reverse());
    } catch (e) {
      notify((e as Error).message, 'error');
    }
  }, [notify]);

  useEffect(() => {
    void load(tenantId);
  }, [load, tenantId]);

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-4 sm:p-6">
      <div>
        <h1 className="text-2xl font-semibold">Production settings</h1>
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

      <Card><CardContent className="pt-6">
        <h2 className="mb-1 text-lg font-medium">Production codes</h2>
        <p className="mb-2 text-xs text-muted-foreground">The code list itself is the PRODUCTIONCODE value list. Cutoff of 16:00 and 1 day before means 4:00 PM the day before.</p>
        {codes.map((c) => <CodeRowEditor key={c.production_code} row={c} tenantId={tenantId} notify={notify} />)}
      </CardContent></Card>

      <Card><CardContent className="pt-6">
        <h2 className="mb-1 text-lg font-medium">Delivery methods</h2>
        <p className="mb-2 text-xs text-muted-foreground">Own fleet methods appear on the driver&apos;s delivery sheet. Methods are never deleted; uncheck Active instead.</p>
        {methods.map((m) => (
          <MethodRowEditor key={m.delivery_method_code} row={m} tenantId={tenantId} notify={notify} onSaved={() => load(tenantId)} />
        ))}
        <MethodRowEditor
          key={`new-${newKey}`} isNew tenantId={tenantId} notify={notify}
          row={{ delivery_method_code: '', delivery_method_name: '', is_own_fleet: false, requires_tracking: false, is_active: true }}
          onSaved={() => { setNewKey((k) => k + 1); void load(tenantId); }}
        />
      </CardContent></Card>

      <Card><CardContent className="pt-6">
        <h2 className="mb-1 text-lg font-medium">Upcoming runs</h2>
        <p className="mb-2 text-xs text-muted-foreground">A run is created when its first order is entered. Change a cutoff here for holidays or special runs (open runs only).</p>
        {runs.length === 0 && <p className="py-3 text-sm text-muted-foreground">No runs yet.</p>}
        {runs.map((r) => <RunRowEditor key={`${r.production_run_id}-${r.cutoff_local}`} row={r} tenantId={tenantId} notify={notify} />)}
      </CardContent></Card>
    </div>
  );
}
