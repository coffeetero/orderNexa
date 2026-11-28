'use client';

import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { AlertCircle, AlertTriangle, CheckCircle2, ChevronDown, Info } from 'lucide-react';
import { GuardedLink as Link } from '@/components/layout/GuardedLink';
import { useNav } from '@/components/layout/nav-context';
import { cn } from '@/lib/utils';

type FindingType = 'Error' | 'Warning' | 'Information';
interface Finding { log_id: number; check_code: string; check_name: string; type: FindingType; findings: string; link_path: string | null }
interface Status { state: 'none' | 'never' | 'ok' | 'warning' | 'error'; last_run_at: string | null }

const TYPES: { type: FindingType; label: string; Icon: typeof Info; cls: string }[] = [
  { type: 'Error', label: 'Errors', Icon: AlertCircle, cls: 'text-destructive' },
  { type: 'Warning', label: 'Warnings', Icon: AlertTriangle, cls: 'text-warning' },
  { type: 'Information', label: 'Information', Icon: Info, cls: 'text-info' },
];
const ADMIN_HREF = '/admin/health';

/** Dashboard sidebar: the open health check findings counted by type, then by check. A check opens Admin › Health filtered to it; Open opens the page. */
export function HealthChecksSidebar() {
  const { tenantId, sidebarSlot } = useNav();
  const [status, setStatus] = useState<Status | null>(null);
  const [findings, setFindings] = useState<Finding[] | null>(null);
  const [folded, setFolded] = useState<Partial<Record<FindingType, boolean>>>({});

  useEffect(() => {
    if (tenantId === null) return;
    const ac = new AbortController();
    Promise.all([
      fetch('/api/health/status', { signal: ac.signal }).then((r) => r.json()),
      fetch(`/api/admin/health?tenant_id=${tenantId}&view=findings`, { signal: ac.signal }).then((r) => r.json()),
    ])
      .then(([s, f]: [{ data?: Status }, { data?: Finding[] }]) => {
        const list = Array.isArray(f.data) ? f.data : [];
        setStatus(s.data ?? null);
        setFindings(list);
        setFolded({ Information: list.some((x) => x.type === 'Error') });
      })
      .catch(() => { /* the sidebar stays empty */ });
    return () => ac.abort();
  }, [tenantId]);

  if (!sidebarSlot || !status || status.state === 'none' || findings === null) return null;

  const lastRun = status.last_run_at
    ? `Last run ${new Date(status.last_run_at).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })} · ${findings.length} open`
    : 'Not run yet';

  return createPortal(
    <section aria-label="Health Checks" className="border-t border-border pt-3">
      <div className="flex items-center justify-between px-2">
        <h2 className="text-[13.5px] font-bold uppercase tracking-wider text-muted-foreground">Health Checks</h2>
        <Link href={ADMIN_HREF} className="rounded px-1 text-xs font-semibold text-primary hover:underline">Open</Link>
      </div>
      <p className="px-2 pb-2 text-[11.5px] text-muted-foreground">{lastRun}</p>

      {status.state === 'never' ? (
        <p className="px-2 text-xs text-muted-foreground">The checks have not run yet. Run them in <Link href={ADMIN_HREF} className="font-semibold text-primary hover:underline">Admin › Health</Link>.</p>
      ) : findings.length === 0 ? (
        <p className="flex items-start gap-2 px-2 text-xs text-muted-foreground"><CheckCircle2 className="h-4 w-4 shrink-0 text-success" aria-hidden />No open findings. All checks passed.</p>
      ) : TYPES.map(({ type, label, Icon, cls }) => {
        const rows = findings.filter((f) => f.type === type);
        const checks = [...new Set(rows.map((f) => f.check_code))];
        const open = !folded[type];
        return (
          <div key={type} className="border-t border-border pt-[3px]">
            <button type="button" aria-expanded={open} onClick={() => setFolded((p) => ({ ...p, [type]: open }))}
              className="flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-[15px] font-bold hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              <span>{label}</span>
              <Icon className={cn('h-4 w-4 shrink-0', cls)} aria-hidden />
              <span className="flex-1" />
              <ChevronDown className={cn('h-3 w-3 shrink-0 text-muted-foreground transition-transform', !open && '-rotate-90')} aria-hidden />
            </button>
            {open && (
              <div className="pb-1.5">
                {rows.length === 0 && <p className="pb-1 pl-4 pr-2 text-xs text-muted-foreground">None open</p>}
                <div className="ml-3 mr-2">
                  {checks.map((code) => {
                    const items = rows.filter((f) => f.check_code === code);
                    return (
                      <Link key={code} href={`${ADMIN_HREF}?check=${encodeURIComponent(code)}`}
                        className="flex items-baseline gap-2 py-[5.5px] pl-1 pr-1 text-sm leading-5 text-foreground hover:bg-muted hover:text-primary">
                        <span className="min-w-0 flex-1">{items[0].check_name}</span>
                        <span className="tabular-nums text-muted-foreground">{items.length}</span>
                      </Link>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        );
      })}
    </section>,
    sidebarSlot,
  );
}
