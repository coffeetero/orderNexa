'use client';

import { Fragment, useCallback, useEffect, useState } from 'react';
import { Play } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { GuardedLink as Link } from '@/components/layout/GuardedLink';
import { adminCall, adminPost, PageHead, useBanner } from '@/components/features/admin/adminShared';
import { cn } from '@/lib/utils';

interface Check {
  check_code: string; name: string; category: 'Setup' | 'Data'; description: string | null; runs_before_production: boolean;
  is_enabled: boolean; last_run_at: string | null; infos: number; warnings: number; errors: number;
}
const fmt = (v: string | null) => (v ? new Date(v).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : 'Never');
const count = (n: number, cls: string) => <span className={cn('tabular-nums', n > 0 ? cls : 'text-muted-foreground')}>{n}</span>;

/** Admin › Health: the checks (enable, run, last counts). A check's name opens its findings on Operations › Health Checks. */
export function HealthChecksAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [checks, setChecks] = useState<Check[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setChecks(await adminCall<Check[]>(`/api/admin/health?tenant_id=${tenantId}`));
    } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);

  useEffect(() => { void load(); }, [load]);

  const run = async (code?: string) => {
    setBusy(code ?? 'all');
    try {
      await adminPost('/api/admin/health', { tenant_id: tenantId, action: 'run', check_code: code });
      await load();
      notify(code ? 'Check finished.' : 'All enabled checks finished.', 'success');
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(null); }
  };

  const setEnabled = async (code: string, enabled: boolean) => {
    try {
      await adminPost('/api/admin/health', { tenant_id: tenantId, action: 'enable', check_code: code, enabled });
      setChecks((cs) => cs.map((c) => (c.check_code === code ? { ...c, is_enabled: enabled } : c)));
    } catch (e) { notify((e as Error).message, 'error'); }
  };

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-2 sm:p-3">
      <div className="flex items-start justify-between gap-3">
        <PageHead title="Health Checks">
          Setup and data checks run automatically every night at midnight (company time). Run them any time, for example after changing setup or right before a Production Run.
          The heart is red with open errors, orange with warnings, blue with information only, and green when nothing is open.
        </PageHead>
        <Button size="sm" className="shrink-0 gap-1.5" disabled={busy !== null} onClick={() => void run()}><Play className="h-3.5 w-3.5" />{busy === 'all' ? 'Running…' : 'Run all'}</Button>
      </div>
      {banner}

      <Card><CardContent className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs">
              <tr><th className="w-16 px-3 py-2 text-center">Enabled</th><th className="px-3 py-2">Check</th><th className="px-3 py-2">Last run</th>
                <th className="px-3 py-2 text-center">Info</th><th className="px-3 py-2 text-center">Warnings</th><th className="px-3 py-2 text-center">Errors</th><th className="w-20 px-3 py-2" /></tr>
            </thead>
            <tbody>
              {checks.map((c, i) => (
                <Fragment key={c.check_code}>
                  {(i === 0 || checks[i - 1].category !== c.category) && (
                    <tr className="border-t border-l-4 border-l-primary bg-muted"><td colSpan={7} className="px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-primary">{c.category}</td></tr>
                  )}
                  <tr className={cn('border-t', !c.is_enabled && 'opacity-50')}>
                    <td className="px-3 py-2 text-center"><Checkbox checked={c.is_enabled} onCheckedChange={(v) => void setEnabled(c.check_code, v === true)} aria-label={`${c.name} enabled`} /></td>
                    <td className="px-3 py-2">
                      <div className="font-medium">
                        <Link href={`/production/health-checks?check=${encodeURIComponent(c.check_code)}`} title="Show this check's findings (Operations › Health Checks)" className="hover:underline">{c.name}</Link>
                        {c.runs_before_production && <span className="ml-2 rounded-full bg-muted px-2 py-0.5 text-[10px] font-medium uppercase text-muted-foreground">Before Production Run</span>}</div>
                      {c.description && <div className="text-xs text-muted-foreground">{c.description}</div>}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2 text-xs text-muted-foreground">{fmt(c.last_run_at)}</td>
                    <td className="px-3 py-2 text-center">{count(c.infos, 'text-foreground')}</td>
                    <td className="px-3 py-2 text-center">{count(c.warnings, 'font-semibold text-warning')}</td>
                    <td className="px-3 py-2 text-center">{count(c.errors, 'font-semibold text-destructive')}</td>
                    <td className="px-3 py-2 text-right"><Button size="sm" variant="outline" disabled={busy !== null || !c.is_enabled} onClick={() => void run(c.check_code)}>{busy === c.check_code ? '…' : 'Run'}</Button></td>
                  </tr>
                </Fragment>
              ))}
              {checks.length === 0 && <tr><td colSpan={7} className="px-3 py-4 text-muted-foreground">Loading…</td></tr>}
            </tbody>
          </table>
        </div>
      </CardContent></Card>

    </div>
  );
}
