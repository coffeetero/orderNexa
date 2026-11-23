'use client';

import { useCallback, useEffect, useState } from 'react';
import { Heart } from 'lucide-react';
import { GuardedLink as Link } from '@/components/layout/GuardedLink';
import { cn } from '@/lib/utils';

type Status = { state: 'none' | 'never' | 'ok' | 'warning' | 'error'; infos: number; warnings: number; errors: number; last_run_at: string | null };

const REFRESH_MS = 5 * 60 * 1000;

/** The health heart: grey never run, green clean, yellow warnings, red and blinking errors. Click opens the Health Checks page. */
export function HealthHeart({ href }: { href: string }) {
  const [status, setStatus] = useState<Status | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await fetch('/api/health/status');
      const json = (await res.json()) as { data?: Status };
      if (res.ok && json.data) setStatus(json.data);
    } catch { /* leave the last known state */ }
  }, []);

  useEffect(() => {
    void load();
    const timer = setInterval(load, REFRESH_MS);
    window.addEventListener('focus', load);
    return () => { clearInterval(timer); window.removeEventListener('focus', load); };
  }, [load]);

  if (!status || status.state === 'none') return null;

  const label =
    status.state === 'never' ? 'Health checks have not run yet'
    : status.state === 'ok' ? 'Health checks: no problems'
    : `Health checks: ${status.errors} error${status.errors === 1 ? '' : 's'}, ${status.warnings} warning${status.warnings === 1 ? '' : 's'}`;

  return (
    <Link href={href} aria-label={label} title={label}
      className="inline-flex h-9 w-9 items-center justify-center rounded-md hover:bg-muted">
      <Heart
        className={cn('h-4 w-4',
          status.state === 'never' && 'text-muted-foreground',
          status.state === 'ok' && 'fill-success/30 text-success',
          status.state === 'warning' && 'fill-warning/30 text-warning',
          status.state === 'error' && 'animate-pulse fill-destructive/40 text-destructive motion-reduce:animate-none')}
      />
    </Link>
  );
}
