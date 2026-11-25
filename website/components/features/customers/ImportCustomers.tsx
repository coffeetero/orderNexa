'use client';

import { useRef, useState } from 'react';
import { CheckCircle2, Upload } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { columnLabel, parseCustomerCsv, readCustomerSheet, type CustomerFileRow } from '@/lib/customers/customer-file';

type Action = 'NEW' | 'CHANGED' | 'UNCHANGED' | 'ERROR';
interface Change { field: string; from: string | null; to: string | null }
interface ImportRow {
  row_number: number; customer_number: string | null; customer_name: string | null; customer_type: string | null; parent_number: string | null;
  row_action: Action; changes: Change[]; issue: string | null;
}
interface ImportDetail {
  customer_import_id: number; file_name: string | null; import_status: 'PREVIEW' | 'APPLIED';
  row_count: number; new_count: number; changed_count: number; unchanged_count: number; error_count: number;
  rows: ImportRow[]; applied?: boolean; message?: string; inserted?: number; updated?: number;
}

const ACTION: Record<Action, { label: string; cls: string }> = {
  NEW: { label: 'New', cls: 'bg-blue-100 text-blue-900 dark:bg-blue-950 dark:text-blue-100' },
  CHANGED: { label: 'Changed', cls: 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100' },
  UNCHANGED: { label: 'Unchanged', cls: 'bg-muted text-muted-foreground' },
  ERROR: { label: 'Error', cls: 'bg-red-100 text-red-900 dark:bg-red-950 dark:text-red-100' },
};
const oneLine = (v: string | null) => (v ? v.replace(/\s*\n\s*/g, ', ') : '(blank)');

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const j = (await res.json()) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Request failed');
  return j.data as T;
}

async function readFile(file: File): Promise<CustomerFileRow[]> {
  if (/\.xlsx$/i.test(file.name)) {
    const { default: ExcelJS } = await import('exceljs');
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(await file.arrayBuffer());
    return readCustomerSheet(wb);
  }
  if (/\.(csv|txt)$/i.test(file.name)) return parseCustomerCsv(await file.text());
  throw new Error('Pick a .csv or .xlsx file (old .xls files: save them as .xlsx first).');
}

/** Upload a customer file in the Export Customers layout, review what each row would do, then apply it. */
export function ImportCustomers({ tenantId }: { tenantId: number }) {
  const [file, setFile] = useState<File | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);
  const [detail, setDetail] = useState<ImportDetail | null>(null);
  const [filter, setFilter] = useState<Action | 'TODO'>('TODO');
  const [confirm, setConfirm] = useState(false);

  const upload = async () => {
    if (!file) return;
    setBusy(true); setMessage(null); setConfirm(false);
    try {
      const rows = await readFile(file);
      if (rows.length === 0) throw new Error('The file has no customer rows');
      const d = await call<ImportDetail>('/api/customers/import', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, file_name: file.name, rows }),
      });
      setDetail(d);
      setFilter(d.error_count > 0 ? 'ERROR' : 'TODO');
      setMessage({
        text: d.error_count > 0 ? `${d.error_count === 1 ? '1 row needs' : `${d.error_count} rows need`} fixing. Correct the file and upload it again.`
          : d.new_count + d.changed_count === 0 ? 'No changes: every customer in the file matches.' : 'Checked. Review the rows, then apply.',
        error: false,
      });
      setFile(null); if (fileInput.current) fileInput.current.value = '';
    } catch (e) {
      setMessage({ text: (e as Error).message, error: true });
    } finally { setBusy(false); }
  };

  const apply = async () => {
    if (!detail) return;
    setBusy(true); setMessage(null); setConfirm(false);
    try {
      const d = await call<ImportDetail>(`/api/customers/import/${detail.customer_import_id}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tenant_id: tenantId, action: 'apply' }),
      });
      setDetail(d);
      if (d.applied) setMessage({ text: `Applied: ${d.inserted} new and ${d.updated} changed customer${d.updated === 1 ? '' : 's'}.`, error: false });
      else { setFilter('ERROR'); setMessage({ text: d.message ?? 'Nothing was applied.', error: true }); }
    } catch (e) { setMessage({ text: (e as Error).message, error: true }); }
    finally { setBusy(false); }
  };

  const rows = detail ? detail.rows.filter((r) => (filter === 'TODO' ? r.row_action !== 'UNCHANGED' : r.row_action === filter)) : [];
  const todo = detail ? detail.new_count + detail.changed_count : 0;
  const applied = detail?.import_status === 'APPLIED';
  const filters: [Action | 'TODO', string, number][] = detail ? [
    ['TODO', 'Needs review', todo + detail.error_count], ['NEW', 'New', detail.new_count], ['CHANGED', 'Changed', detail.changed_count],
    ['UNCHANGED', 'Unchanged', detail.unchanged_count], ['ERROR', 'Errors', detail.error_count],
  ] : [];

  return (
    <div className="mx-auto max-w-7xl space-y-4 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Import Customers</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Upload a CSV or Excel file in the Export Customers layout. Each row is matched on customer number and checked; nothing changes until you apply.
          New numbers are added, existing customers are updated, no customer is deleted.
        </p>
      </div>

      <Card><CardContent className="space-y-4 pt-6">
        <div className="grid gap-4 sm:grid-cols-[minmax(16rem,28rem)_auto] sm:items-end">
          <div>
            <Label htmlFor="cimp-file" className="text-xs">Customer file (.csv or .xlsx)</Label>
            <Input id="cimp-file" ref={fileInput} type="file" accept=".csv,.txt,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </div>
          <Button onClick={upload} disabled={busy || !file} className="gap-1.5 justify-self-start"><Upload className="h-4 w-4" />{busy ? 'Working…' : 'Upload and check'}</Button>
        </div>
        <p className="text-xs text-muted-foreground">
          The first row must be the export header. Parents must already exist or be in the file. Blank flags, invoice copies, addresses, phone and email
          keep the current value; blank parent, billing, credit limit, delivery method and cutoff clear it. Pricing book is not imported.
        </p>
        {message && <p role="status" className={`text-sm ${message.error ? 'text-destructive' : 'text-foreground'}`}>{message.text}</p>}
      </CardContent></Card>

      {detail && (
        <Card><CardContent className="space-y-4 pt-6">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="space-y-1">
              <h2 className="text-lg font-medium">{detail.file_name ?? 'Uploaded file'}{applied && <span className="ml-2 rounded bg-green-100 px-2 py-0.5 text-xs font-medium text-green-900 dark:bg-green-950 dark:text-green-100">Applied</span>}</h2>
              <p className="text-sm">
                {detail.row_count} rows · {detail.new_count} new · {detail.changed_count} changed · {detail.unchanged_count} unchanged
                {detail.error_count > 0 && <span className="text-destructive"> · {detail.error_count} with errors</span>}
              </p>
            </div>
            {!applied && (
              <div className="flex flex-wrap items-center gap-2">
                {confirm ? (
                  <>
                    <span className="text-sm">Add {detail.new_count} and update {detail.changed_count} customers?</span>
                    <Button size="sm" onClick={apply} disabled={busy}>Apply</Button>
                    <Button size="sm" variant="outline" onClick={() => setConfirm(false)} disabled={busy}>Cancel</Button>
                  </>
                ) : (
                  <Button size="sm" className="gap-1.5" onClick={() => setConfirm(true)} disabled={busy || detail.error_count > 0 || todo === 0}
                    title={detail.error_count > 0 ? 'Fix the rows with errors and upload the file again' : todo === 0 ? 'Nothing to change' : undefined}>
                    <CheckCircle2 className="h-4 w-4" />Apply changes
                  </Button>
                )}
              </div>
            )}
          </div>

          <div className="flex flex-wrap gap-1.5" role="group" aria-label="Show rows">
            {filters.map(([key, label, n]) => (
              <Button key={key} size="sm" variant={filter === key ? 'secondary' : 'ghost'} onClick={() => setFilter(key)}>{label} ({n})</Button>
            ))}
          </div>

          <div className="max-h-[36rem] overflow-auto rounded-md border">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-muted text-left text-xs">
                <tr>
                  <th className="px-2 py-1.5">Row</th><th className="px-2 py-1.5">Customer no</th><th className="px-2 py-1.5">Name</th>
                  <th className="px-2 py-1.5">Type</th><th className="px-2 py-1.5">Parent no</th><th className="px-2 py-1.5">Status</th><th className="px-2 py-1.5">Changes / issues</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.row_number} className={`border-t align-top ${r.row_action === 'ERROR' ? 'bg-red-50 dark:bg-red-950/40' : ''}`}>
                    <td className="px-2 py-1 text-muted-foreground">{r.row_number}</td>
                    <td className="px-2 py-1">{r.customer_number}</td>
                    <td className="px-2 py-1">{r.customer_name}</td>
                    <td className="px-2 py-1">{r.customer_type}</td>
                    <td className="px-2 py-1">{r.parent_number}</td>
                    <td className="px-2 py-1"><span className={`rounded px-2 py-0.5 text-xs font-medium ${ACTION[r.row_action].cls}`}>{ACTION[r.row_action].label}</span></td>
                    <td className="px-2 py-1">
                      {r.changes.map((c) => (
                        <div key={c.field}><span className="font-medium">{columnLabel(c.field)}:</span> <span className="text-muted-foreground">{oneLine(c.from)}</span> → {oneLine(c.to)}</div>
                      ))}
                      {r.issue && <div className={r.row_action === 'ERROR' ? 'text-destructive' : 'text-muted-foreground'}>{r.issue}</div>}
                    </td>
                  </tr>
                ))}
                {rows.length === 0 && <tr><td colSpan={7} className="px-2 py-3 text-muted-foreground">No rows.</td></tr>}
              </tbody>
            </table>
          </div>
        </CardContent></Card>
      )}
    </div>
  );
}
