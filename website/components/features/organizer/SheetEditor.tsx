'use client';

import '@univerjs/preset-sheets-core/lib/index.css';
import Link from 'next/link';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { BPS_FUNCTIONS, createBpsClient, resultToCell, toArg, type BpsResult } from '@/lib/organizer/bps-functions';
import { emptyWorkbook, toExcel, toPrintHtml, type WorkbookData } from '@/lib/organizer/xlsx';

interface Meta { sheet_id: number | null; sheet_name: string; visibility: 'PRIVATE' | 'SHARED'; version: number | null; is_owner: boolean; owner_name?: string }
// The spreadsheet's API object (Univer facade); only the few calls below are used.
type SheetApi = {
  getActiveWorkbook: () => { save: () => WorkbookData } | null;
};

export function SheetEditor({ tenantId, sheetId }: { tenantId: number; sheetId: number | null }) {
  const host = useRef<HTMLDivElement>(null);
  const api = useRef<SheetApi | null>(null);
  const [meta, setMeta] = useState<Meta | null>(null);
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ text: string; error?: boolean } | null>(null);
  const [showHelp, setShowHelp] = useState(false);

  // load the sheet, then start the spreadsheet in the page
  useEffect(() => {
    let disposed = false;
    let dispose: (() => void) | null = null;
    (async () => {
      try {
        let book: WorkbookData;
        if (sheetId === null) {
          book = emptyWorkbook('Untitled sheet');
          setMeta({ sheet_id: null, sheet_name: 'Untitled sheet', visibility: 'PRIVATE', version: null, is_owner: true });
        } else {
          const j = (await (await fetch(`/api/organizer/sheets?tenant_id=${tenantId}&id=${sheetId}`)).json()) as { data?: Meta & { workbook: WorkbookData }; error?: string };
          if (j.error || !j.data) throw new Error(j.error ?? 'Could not open the sheet');
          const { workbook, ...m } = j.data;
          book = workbook;
          setMeta(m);
        }
        const [{ createUniver, LocaleType, mergeLocales }, { UniverSheetsCorePreset }, { default: enUS }] = await Promise.all([
          import('@univerjs/presets'), import('@univerjs/preset-sheets-core'), import('@univerjs/preset-sheets-core/locales/en-US'),
        ]);
        if (disposed || !host.current) return;
        const { univer, univerAPI } = createUniver({
          locale: LocaleType.EN_US,
          locales: { [LocaleType.EN_US]: mergeLocales(enUS) },
          presets: [UniverSheetsCorePreset({ container: host.current })],
        });
        const bps = createBpsClient(async (calls) => {
          const res = await fetch('/api/organizer/sheets/bps', {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tenant_id: tenantId, calls }),
          });
          const j = (await res.json()) as { data?: BpsResult[]; error?: string };
          if (!res.ok || j.error) throw new Error(j.error ?? 'BPS functions failed');
          return j.data ?? [];
        });
        const formula = univerAPI.getFormula();
        for (const f of BPS_FUNCTIONS) {
          formula.registerAsyncFunction(`BPS.${f.name}`, async (...args: unknown[]) =>
            resultToCell(await bps({ fn: f.name, args: args.map((a, i) => toArg(a, f.dateArgs.includes(i))) })), f.help);
        }
        univerAPI.createWorkbook(book as never);
        univerAPI.addEvent(univerAPI.Event.SheetValueChanged, () => setDirty(true));
        api.current = univerAPI as unknown as SheetApi;        dispose = () => univer.dispose();
      } catch (e) {
        setMessage({ text: (e as Error).message, error: true });
      }
    })();
    return () => { disposed = true; api.current = null; dispose?.(); };
  }, [tenantId, sheetId]);

  const snapshot = () => api.current?.getActiveWorkbook()?.save() ?? null;

  const save = useCallback(async () => {
    const book = api.current?.getActiveWorkbook()?.save();
    if (!book || !meta) return;
    setBusy(true);
    setMessage(null);
    try {
      const res = await fetch('/api/organizer/sheets', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, sheet_id: meta.sheet_id, sheet_name: meta.sheet_name, visibility: meta.visibility, version: meta.version, workbook: book }),
      });
      const j = (await res.json()) as { data?: { sheet_id: number; version: number }; error?: string };
      if (!res.ok || j.error || !j.data) throw new Error(j.error ?? 'Save failed');
      const saved = j.data;
      if (meta.sheet_id === null) window.history.replaceState(null, '', `/organizer/sheets/${saved.sheet_id}`);
      setMeta((m) => (m ? { ...m, sheet_id: saved.sheet_id, version: saved.version } : m));
      setDirty(false);
      setMessage({ text: 'Saved' });
    } catch (e) {
      setMessage({ text: (e as Error).message, error: true });
    } finally {
      setBusy(false);
    }
  }, [meta, tenantId]);

  // Ctrl/Cmd+S saves; warn before leaving with unsaved changes
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's') { e.preventDefault(); void save(); }
    };
    const onLeave = (e: BeforeUnloadEvent) => { if (dirty) { e.preventDefault(); e.returnValue = ''; } };
    window.addEventListener('keydown', onKey);
    window.addEventListener('beforeunload', onLeave);
    return () => { window.removeEventListener('keydown', onKey); window.removeEventListener('beforeunload', onLeave); };
  }, [save, dirty]);

  const exportXlsx = async () => {
    const book = snapshot();
    if (!book || !meta) return;
    const { default: ExcelJS } = await import('exceljs');
    const buf = await toExcel(book, ExcelJS).xlsx.writeBuffer();
    const url = URL.createObjectURL(new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `${meta.sheet_name.replace(/[\\/:*?"<>|]/g, '_')}.xlsx`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const print = () => {
    const book = snapshot();
    if (!book || !meta) return;
    const frame = document.createElement('iframe');
    frame.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0';
    frame.srcdoc = toPrintHtml(book, meta.sheet_name);
    frame.onload = () => { frame.contentWindow?.print(); setTimeout(() => frame.remove(), 1000); };
    document.body.appendChild(frame);
  };

  const setName = (sheet_name: string) => { setMeta((m) => (m ? { ...m, sheet_name } : m)); setDirty(true); };
  const setVisibility = (visibility: Meta['visibility']) => { setMeta((m) => (m ? { ...m, visibility } : m)); setDirty(true); };

  return (
    <div className="flex h-[calc(100vh-4rem)] flex-col gap-2 p-2">
      <div className="flex flex-wrap items-center gap-2">
        <Link href="/organizer/sheets" className="text-sm text-muted-foreground hover:underline">Sheets</Link>
        <span className="text-muted-foreground">/</span>
        <Input
          aria-label="Sheet name" className="h-8 w-64" value={meta?.sheet_name ?? ''} disabled={!meta?.is_owner}
          onChange={(e) => setName(e.target.value)} title={meta?.is_owner ? undefined : 'Only the owner can rename it'}
        />
        <select
          aria-label="Who can see it" className="h-8 rounded-md border border-input bg-background px-2 text-sm"
          value={meta?.visibility ?? 'PRIVATE'} disabled={!meta?.is_owner} onChange={(e) => setVisibility(e.target.value as Meta['visibility'])}
        >
          <option value="PRIVATE">Private (only me)</option>
          <option value="SHARED">Shared (everyone at the company)</option>
        </select>
        {meta && !meta.is_owner && meta.owner_name && <span className="text-xs text-muted-foreground">Owner: {meta.owner_name}</span>}
        <div className="ml-auto flex items-center gap-2">
          {message && <span role={message.error ? 'alert' : 'status'} className={`text-xs ${message.error ? 'text-destructive' : 'text-muted-foreground'}`}>{message.text}</span>}
          {dirty && !message?.error && <span className="text-xs text-amber-700 dark:text-amber-400">Unsaved changes</span>}
          <Button size="sm" variant="ghost" onClick={() => setShowHelp((v) => !v)}>BPS functions</Button>
          <Button size="sm" variant="outline" onClick={print} disabled={!meta}>Print</Button>
          <Button size="sm" variant="outline" onClick={exportXlsx} disabled={!meta}>Export .xlsx</Button>
          <Button size="sm" variant="outline" disabled title="Sending needs the email connector">Send</Button>
          <Button size="sm" onClick={save} disabled={busy || !meta || !meta.sheet_name.trim()}>{busy ? 'Saving…' : 'Save'}</Button>
        </div>
      </div>
      {showHelp && (
        <div className="rounded-md border bg-muted/40 p-3 text-xs">
          <p className="mb-1 font-medium">Live BPS values (recalculated when the sheet opens; printed and exported copies keep the values of that moment)</p>
          <ul className="grid gap-0.5 sm:grid-cols-2">
            {BPS_FUNCTIONS.map((f) => <li key={f.name}><code>={f.help.split(':')[0]}</code>: {f.help.split(': ')[1]}</li>)}
          </ul>
          <p className="mt-1 text-muted-foreground">Example: <code>=BPS.SALES(TODAY()-7, TODAY())</code>. A value you are not allowed to see shows #ACCESS.</p>
        </div>
      )}
      <div ref={host} className="min-h-0 flex-1 overflow-hidden rounded-md border" />
    </div>
  );
}
