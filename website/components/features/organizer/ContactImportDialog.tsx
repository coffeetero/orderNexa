'use client';

import { useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { parseContactsFile, type ContactInput } from '@/lib/organizer/contacts';
import { api } from './contacts-ui';

interface ImportResult {
  rows: { row: number; status: 'NEW' | 'CREATED' | 'DUPLICATE' | 'INVALID'; message?: string }[];
  new: number; duplicate: number; invalid: number;
}

const STATUS: Record<string, string> = { NEW: 'New', CREATED: 'Added', DUPLICATE: 'Skipped: duplicate', INVALID: 'Not imported' };
const nameOf = (c: ContactInput) => [c.first_name, c.last_name].filter(Boolean).join(' ') || c.company_name || c.nickname || '(no name)';

export function ContactImportDialog({ tenantId, open, onOpenChange, onImported }: {
  tenantId: number; open: boolean; onOpenChange: (o: boolean) => void; onImported: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [fileName, setFileName] = useState('');
  const [rows, setRows] = useState<ContactInput[]>([]);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reset = () => { setFileName(''); setRows([]); setResult(null); setDone(false); setError(null); };

  const pick = async (file: File) => {
    reset();
    setBusy(true);
    try {
      const parsed = parseContactsFile(file.name, await file.text());
      if (parsed.length === 0) throw new Error('No contacts found. Pick a vCard (.vcf) or a Google / Outlook CSV export.');
      setFileName(file.name);
      setRows(parsed);
      setResult(await api<ImportResult>('/api/organizer/contacts/import', 'POST', { tenant_id: tenantId, rows: parsed, commit: false }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  };

  const commit = async () => {
    setBusy(true);
    setError(null);
    try {
      setResult(await api<ImportResult>('/api/organizer/contacts/import', 'POST', { tenant_id: tenantId, rows, commit: true }));
      setDone(true);
      onImported();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) reset(); onOpenChange(o); }}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle>Import contacts</DialogTitle>
          <DialogDescription>
            vCard (.vcf) from iPhone or Google, or a CSV exported from Google Contacts or Outlook. Imported contacts are company
            contacts; anyone already in the address book (same name, email or phone) is skipped.
          </DialogDescription>
        </DialogHeader>
        <div className="flex items-center gap-3">
          <input ref={fileRef} type="file" accept=".vcf,.vcard,.csv,text/vcard,text/csv" className="hidden"
            onChange={(e) => e.target.files?.[0] && pick(e.target.files[0])} />
          <Button variant="outline" disabled={busy} onClick={() => fileRef.current?.click()}>{fileName ? 'Pick another file' : 'Pick a file'}</Button>
          <span className="truncate text-sm text-muted-foreground">{busy ? 'Reading…' : fileName}</span>
        </div>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        {result && (
          <>
            <p className="text-sm">
              {done ? `Added ${result.new}` : `${result.new} to add`} · {result.duplicate} duplicate{result.duplicate === 1 ? '' : 's'} skipped
              {result.invalid > 0 && ` · ${result.invalid} with problems`}
            </p>
            <div className="max-h-[50vh] overflow-auto rounded border">
              <table className="w-full text-sm">
                <thead className="sticky top-0 bg-background">
                  <tr className="border-b text-left text-xs text-muted-foreground">
                    <th className="px-2 py-1 font-medium">#</th>
                    <th className="px-2 py-1 font-medium">Name</th>
                    <th className="px-2 py-1 font-medium">Company</th>
                    <th className="px-2 py-1 font-medium">Email / phone</th>
                    <th className="px-2 py-1 font-medium">Result</th>
                  </tr>
                </thead>
                <tbody>
                  {result.rows.map((r) => {
                    const c = rows[r.row - 1];
                    const first = c?.points.find((p) => p.type === 'EMAIL') ?? c?.points.find((p) => p.type !== 'ADDRESS');
                    return (
                      <tr key={r.row} className="border-b">
                        <td className="px-2 py-1 text-muted-foreground">{r.row}</td>
                        <td className="px-2 py-1">{c ? nameOf(c) : ''}</td>
                        <td className="px-2 py-1">{c?.company_name ?? ''}</td>
                        <td className="px-2 py-1">{first?.value ?? ''}</td>
                        <td className={`px-2 py-1 ${r.status === 'INVALID' ? 'text-destructive' : r.status === 'DUPLICATE' ? 'text-muted-foreground' : ''}`}>
                          {STATUS[r.status]}{r.message ? `: ${r.message}` : ''}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </>
        )}
        <DialogFooter>
          <Button variant="ghost" onClick={() => { reset(); onOpenChange(false); }}>{done ? 'Close' : 'Cancel'}</Button>
          {!done && <Button disabled={busy || !result || result.new === 0} onClick={commit}>{busy ? 'Importing…' : `Import ${result?.new ?? ''}`}</Button>}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
