'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';

interface SheetRow {
  sheet_id: number;
  sheet_name: string;
  visibility: 'PRIVATE' | 'SHARED';
  owner_name: string;
  is_owner: boolean;
  updated_at: string;
  updated_by_name: string | null;
}

const fmt = (iso: string) => new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });

export function SheetsList({ tenantId }: { tenantId: number }) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [rows, setRows] = useState<SheetRow[] | null>(null);
  const [search, setSearch] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirmId, setConfirmId] = useState<number | null>(null);

  const load = useCallback(() => {
    fetch(`/api/organizer/sheets?tenant_id=${tenantId}`)
      .then((r) => r.json())
      .then((j: { data?: SheetRow[]; error?: string }) => {
        if (j.error) throw new Error(j.error);
        setRows(j.data ?? []);
      })
      .catch((e: Error) => setError(e.message));
  }, [tenantId]);
  useEffect(load, [load]);

  const importFile = async (file: File) => {
    setBusy(true);
    setError(null);
    try {
      if (!/\.xlsx$/i.test(file.name)) throw new Error('Pick an Excel .xlsx file. Old .xls files: open them in Excel and save as .xlsx.');
      const [{ default: ExcelJS }, { fromExcel }] = await Promise.all([import('exceljs'), import('@/lib/organizer/xlsx')]);
      const wb = new ExcelJS.Workbook();
      await wb.xlsx.load(await file.arrayBuffer());
      const name = file.name.replace(/\.xlsx$/i, '').slice(0, 200) || 'Imported sheet';
      const res = await fetch('/api/organizer/sheets', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, sheet_name: name, visibility: 'PRIVATE', workbook: fromExcel(wb, name) }),
      });
      const j = (await res.json()) as { data?: { sheet_id: number }; error?: string };
      if (!res.ok || j.error || !j.data) throw new Error(j.error ?? 'Import failed');
      router.push(`/organizer/sheets/${j.data.sheet_id}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    } finally {
      if (fileRef.current) fileRef.current.value = '';
    }
  };

  const remove = async (id: number) => {
    setError(null);
    const res = await fetch(`/api/organizer/sheets/${id}?tenant_id=${tenantId}`, { method: 'DELETE' });
    const j = (await res.json()) as { error?: string };
    setConfirmId(null);
    if (!res.ok || j.error) setError(j.error ?? 'Delete failed');
    else load();
  };

  const shown = (rows ?? []).filter((r) => r.sheet_name.toLowerCase().includes(search.trim().toLowerCase()));

  return (
    <div className="mx-auto max-w-5xl space-y-4 p-2 sm:p-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Sheets</h1>
          <p className="text-sm text-muted-foreground">
            Spreadsheets kept in BPS. Private sheets are yours; shared sheets are open to everyone at the company with Sheets access.
          </p>
        </div>
        <div className="flex gap-2">
          <input ref={fileRef} type="file" accept=".xlsx" className="hidden" onChange={(e) => e.target.files?.[0] && importFile(e.target.files[0])} />
          <Button variant="outline" disabled={busy} onClick={() => fileRef.current?.click()}>{busy ? 'Importing…' : 'Import .xlsx'}</Button>
          <Button asChild><Link href="/organizer/sheets/new">New sheet</Link></Button>
        </div>
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}

      <Card><CardContent className="pt-6">
        <Input placeholder="Search by name" value={search} onChange={(e) => setSearch(e.target.value)} className="mb-3 max-w-xs" />
        {rows === null ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : shown.length === 0 ? (
          <p className="text-sm text-muted-foreground">{rows.length === 0 ? 'No sheets yet. Create one or import an Excel file.' : 'No sheet matches.'}</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-xs text-muted-foreground">
                <th className="px-2 py-1 font-medium">Name</th>
                <th className="px-2 py-1 font-medium">Visibility</th>
                <th className="px-2 py-1 font-medium">Owner</th>
                <th className="px-2 py-1 font-medium">Last saved</th>
                <th className="px-2 py-1" />
              </tr>
            </thead>
            <tbody>
              {shown.map((r) => (
                <tr key={r.sheet_id} className="border-b">
                  <td className="px-2 py-1.5"><Link className="font-medium hover:underline" href={`/organizer/sheets/${r.sheet_id}`}>{r.sheet_name}</Link></td>
                  <td className="px-2 py-1.5">
                    <span className={`rounded px-2 py-0.5 text-xs font-medium ${r.visibility === 'SHARED' ? 'bg-sky-100 text-sky-800 dark:bg-sky-900/40 dark:text-sky-200' : 'bg-muted text-muted-foreground'}`}>
                      {r.visibility === 'SHARED' ? 'Shared' : 'Private'}
                    </span>
                  </td>
                  <td className="px-2 py-1.5">{r.is_owner ? 'You' : r.owner_name}</td>
                  <td className="px-2 py-1.5 text-muted-foreground">{fmt(r.updated_at)}{r.updated_by_name && !r.is_owner ? ` · ${r.updated_by_name}` : ''}</td>
                  <td className="px-2 py-1.5 text-right">
                    {r.is_owner && (confirmId === r.sheet_id ? (
                      <span className="space-x-2 text-xs">
                        <span>Delete for good?</span>
                        <Button size="sm" variant="destructive" onClick={() => remove(r.sheet_id)}>Delete</Button>
                        <Button size="sm" variant="ghost" onClick={() => setConfirmId(null)}>Keep</Button>
                      </span>
                    ) : (
                      <Button size="sm" variant="ghost" onClick={() => setConfirmId(r.sheet_id)}>Delete</Button>
                    ))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </CardContent></Card>
    </div>
  );
}
