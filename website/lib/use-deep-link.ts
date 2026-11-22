'use client';

import { useEffect, useRef } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { parseIdParam } from '@/lib/nav-records';

/**
 * Lets the sidebar open a record on the page you are already on: `/customers?customer=10700`.
 * Once `ready` (the page's data has loaded) it calls `onId(id)` through the page's own selection handler,
 * then removes the parameter from the URL so the same link works again later.
 */
export function useDeepLinkId(param: string, ready: boolean, onId: (id: number) => void) {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const id = parseIdParam(searchParams.get(param));
  const handler = useRef(onId);
  handler.current = onId;

  useEffect(() => {
    if (id === null || !ready) return;
    router.replace(pathname, { scroll: false });
    handler.current(id);
  }, [id, ready, pathname, router]);
}
