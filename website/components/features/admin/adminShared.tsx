'use client';

import { useCallback, useState } from 'react';

export async function adminCall<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const json = (await res.json()) as { data?: T; error?: string };
  if (!res.ok || json.error) throw new Error(json.error ?? 'Request failed');
  return json.data as T;
}

export const adminPost = <T,>(url: string, body: unknown) =>
  adminCall<T>(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

export const adminDelete = (url: string) => adminCall<unknown>(url, { method: 'DELETE' });

/** A status line shown under the page heading. */
export function useBanner() {
  const [banner, setBanner] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const notify = useCallback((text: string, type: 'success' | 'error') => setBanner({ text, type }), []);
  const view = banner ? (
    <p role="status" className={`rounded-md border px-3 py-2 text-sm ${banner.type === 'error' ? 'border-destructive/40 text-destructive' : 'border-primary/30 text-foreground'}`}>
      {banner.text}
    </p>
  ) : null;
  return { notify, banner: view };
}

export function PageHead({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h1 className="text-2xl font-semibold">{title}</h1>
      <p className="mt-1 max-w-3xl text-sm text-muted-foreground">{children}</p>
    </div>
  );
}
