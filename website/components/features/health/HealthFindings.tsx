'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Play } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { GuardedLink as Link } from '@/components/layout/GuardedLink';
import { adminCall, adminPost, PageHead, useBanner } from '@/components/features/admin/adminShared';
import { HealthChecksSidebar } from '@/components/features/dashboard/HealthChecksSidebar';
import { cn } from '@/lib/utils';

interface Finding {
  log_id: number; check_code: string; check_name: string; category: string; type: 'Information' | 'Warning' | 'Error'; found_at: string;
  findings: string; record_type: string | null; record_name: string | null; remediation: string | null; link_path: string | null;
  fixed_at: string | null; fixed_by_name: string | null; can_inactivate: boolean;
}

const fmt = (v: string | null) => (v ? new Date(v).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : 'Never');

/**
 * Operations › Health Checks: the findings of the check picked in the sidebar (as on the Dashboard), its name, count and What to do
 * in the heading, one line per record with Open (fix it on the record; the next run clears the finding).
 * initialCheck (?check=code, from the Dashboard sidebar or Admin › Health) starts with that check picked; otherwise the first check in the sidebar
 * (errors first) is picked on the first load. One check is always picked while there are findings.
 * Items not ordered / Pricing books not used: people who may change items (books) tick records and Inactivate (Disable) them here.
 * canRun (Health Checks write access) shows Run Health Checks, which runs every enabled check. Enabling checks is in Admin › Health.
 */
export function HealthFindings({ tenantId, initialCheck = null, canRun = false }: { tenantId: number; initialCheck?: string | null; canRun?: boolean }) {
  const { notify, banner } = useBanner();
  const [findings, setFindings] = useState<Finding[]>([]);
  const [showFixed, setShowFixed] = useState(false);
  const [checkFilter, setCheckFilter] = useState<string | null>(initialCheck);
  const [picked, setPicked] = useState<Set<number>>(new Set());
  const [busy, setBusy] = useState<'run' | 'inactivate' | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const defaulted = useRef(initialCheck !== null);

  const load = useCallback(async () => {
    try {
      const list = await adminCall<Finding[]>(`/api/admin/health?tenant_id=${tenantId}&view=findings${showFixed ? '&fixed=1' : ''}`);
      setFindings(list);
      setPicked(new Set());
      // the list comes errors first, open before fixed: its first check is the sidebar's first
      if (!defaulted.current) { defaulted.current = true; setCheckFilter(list.find((f) => !f.fixed_at)?.check_code ?? null); }
    } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, showFixed, notify]);

  useEffect(() => { void load(); }, [load]);

  const checkName = findings.find((f) => f.check_code === checkFilter)?.check_name ?? checkFilter;
  const shown = findings.filter((f) => !checkFilter || f.check_code === checkFilter);
  const remediation = checkFilter ? shown[0]?.remediation : null;
  const actionable = shown.filter((f) => f.can_inactivate);
  const verb = actionable[0]?.record_type === 'PRICEBOOK' ? 'Disable' : 'Inactivate';
  const noun = actionable[0]?.record_type === 'PRICEBOOK' ? 'pricing book' : 'item';
  const pickedHere = actionable.filter((f) => picked.has(f.log_id)).map((f) => f.log_id);

  const pickCheck = (code: string | null) => { setCheckFilter(code); setPicked(new Set()); };
  const toggle = (id: number, on: boolean) => setPicked((p) => { const n = new Set(p); if (on) n.add(id); else n.delete(id); return n; });

  const run = async () => {
    setBusy('run');
    try {
      await adminPost('/api/admin/health', { tenant_id: tenantId, action: 'run' });
      await load();
      setRefreshKey((k) => k + 1);
      notify('Health checks ran.', 'success');
    } catch (e) { notify((e as Error).message, 'error'); }
    setBusy(null);
  };

  const inactivate = async () => {
    setConfirming(false);
    setBusy('inactivate');
    try {
      const n = await adminPost<number>('/api/admin/health', { tenant_id: tenantId, action: 'inactivate', log_ids: pickedHere });
      await load();
      setRefreshKey((k) => k + 1);
      notify(`${verb === 'Disable' ? 'Disabled' : 'Inactivated'} ${n} ${noun}${n === 1 ? '' : 's'}.`, 'success');
    } catch (e) { notify((e as Error).message, 'error'); }
    setBusy(null);
  };

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-2 sm:p-3">
      <div className="flex items-start justify-between gap-3">
        <PageHead title="Health Checks">
          What the setup and data checks found. Open a record and fix it there; the next run of the checks clears the finding.
        </PageHead>
        {canRun && (
          <Button size="sm" className="shrink-0 gap-1.5" disabled={busy !== null} onClick={() => void run()}>
            <Play className="h-3.5 w-3.5" />{busy === 'run' ? 'Running…' : 'Run Health Checks'}
          </Button>
        )}
      </div>
      {banner}
      <HealthChecksSidebar selected={checkFilter} onSelect={pickCheck} refreshKey={refreshKey} />

      <Card><CardContent className="space-y-3 pt-6">
        <div className="flex flex-wrap items-center gap-4">
          <div className="mr-auto">
            <h2 className="text-lg font-medium">{checkFilter ? <>{checkName} ({shown.length})</> : <>All findings ({shown.length})</>}</h2>
            {remediation && <p className="text-xs text-muted-foreground"><span className="font-semibold">What to do:</span> {remediation}</p>}
          </div>
          {actionable.length > 0 && (
            <Button size="sm" variant="outline" disabled={pickedHere.length === 0 || busy !== null} onClick={() => setConfirming(true)}>
              {busy === 'inactivate' ? `${verb === 'Disable' ? 'Disabling' : 'Inactivating'}…` : `${verb}${pickedHere.length ? ` (${pickedHere.length})` : ''}`}
            </Button>
          )}
          <label className="flex items-center gap-1.5 text-sm"><Checkbox checked={showFixed} onCheckedChange={(v) => setShowFixed(v === true)} />Show fixed (30 days)</label>
        </div>
        <div className="overflow-x-auto rounded-md border">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs">
              <tr>
                {actionable.length > 0 && (
                  <th className="w-10 px-3 py-2">
                    <Checkbox aria-label={`Select all ${noun}s`} checked={pickedHere.length === actionable.length ? true : pickedHere.length ? 'indeterminate' : false}
                      onCheckedChange={(v) => setPicked(v === true ? new Set(actionable.map((f) => f.log_id)) : new Set())} />
                  </th>
                )}
                <th className="px-3 py-2">Customer or finding</th><th className="px-3 py-2">Found</th><th className="w-24 px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {shown.map((f) => (
                <tr key={f.log_id} className={cn('border-t align-top', f.fixed_at && 'opacity-50')}>
                  {actionable.length > 0 && (
                    <td className="px-3 py-1.5">
                      {f.can_inactivate && <Checkbox aria-label={`Select ${f.findings}`} checked={picked.has(f.log_id)} onCheckedChange={(v) => toggle(f.log_id, v === true)} />}
                    </td>
                  )}
                  <td className="px-3 py-1.5">{f.record_name ?? f.findings}</td>
                  <td className="whitespace-nowrap px-3 py-1.5 text-xs text-muted-foreground">{fmt(f.found_at)}</td>
                  <td className="px-3 py-1.5 text-right">
                    {f.fixed_at ? <span className="text-xs text-muted-foreground">Fixed {fmt(f.fixed_at)}{f.fixed_by_name ? ` by ${f.fixed_by_name}` : ''}</span> : (
                      f.link_path && <Link href={f.link_path} className="text-sm text-primary underline-offset-2 hover:underline">Open</Link>
                    )}
                  </td>
                </tr>
              ))}
              {shown.length === 0 && <tr><td colSpan={actionable.length > 0 ? 4 : 3} className="px-3 py-4 text-muted-foreground">No findings.</td></tr>}
            </tbody>
          </table>
        </div>
      </CardContent></Card>

      <AlertDialog open={confirming} onOpenChange={setConfirming}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{verb} {pickedHere.length} {noun}{pickedHere.length === 1 ? '' : 's'}?</AlertDialogTitle>
            <AlertDialogDescription>
              {noun === 'item'
                ? 'They will no longer appear for ordering. You can make an item active again on Item Management.'
                : 'Their customers will no longer be priced from them. You can enable a book again on the Pricing Books page.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => void inactivate()}>{verb}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
