'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';

const KEY = 'bps.activity.sent';
const EVERY_MS = 5 * 60_000;

/**
 * Tells the server this person is using BPS (/api/activity): on opening a page, at most once every 5 minutes per browser tab.
 * Renders nothing. Mounted by the staff and customer layouts.
 */
export function ActivityPing() {
  const pathname = usePathname();
  useEffect(() => {
    let last = 0;
    try { last = Number(sessionStorage.getItem(KEY) || 0); } catch { /* private window: send anyway */ }
    if (Date.now() - last < EVERY_MS) return;
    try { sessionStorage.setItem(KEY, String(Date.now())); } catch { /* not remembered */ }
    fetch('/api/activity', { method: 'POST', keepalive: true }).catch(() => { /* best effort */ });
  }, [pathname]);
  return null;
}
