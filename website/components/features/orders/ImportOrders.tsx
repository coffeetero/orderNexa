'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CheckCircle2, Trash2, Upload } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toImportRows } from '@/lib/orders/import-csv';

interface Account { customer_id: number; customer_name: string; customer_number: string | null }
interface Code { value: string; label: string }
type Status = 'IMPORTED' | 'ISSUES' | 'APPROVED';
interface ImportSummary {
  order_import_id: number; customer_name: string; customer_number: string | null; production_date: string; production_code: string;
  file_name: string | null; import_status: Status; row_count: number; order_count: number; error_count: number; warning_count: number;
  total_amount: number; created_at: string; approved_at: string | null;
}
interface ImportRowOut {
  row_number: number; cus_no: string | null; item_number: string | null; item_desc: string | null; qty: string | null;
  customer_name: string | null; item_name: string | null; unit_price: number | null; amount: number | null;
  severity: 'ERROR' | 'WARNING' | null; issue: string | null; order_number: string | null;
}
interface ImportOrder { order_id: number; order_number: string; customer_number: string | null; customer_name: string; lines: number; quantity: number; amount: number }
interface ImportDetail extends ImportSummary { delivery_date: string; run_status: string | null; rows: ImportRowOut[]; orders: ImportOrder[]; needs_reprocess?: boolean }

const money = (v: unknown) => Number(v ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const qty = (v: unknown) => Number(v ?? 0).toLocaleString('en-US', { maximumFractionDigits: 3 });
const isoDay = (offset: number) => new Date(Date.now() + offset * 86_400_000).toLocaleDateString('en-CA');
const STATUS: Record<Status, { label: string; cls: string }> = {
  IMPORTED: { label: 'Ready to approve', cls: 'bg-blue-100 text-blue-900 dark:bg-blue-950 dark:text-blue-100' },
  ISSUES: { label: 'Has issues', cls: 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100' },
  APPROVED: { label: 'Approved', cls: 'bg-green-100 text-green-900 dark:bg-green-950 dark:text-green-100' },
};
const Badge = ({ s }: { s: Status }) => <span className={`rounded px-2 py-0.5 text-xs font-medium ${STATUS[s].cls}`}>{STATUS[s].label}</span>;

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const j = (await res.json()) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Request failed');
  return j.data as T;
}

export function ImportOrders({ tenantId }: { tenantId: number }) {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [codes, setCodes] = useState<Code[]>([]);
  const [search, setSearch] = useState('');
  const [accountId, setAccountId] = useState<number | null>(null);
  const [date, setDate] = useState(isoDay(1));
  const [code, setCode] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);
  const [detail, setDetail] = useState<ImportDetail | null>(null);
  const [issuesOnly, setIssuesOnly] = useState(false);
  const [recent, setRecent] = useState<ImportSummary[]>([]);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const loadRecent = useCallback(() => {
    call<ImportSummary[]>(`/api/orders/import?tenant_id=${tenantId}&from=${isoDay(-14)}&to=${isoDay(30)}`)
      .then(setRecent).catch((e: Error) => setMessage({ text: e.message, error: true }));
  }, [tenantId]);

  useEffect(() => {
    call<Account[]>(`/api/reports/financial?tenant_id=${tenantId}`).then(setAccounts).catch((e: Error) => setMessage({ text: e.message, error: true }));
    call<{ production_codes: Code[] }>(`/api/production/defaults?tenant_id=${tenantId}`)
      .then((d) => { setCodes(d.production_codes); setCode((c) => c || d.production_codes[0]?.value || ''); })
      .catch((e: Error) => setMessage({ text: e.message, error: true }));
    loadRecent();
  }, [tenantId, loadRecent]);

  const matches = useMemo(() => {
    const t = search.trim().toLowerCase();
    if (!t) return [];
    return accounts.filter((a) => a.customer_name.toLowerCase().includes(t) || (a.customer_number ?? '').includes(t)).slice(0, 8);
  }, [accounts, search]);
  const account = accounts.find((a) => a.customer_id === accountId) ?? null;

  const upload = async () => {
    if (!account || !file || !code) return;
    setBusy(true); setMessage(null); setConfirmDelete(false);
    try {
      const rows = toImportRows(await file.text());
      if (rows.length === 0) throw new Error('The file has no rows');
      const d = await call<ImportDetail>('/api/orders/import', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, customer_id: account.customer_id, production_date: date, production_code: code, file_name: file.name, rows }),
      });
      setDetail(d); setIssuesOnly(d.error_count > 0);
      setMessage({ text: d.error_count > 0 ? `Imported with ${d.error_count} row${d.error_count === 1 ? '' : 's'} that need fixing.` : 'Imported. Review the orders and approve them.', error: false });
      setFile(null); if (fileInput.current) fileInput.current.value = '';
      loadRecent();
    } catch (e) {
      setMessage({ text: (e as Error).message, error: true });
    } finally { setBusy(false); }
  };

  const open = async (id: number) => {
    setBusy(true); setMessage(null); setConfirmDelete(false);
    try { const d = await call<ImportDetail>(`/api/orders/import?tenant_id=${tenantId}&id=${id}`); setDetail(d); setIssuesOnly(d.error_count > 0); }
    catch (e) { setMessage({ text: (e as Error).message, error: true }); }
    finally { setBusy(false); }
  };

  const approve = async () => {
    if (!detail) return;
    setBusy(true); setMessage(null);
    try {
      const d = await call<ImportDetail>(`/api/orders/import/${detail.order_import_id}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tenant_id: tenantId, action: 'approve' }),
      });
      setDetail(d);
      setMessage({ text: d.needs_reprocess ? 'Approved. This run was already processed: process it again so these orders get their deliveries and invoice.' : 'Approved. The orders are now part of production.', error: false });
      loadRecent();
    } catch (e) { setMessage({ text: (e as Error).message, error: true }); }
    finally { setBusy(false); }
  };

  const remove = async () => {
    if (!detail) return;
    setBusy(true); setMessage(null);
    try {
      const r = await call<{ deleted_orders: number }>(`/api/orders/import/${detail.order_import_id}?tenant_id=${tenantId}`, { method: 'DELETE' });
      setDetail(null); setConfirmDelete(false);
      setMessage({ text: `Import deleted with its ${r.deleted_orders} order${r.deleted_orders === 1 ? '' : 's'}.`, error: false });
      loadRecent();
    } catch (e) { setMessage({ text: (e as Error).message, error: true }); }
    finally { setBusy(false); }
  };

  const rows = detail ? (issuesOnly ? detail.rows.filter((r) => r.severity) : detail.rows) : [];

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Import Orders</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Upload a customer&rsquo;s order file for one production date and code. Each row is checked and priced from the customer&rsquo;s pricing book;
          the orders stay out of production until you approve them. Uploading again for the same customer, date and code replaces an import that is not approved yet.
        </p>
      </div>

      <Card><CardContent className="space-y-4 pt-6">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[minmax(16rem,1fr)_10rem_10rem_minmax(14rem,1fr)_auto] lg:items-end">
          <div className="relative">
            <Label htmlFor="imp-cust" className="text-xs">Customer account</Label>
            <Input id="imp-cust" autoComplete="off" placeholder="Name or number" value={account && !search ? `${account.customer_number ?? ''} · ${account.customer_name}` : search}
              onChange={(e) => { setSearch(e.target.value); setAccountId(null); }} />
            {matches.length > 0 && !account && (
              <ul className="absolute z-10 mt-1 w-full rounded-md border bg-popover text-sm shadow">
                {matches.map((a) => (
                  <li key={a.customer_id}>
                    <button type="button" className="flex w-full justify-between gap-2 px-3 py-1.5 text-left hover:bg-accent"
                      onClick={() => { setAccountId(a.customer_id); setSearch(''); }}>
                      <span>{a.customer_name}</span><span className="text-muted-foreground">{a.customer_number}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
          <div><Label htmlFor="imp-date" className="text-xs">Production date</Label><Input id="imp-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
          <div>
            <Label htmlFor="imp-code" className="text-xs">Production code</Label>
            <select id="imp-code" className="h-10 w-full rounded-md border border-input bg-background px-2 text-sm" value={code} onChange={(e) => setCode(e.target.value)}>
              {codes.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          <div>
            <Label htmlFor="imp-file" className="text-xs">Order file (.csv)</Label>
            <Input id="imp-file" ref={fileInput} type="file" accept=".csv,.txt,text/csv" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </div>
          <Button onClick={upload} disabled={busy || !account || !file || !code} className="gap-1.5"><Upload className="h-4 w-4" />{busy ? 'Working…' : 'Upload'}</Button>
        </div>
        <p className="text-xs text-muted-foreground">Columns: customer number, item number, item description, quantity. A header row is optional. Customer numbers must be the account or its departments and sites.</p>
        {message && <p role="status" className={`text-sm ${message.error ? 'text-destructive' : 'text-foreground'}`}>{message.text}</p>}
      </CardContent></Card>

      {detail && (
        <Card><CardContent className="space-y-4 pt-6">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="space-y-1">
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-lg font-medium">{detail.customer_name}{detail.customer_number ? ` (${detail.customer_number})` : ''}</h2>
                <Badge s={detail.import_status} />
              </div>
              <p className="text-sm text-muted-foreground">
                {detail.production_date} · {detail.production_code} · delivery {detail.delivery_date}{detail.file_name ? ` · ${detail.file_name}` : ''}
              </p>
              <p className="text-sm">
                {detail.row_count} rows · {detail.order_count} orders · total {money(detail.total_amount)}
                {detail.error_count > 0 && <span className="text-destructive"> · {detail.error_count} with errors</span>}
                {detail.warning_count > 0 && <span className="text-amber-700 dark:text-amber-400"> · {detail.warning_count} warnings</span>}
              </p>
            </div>
            {detail.import_status !== 'APPROVED' && (
              <div className="flex flex-wrap gap-2">
                {confirmDelete ? (
                  <>
                    <span className="self-center text-sm">Delete this import and its {detail.order_count} orders?</span>
                    <Button variant="destructive" size="sm" onClick={remove} disabled={busy}>Delete</Button>
                    <Button variant="outline" size="sm" onClick={() => setConfirmDelete(false)} disabled={busy}>Keep</Button>
                  </>
                ) : (
                  <Button variant="outline" size="sm" className="gap-1.5" onClick={() => setConfirmDelete(true)} disabled={busy}><Trash2 className="h-4 w-4" />Delete import</Button>
                )}
                <Button size="sm" className="gap-1.5" onClick={approve} disabled={busy || detail.error_count > 0}
                  title={detail.error_count > 0 ? 'Fix the rows with errors and upload the file again' : undefined}>
                  <CheckCircle2 className="h-4 w-4" />Approve for production
                </Button>
              </div>
            )}
          </div>

          <div className="flex items-center justify-between gap-2">
            <h3 className="text-sm font-medium">File rows</h3>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" className="h-4 w-4 rounded border-input" checked={issuesOnly} onChange={(e) => setIssuesOnly(e.target.checked)} />
              Only rows with issues
            </label>
          </div>
          <div className="max-h-[28rem] overflow-auto rounded-md border">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-muted text-left text-xs">
                <tr>
                  <th className="px-2 py-1.5">Row</th><th className="px-2 py-1.5">Cus no</th><th className="px-2 py-1.5">Customer</th>
                  <th className="px-2 py-1.5">Item no</th><th className="px-2 py-1.5">Item</th><th className="px-2 py-1.5 text-right">Qty</th>
                  <th className="px-2 py-1.5 text-right">Price</th><th className="px-2 py-1.5 text-right">Amount</th><th className="px-2 py-1.5">Order</th><th className="px-2 py-1.5">Issue</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.row_number} className={`border-t ${r.severity === 'ERROR' ? 'bg-red-50 dark:bg-red-950/40' : r.severity === 'WARNING' ? 'bg-amber-50 dark:bg-amber-950/30' : ''}`}>
                    <td className="px-2 py-1 text-muted-foreground">{r.row_number}</td>
                    <td className="px-2 py-1">{r.cus_no}</td>
                    <td className="px-2 py-1">{r.customer_name}</td>
                    <td className="px-2 py-1">{r.item_number}</td>
                    <td className="px-2 py-1">{r.item_name ?? r.item_desc}</td>
                    <td className="px-2 py-1 text-right">{r.qty}</td>
                    <td className="px-2 py-1 text-right">{r.unit_price != null ? money(r.unit_price) : ''}</td>
                    <td className="px-2 py-1 text-right">{r.amount != null ? money(r.amount) : ''}</td>
                    <td className="px-2 py-1">{r.order_number}</td>
                    <td className={`px-2 py-1 ${r.severity === 'ERROR' ? 'text-destructive' : 'text-amber-700 dark:text-amber-400'}`}>{r.issue}</td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={10} className="px-2 py-3 text-muted-foreground">No rows with issues.</td></tr>}
              </tbody>
            </table>
          </div>

          <h3 className="text-sm font-medium">Orders created</h3>
          <div className="overflow-auto rounded-md border">
            <table className="w-full text-sm">
              <thead className="bg-muted text-left text-xs">
                <tr><th className="px-2 py-1.5">Order</th><th className="px-2 py-1.5">Cus no</th><th className="px-2 py-1.5">Customer</th><th className="px-2 py-1.5 text-right">Lines</th><th className="px-2 py-1.5 text-right">Qty</th><th className="px-2 py-1.5 text-right">Amount</th></tr>
              </thead>
              <tbody>
                {detail.orders.map((o) => (
                  <tr key={o.order_id} className="border-t">
                    <td className="px-2 py-1">{o.order_number}</td><td className="px-2 py-1">{o.customer_number}</td><td className="px-2 py-1">{o.customer_name}</td>
                    <td className="px-2 py-1 text-right">{o.lines}</td><td className="px-2 py-1 text-right">{qty(o.quantity)}</td><td className="px-2 py-1 text-right">{money(o.amount)}</td>
                  </tr>
                ))}
                {detail.orders.length === 0 && <tr><td colSpan={6} className="px-2 py-3 text-muted-foreground">No orders were created.</td></tr>}
              </tbody>
            </table>
          </div>
        </CardContent></Card>
      )}

      <Card><CardContent className="space-y-3 pt-6">
        <h2 className="text-lg font-medium">Recent imports</h2>
        <p className="text-xs text-muted-foreground">Production dates from two weeks ago to a month ahead.</p>
        {recent.length === 0 ? <p className="text-sm text-muted-foreground">No imports yet.</p> : (
          <div className="overflow-auto rounded-md border">
            <table className="w-full text-sm">
              <thead className="bg-muted text-left text-xs">
                <tr><th className="px-2 py-1.5">Production</th><th className="px-2 py-1.5">Customer</th><th className="px-2 py-1.5">File</th><th className="px-2 py-1.5 text-right">Orders</th><th className="px-2 py-1.5 text-right">Total</th><th className="px-2 py-1.5">Status</th></tr>
              </thead>
              <tbody>
                {recent.map((i) => (
                  <tr key={i.order_import_id} className="cursor-pointer border-t hover:bg-accent" onClick={() => open(i.order_import_id)}>
                    <td className="px-2 py-1">{i.production_date} {i.production_code}</td>
                    <td className="px-2 py-1">{i.customer_name}{i.customer_number ? ` (${i.customer_number})` : ''}</td>
                    <td className="px-2 py-1">{i.file_name}</td>
                    <td className="px-2 py-1 text-right">{i.order_count}</td>
                    <td className="px-2 py-1 text-right">{money(i.total_amount)}</td>
                    <td className="px-2 py-1"><Badge s={i.import_status} />{i.error_count > 0 && <span className="ml-2 text-xs text-destructive">{i.error_count} errors</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent></Card>
    </div>
  );
}
