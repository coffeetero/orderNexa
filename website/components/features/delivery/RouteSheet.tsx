'use client';

import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { Printer } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { DAY_LONG, IN, LAB, call, shortDate, timeLabel, type Day } from './routes-ui';

interface SheetStop {
  stop_no: number; customer_number: string | null; customer_name: string; parent_name: string | null; address: string | null;
  window_from: string | null; window_to: string | null; driver_notes: string | null; is_change: boolean;
}
interface SheetRoute { route_id: number; route_code: string; route_name: string; driver_name: string | null; start_time: string | null; notes: string | null; stops: SheetStop[] }
interface SheetData { day_of_week: Day; production_code: string; production_label: string; date: string | null; routes: SheetRoute[] }

// Printing shows only the sheet (moved to the end of <body>); print colours are fixed black on white, one route per page.
const PRINT_CSS = `
@media print {
  @page { margin: 0.4in; }
  body > *:not(#route-print) { display: none !important; }
  #route-print { display: block !important; }
  html, body { background: #fff !important; height: auto !important; overflow: visible !important; }
  .rs .page + .page { break-before: page; page-break-before: always; }
}
#route-print { display: none; }
.rs { font: 12px/1.35 Inter, Helvetica, Arial, sans-serif; color: #000; background: #fff; font-variant-numeric: tabular-nums; }
.rs h1 { font-size: 18px; margin: 0; }
.rs .meta { display: flex; flex-wrap: wrap; gap: 4px 18px; margin: 4px 0 10px; }
.rs table { width: 100%; border-collapse: collapse; }
.rs th { text-align: left; font-size: 10px; text-transform: uppercase; letter-spacing: .05em; border-bottom: 1.5px solid #000; padding: 3px 6px; }
.rs td { border-bottom: 1px solid #bbb; padding: 5px 6px; vertical-align: top; }
.rs tr { break-inside: avoid; page-break-inside: avoid; }
.rs .no { font-weight: 700; font-size: 13px; width: 26px; }
.rs .muted { color: #444; }
.rs .box { width: 64px; }
.rs .page + .page { margin-top: 28px; }
.rs .empty { padding: 8px 0; }
`;

/** Printable route sheet(s) in stop order; a date applies that date's changes. */
export function RouteSheet({ tenantId, routeId, dow, code, initialDate }: { tenantId: number; routeId: number | null; dow: string; code: string; initialDate: string }) {
  const [date, setDate] = useState(initialDate);
  const [data, setData] = useState<SheetData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
    const qs = new URLSearchParams({ tenant_id: String(tenantId), dow, code });
    if (routeId !== null) qs.set('route_id', String(routeId));
    if (date) qs.set('date', date);
    setData(null);
    call<SheetData>(`/api/delivery/routes/sheet?${qs.toString()}`).then(setData).catch((e: Error) => setError(e.message));
  }, [tenantId, routeId, dow, code, date]);

  const sheet = data ? (
    <div className="rs">
      {data.routes.length === 0 && <p className="empty">No routes with stops for {DAY_LONG[data.day_of_week]} {data.production_label}.</p>}
      {data.routes.map((r) => (
        <div key={r.route_id} className="page">
          <h1>{r.route_code} · {r.route_name}</h1>
          <div className="meta">
            <span><b>{DAY_LONG[data.day_of_week]}{data.date ? ` ${shortDate(data.date)}` : ''}</b> · {data.production_label}</span>
            {r.driver_name && <span>Driver <b>{r.driver_name}</b></span>}
            {r.start_time && <span>Start <b>{timeLabel(r.start_time)}</b></span>}
            <span>{r.stops.length} stops</span>
            {r.notes && <span className="muted">{r.notes}</span>}
          </div>
          <table>
            <thead><tr><th>#</th><th>Cust No.</th><th>Ship-to</th><th>Address</th><th>Window</th><th>Driver notes</th><th className="box">Arrived</th></tr></thead>
            <tbody>
              {r.stops.map((s) => (
                <tr key={`${s.stop_no}-${s.customer_number}`}>
                  <td className="no">{s.stop_no}</td>
                  <td>{s.customer_number}</td>
                  <td><b>{s.customer_name}</b>{s.parent_name ? <div className="muted">{s.parent_name}</div> : null}{s.is_change ? <div className="muted">(this date only)</div> : null}</td>
                  <td>{s.address}</td>
                  <td>{s.window_from || s.window_to ? `${timeLabel(s.window_from) || '…'} – ${timeLabel(s.window_to) || '…'}` : ''}</td>
                  <td>{s.driver_notes}</td>
                  <td className="box" />
                </tr>
              ))}
              {r.stops.length === 0 && <tr><td colSpan={7} className="muted">No stops.</td></tr>}
            </tbody>
          </table>
        </div>
      ))}
    </div>
  ) : null;

  return (
    <div className="space-y-3 p-2 sm:p-3">
      <style>{PRINT_CSS}</style>
      <div className="flex flex-wrap items-end gap-3">
        <h1 className="mr-auto text-lg font-semibold">Route Sheet</h1>
        <div>
          <label className={LAB} htmlFor="rs-date">Delivery date (applies date changes)</label>
          <input id="rs-date" type="date" className={`${IN} w-44`} value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
        <Button className="gap-1" disabled={!sheet} onClick={() => window.print()}><Printer className="h-4 w-4" />Print</Button>
      </div>
      <p className="text-sm text-muted-foreground">
        {date ? 'The routes as they run on that date.' : 'The weekly stops for this day; pick a delivery date to apply that date’s changes.'} Use Print, then Save as PDF for a PDF.
      </p>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      {!error && !sheet && <p className="text-sm text-muted-foreground">Loading…</p>}
      {sheet && <div className="max-w-[72rem] overflow-x-auto rounded-lg border bg-card p-1"><div className="rounded-md bg-background p-4">{sheet}</div></div>}
      {mounted && sheet && createPortal(<div id="route-print">{sheet}</div>, document.body)}
    </div>
  );
}
