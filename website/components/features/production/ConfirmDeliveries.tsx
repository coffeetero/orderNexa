'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface Defaults {
  from_date: string;
  to_date: string;
  production_codes: { value: string; label: string }[];
}
interface Method {
  delivery_method_code: string;
  delivery_method_name: string;
  requires_tracking: boolean;
  is_active: boolean;
}
interface ShipLine {
  shipment_line_id: number;
  order_number: string | null;
  department_event: string | null;
  item_name: string | null;
  quantity: number;
  shipped_quantity: number | null;
}
interface Shipment {
  shipment_id: number;
  shipment_number: string;
  production_date: string;
  production_code: string;
  delivery_date: string;
  customer_name: string;
  delivery_method_code: string | null;
  carrier: string | null;
  tracking_reference: string | null;
  route: string | null;
  delivery_cost: number | null;
  shipment_status: string;
  invoice_numbers: string[];
  lines: ShipLine[];
}
interface Shortage { item_name: string | null; short: number }

const selectClass = 'h-9 w-full rounded-md border border-input bg-background px-2 text-sm';

function ShipmentCard({
  shipment, methods, tenantId, onDone,
}: { shipment: Shipment; methods: Method[]; tenantId: number; onDone: (message: string) => void }) {
  const [method, setMethod] = useState(shipment.delivery_method_code ?? '');
  const [carrier, setCarrier] = useState(shipment.carrier ?? '');
  const [tracking, setTracking] = useState(shipment.tracking_reference ?? '');
  const [route, setRoute] = useState(shipment.route ?? '');
  const [cost, setCost] = useState(shipment.delivery_cost === null ? '' : String(shipment.delivery_cost));
  const [shipped, setShipped] = useState<Record<number, string>>(
    Object.fromEntries(shipment.lines.map((l) => [l.shipment_line_id, String(l.shipped_quantity ?? l.quantity)])),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requiresTracking = methods.find((m) => m.delivery_method_code === method)?.requires_tracking ?? false;

  const confirm = async (status: 'SHIPPED' | 'DELIVERED') => {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/shipments/confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, shipment_id: shipment.shipment_id, shipment_status: status,
          delivery_method_code: method || undefined, carrier, tracking_reference: tracking, route,
          delivery_cost: cost === '' ? '' : cost,
          lines: shipment.lines.map((l) => ({ shipment_line_id: l.shipment_line_id, shipped_quantity: Number(shipped[l.shipment_line_id]) })),
        }),
      });
      const json = (await res.json()) as { data?: { shortages: Shortage[] }; error?: string };
      if (!res.ok || json.error) throw new Error(json.error ?? 'Could not confirm');
      const short = json.data?.shortages ?? [];
      onDone(`${shipment.shipment_number} ${status.toLowerCase()}.${short.length ? ` Short: ${short.map((s) => `${s.item_name} (${s.short})`).join(', ')}.` : ''}`);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card><CardContent className="space-y-3 pt-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <span className="font-medium">{shipment.customer_name}</span>
          <span className="ml-2 text-xs text-muted-foreground">
            {shipment.shipment_number} · {shipment.production_date} {shipment.production_code} · deliver {shipment.delivery_date}
          </span>
        </div>
        <div className="text-xs">
          <span className="rounded bg-muted px-2 py-0.5">{shipment.shipment_status}</span>
          {shipment.invoice_numbers.length > 0 && <span className="ml-2 text-muted-foreground">Invoice {shipment.invoice_numbers.join(', ')}</span>}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-[12rem_1fr_1fr_8rem_8rem]">
        <div>
          <Label className="text-xs">Method</Label>
          <select className={selectClass} value={method} onChange={(e) => setMethod(e.target.value)}>
            <option value="">—</option>
            {methods.filter((m) => m.is_active || m.delivery_method_code === method).map((m) => (
              <option key={m.delivery_method_code} value={m.delivery_method_code}>{m.delivery_method_name}</option>
            ))}
          </select>
        </div>
        <div>
          <Label className="text-xs">Carrier</Label>
          <Input value={carrier} onChange={(e) => setCarrier(e.target.value)} placeholder="UPS, Uber…" />
        </div>
        <div>
          <Label className="text-xs">Tracking / reference{requiresTracking ? ' *' : ''}</Label>
          <Input value={tracking} onChange={(e) => setTracking(e.target.value)} />
        </div>
        <div>
          <Label className="text-xs">Route</Label>
          <Input value={route} onChange={(e) => setRoute(e.target.value)} />
        </div>
        <div>
          <Label className="text-xs">Delivery cost</Label>
          <Input type="number" min={0} step="0.01" value={cost} onChange={(e) => setCost(e.target.value)} className="text-right tabular-nums" />
        </div>
      </div>

      <div>
        <div className="grid grid-cols-[1fr_5rem_6rem] gap-2 border-b pb-1 text-xs font-medium text-muted-foreground">
          <span>Order / item</span><span className="text-right">Planned</span><span className="text-right">Shipped</span>
        </div>
        {shipment.lines.map((l) => (
          <div key={l.shipment_line_id} className="grid grid-cols-[1fr_5rem_6rem] items-center gap-2 border-b py-1.5 text-sm">
            <span>
              {l.item_name} <span className="text-xs text-muted-foreground">{l.order_number}{l.department_event ? ` · ${l.department_event}` : ''}</span>
            </span>
            <span className="text-right tabular-nums">{l.quantity}</span>
            <Input
              type="number" min={0} step="any" className="h-8 text-right tabular-nums"
              value={shipped[l.shipment_line_id] ?? ''}
              onChange={(e) => setShipped((s) => ({ ...s, [l.shipment_line_id]: e.target.value }))}
            />
          </div>
        ))}
      </div>

      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <div className="flex gap-2">
        <Button size="sm" onClick={() => confirm('SHIPPED')} disabled={busy}>Mark shipped</Button>
        <Button size="sm" variant="outline" onClick={() => confirm('DELIVERED')} disabled={busy}>Mark delivered</Button>
      </div>
    </CardContent></Card>
  );
}

export function ConfirmDeliveries({ tenantId }: { tenantId: number }) {
  const [codes, setCodes] = useState<Defaults['production_codes']>([]);
  const [methods, setMethods] = useState<Method[]>([]);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [code, setCode] = useState('');
  const [status, setStatus] = useState('PLANNED');
  const [shipments, setShipments] = useState<Shipment[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      fetch(`/api/production/defaults?tenant_id=${tenantId}`).then((r) => r.json()),
      fetch(`/api/admin/delivery-methods?tenant_id=${tenantId}`).then((r) => r.json()),
    ])
      .then(([d, m]: [{ data?: Defaults; error?: string }, { data?: Method[]; error?: string }]) => {
        if (d.error || !d.data) throw new Error(d.error ?? 'Could not load defaults');
        setFrom(d.data.from_date);
        setTo(d.data.to_date);
        setCodes(d.data.production_codes);
        setMethods(m.data ?? []);
      })
      .catch((e: Error) => setError(e.message));
  }, [tenantId]);

  const load = async () => {
    setBusy(true);
    setError(null);
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId), from, to });
      if (code) qs.set('production_code', code);
      if (status) qs.set('status', status);
      const res = await fetch(`/api/shipments?${qs.toString()}`);
      const json = (await res.json()) as { data?: Shipment[]; error?: string };
      if (!res.ok || json.error) throw new Error(json.error ?? 'Could not load shipments');
      setShipments(json.data ?? []);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-4 sm:p-6">
      <div>
        <h1 className="text-2xl font-semibold">Confirm deliveries</h1>
        <p className="text-sm text-muted-foreground">
          Record what actually went out on each shipment (and how). Once a shipment is shipped, its invoice lines count toward
          the customer&apos;s balance; a short delivery only bills what shipped. Carrier shipments need a tracking reference.
        </p>
      </div>

      <Card><CardContent className="pt-6">
        <div className="grid grid-cols-1 items-end gap-3 sm:grid-cols-[10rem_10rem_11rem_11rem_auto]">
          <div>
            <Label className="text-xs">From production date</Label>
            <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div>
            <Label className="text-xs">To production date</Label>
            <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <div>
            <Label className="text-xs">Production code</Label>
            <select className={selectClass} value={code} onChange={(e) => setCode(e.target.value)}>
              <option value="">All codes</option>
              {codes.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          <div>
            <Label className="text-xs">Status</Label>
            <select className={selectClass} value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="PLANNED">Planned</option>
              <option value="SHIPPED">Shipped</option>
              <option value="DELIVERED">Delivered</option>
              <option value="">All</option>
            </select>
          </div>
          <Button onClick={load} disabled={busy || !from || !to}>{busy ? 'Loading…' : 'Load shipments'}</Button>
        </div>
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
        {message && <p role="status" className="mt-3 text-sm text-success">{message}</p>}
      </CardContent></Card>

      {shipments !== null && shipments.length === 0 && (
        <p className="text-sm text-muted-foreground">No shipments for these filters. Process the run first (Production &gt; Process Run).</p>
      )}
      {shipments?.map((s) => (
        <ShipmentCard
          key={`${s.shipment_id}-${s.shipment_status}`}
          shipment={s} methods={methods} tenantId={tenantId}
          onDone={(text) => { setMessage(text); void load(); }}
        />
      ))}
    </div>
  );
}
