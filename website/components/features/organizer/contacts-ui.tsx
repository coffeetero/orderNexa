'use client';

import { cn } from '@/lib/utils';
import type { ContactTag } from '@/lib/organizer/contacts';

/** One row of the address book list (org_contacts_get). */
export interface ContactRow {
  contact_id: number; full_name: string; sort_name: string; first_name: string | null; last_name: string | null;
  nickname: string | null; company_name: string | null; job_title: string | null; is_favorite: boolean; has_photo: boolean;
  kind: 'COMPANY' | 'CUSTOMER'; customer_id: number | null; customer_name: string | null; customer_number: string | null;
  phone: string | null; email: string | null; search: string; tag_ids: number[]; updated_at: string;
}

/** fetch → JSON, throwing the API's error message. */
export async function api<T>(url: string, method = 'GET', body?: unknown): Promise<T> {
  const res = await fetch(url, {
    method,
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const j = (await res.json().catch(() => ({}))) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? `Request failed (${res.status})`);
  return j.data as T;
}

export const TAG_COLORS = ['gray', 'red', 'orange', 'amber', 'green', 'teal', 'sky', 'blue', 'violet', 'pink'] as const;

const TAG_CLASS: Record<string, string> = {
  gray: 'bg-muted text-muted-foreground',
  red: 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200',
  orange: 'bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-200',
  amber: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200',
  green: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200',
  teal: 'bg-teal-100 text-teal-800 dark:bg-teal-900/40 dark:text-teal-200',
  sky: 'bg-sky-100 text-sky-800 dark:bg-sky-900/40 dark:text-sky-200',
  blue: 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-200',
  violet: 'bg-violet-100 text-violet-800 dark:bg-violet-900/40 dark:text-violet-200',
  pink: 'bg-pink-100 text-pink-800 dark:bg-pink-900/40 dark:text-pink-200',
};

export function TagChip({ tag, active, onClick, className }: { tag: ContactTag; active?: boolean; onClick?: () => void; className?: string }) {
  const cls = cn('inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium', TAG_CLASS[tag.tag_color] ?? TAG_CLASS.gray,
    onClick && 'cursor-pointer', active === false && 'opacity-40', active && 'ring-2 ring-ring ring-offset-1', className);
  return onClick
    ? <button type="button" className={cls} onClick={onClick}>{tag.tag_name}</button>
    : <span className={cls}>{tag.tag_name}</span>;
}

export function initials(name: string): string {
  const parts = name.replace(/[.,;:()"'&/-]/g, ' ').trim().split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] ?? '?') + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}

export function Avatar({ name, photo, size = 'md' }: { name: string; photo?: string | null; size?: 'sm' | 'md' | 'lg' }) {
  const dim = size === 'lg' ? 'h-20 w-20 text-2xl' : size === 'md' ? 'h-10 w-10 text-sm' : 'h-8 w-8 text-xs';
  if (photo) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={photo} alt="" className={cn(dim, 'shrink-0 rounded-full object-cover')} />;
  }
  return (
    <span className={cn(dim, 'flex shrink-0 items-center justify-center rounded-full bg-primary/10 font-semibold text-primary')}>
      {initials(name)}
    </span>
  );
}

/** '1980-05-12' → 'May 12, 1980'; '--05-12' → 'May 12'. */
export function formatContactDate(d: string): string {
  const noYear = d.startsWith('--');
  const iso = noYear ? `2000${d.slice(1)}` : d;
  const dt = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(dt.getTime())) return d;
  return dt.toLocaleDateString(undefined, noYear ? { month: 'long', day: 'numeric' } : { year: 'numeric', month: 'long', day: 'numeric' });
}

export function downloadText(name: string, text: string, type: string) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Picked image → square JPEG data URL, 160 px, small enough for the database. */
export function resizePhoto(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      const size = 160;
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const side = Math.min(img.width, img.height);
      canvas.getContext('2d')?.drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, size, size);
      URL.revokeObjectURL(url);
      resolve(canvas.toDataURL('image/jpeg', 0.85));
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('That file is not an image')); };
    img.src = url;
  });
}
