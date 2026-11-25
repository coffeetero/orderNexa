'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Building2, Globe, Mail, MapPin, MessageSquare, Phone, Pin, PinOff, Printer, Star, Trash2, User } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';
import type { ContactDetail, ContactPoint } from '@/lib/organizer/contacts';
import { api, Avatar, formatContactDate, TagChip } from './contacts-ui';

const fmt = (iso: string) => new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });

function pointHref(p: ContactPoint): string | null {
  if (p.type === 'EMAIL') return `mailto:${p.value}`;
  if (p.type === 'PHONE' || p.type === 'MOBILE') return `tel:${p.value.replace(/[^\d+]/g, '')}`;
  if (p.type === 'ADDRESS') return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(p.value.replace(/\n/g, ', '))}`;
  if (p.type === 'WEBSITE') return /^https?:\/\//i.test(p.value) ? p.value : `https://${p.value}`;
  if (p.type === 'OTHER' && /^https?:\/\//i.test(p.value)) return p.value;
  return null;
}

const SECTIONS: { title: string; icon: typeof Phone; match: (p: ContactPoint) => boolean }[] = [
  { title: 'Phone', icon: Phone, match: (p) => p.type === 'PHONE' || p.type === 'MOBILE' || p.type === 'FAX' },
  { title: 'Email', icon: Mail, match: (p) => p.type === 'EMAIL' },
  { title: 'Address', icon: MapPin, match: (p) => p.type === 'ADDRESS' },
  { title: 'Website', icon: Globe, match: (p) => p.type === 'WEBSITE' },
  { title: 'Social profile', icon: User, match: (p) => p.type === 'OTHER' },
];

function QuickAction({ href, icon: Icon, label }: { href: string | null | undefined; icon: typeof Phone; label: string }) {
  const inner = <><Icon className="mr-1 h-4 w-4" />{label}</>;
  return href
    ? <Button asChild variant="outline" size="sm"><a href={href}>{inner}</a></Button>
    : <Button variant="outline" size="sm" disabled>{inner}</Button>;
}

interface Props {
  tenantId: number;
  contact: ContactDetail;
  canEdit: boolean;
  canDelete: boolean;
  onEdit: () => void;
  onDeleted: (result: string) => void;
  onChanged: () => void;
  onError: (msg: string | null) => void;
}

export function ContactView({ tenantId, contact: c, canEdit, canDelete, onEdit, onDeleted, onChanged, onError }: Props) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const phone = c.points.find((p) => (p.type === 'MOBILE' || p.type === 'PHONE') && p.is_primary) ?? c.points.find((p) => p.type === 'MOBILE' || p.type === 'PHONE');
  const email = c.points.find((p) => p.type === 'EMAIL' && p.is_primary) ?? c.points.find((p) => p.type === 'EMAIL');
  const subtitle = [c.job_title, c.department, c.company_name].filter(Boolean).join(' · ');

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    onError(null);
    try { await fn(); onChanged(); } catch (e) { onError((e as Error).message); } finally { setBusy(false); }
  };
  const base = `/api/organizer/contacts/${c.contact_id}`;
  const toggleFavorite = () => run(() => api(base, 'PATCH', { tenant_id: tenantId, is_favorite: !c.is_favorite }));
  const addNote = () => run(async () => {
    await api(`${base}/notes`, 'POST', { tenant_id: tenantId, note_text: note });
    setNote('');
  });
  const pinNote = (id: number, text: string, pinned: boolean) =>
    run(() => api(`${base}/notes`, 'POST', { tenant_id: tenantId, note_id: id, note_text: text, is_pinned: pinned }));
  const deleteNote = (id: number) => run(() => api(`${base}/notes?tenant_id=${tenantId}&note_id=${id}`, 'DELETE'));
  const remove = async () => {
    setBusy(true);
    onError(null);
    try {
      const r = await api<{ result: string }>(`${base}?tenant_id=${tenantId}`, 'DELETE');
      onDeleted(r.result);
    } catch (e) { onError((e as Error).message); setBusy(false); }
  };

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start gap-4">
        <Avatar name={c.full_name} photo={c.photo_data} size="lg" />
        <div className="min-w-0 flex-1">
          <h2 className="flex items-center gap-2 text-xl font-semibold">
            <span className="truncate">{c.full_name}</span>
            <button type="button" disabled={!canEdit || busy} onClick={toggleFavorite} title={c.is_favorite ? 'Remove from favourites' : 'Add to favourites'}
              aria-label={c.is_favorite ? 'Remove from favourites' : 'Add to favourites'} className="text-muted-foreground hover:text-amber-500 disabled:opacity-50">
              <Star className={cn('h-5 w-5', c.is_favorite && 'fill-amber-400 text-amber-500')} />
            </button>
          </h2>
          {c.nickname && <p className="text-sm text-muted-foreground">“{c.nickname}”</p>}
          {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
          <p className="mt-1 text-xs">
            {c.kind === 'CUSTOMER' ? (
              <Link href={`/customers?customer=${c.customer_id}`} className="inline-flex items-center gap-1 text-primary hover:underline">
                <Building2 className="h-3.5 w-3.5" /> Customer: {[c.customer_number, c.customer_name].filter(Boolean).join(' · ')}
              </Link>
            ) : <span className="text-muted-foreground">Company contact</span>}
          </p>
          {c.tags.length > 0 && <div className="mt-2 flex flex-wrap gap-1">{c.tags.map((t) => <TagChip key={t.tag_id} tag={t} />)}</div>}
        </div>
        <div className="flex gap-2 print:hidden">
          {canEdit && <Button size="sm" onClick={onEdit}>Edit</Button>}
          {canDelete && !confirmDelete && <Button size="sm" variant="ghost" onClick={() => setConfirmDelete(true)}>Delete</Button>}
          <Button size="sm" variant="ghost" onClick={() => window.print()} title="Print" aria-label="Print"><Printer className="h-4 w-4" /></Button>
        </div>
      </div>
      {confirmDelete && (
        <div className="flex flex-wrap items-center gap-2 rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm">
          <span>{c.timeline && c.timeline.length > 0 ? 'Delete this contact? It has notes, so it is deactivated and the notes are kept.' : 'Delete this contact for good?'}</span>
          <Button size="sm" variant="destructive" disabled={busy} onClick={remove}>Delete</Button>
          <Button size="sm" variant="ghost" onClick={() => setConfirmDelete(false)}>Keep</Button>
        </div>
      )}

      <div className="flex gap-2 print:hidden">
        <QuickAction href={phone && `tel:${phone.value.replace(/[^\d+]/g, '')}`} icon={Phone} label="Call" />
        <QuickAction href={phone && `sms:${phone.value.replace(/[^\d+]/g, '')}`} icon={MessageSquare} label="Message" />
        <QuickAction href={email && `mailto:${email.value}`} icon={Mail} label="Email" />
      </div>

      <div className="grid gap-x-8 gap-y-4 xl:grid-cols-2">
        {SECTIONS.map((s) => {
          const pts = c.points.filter(s.match);
          if (pts.length === 0) return null;
          return (
            <section key={s.title}>
              <h3 className="mb-1 flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground"><s.icon className="h-3.5 w-3.5" />{s.title}</h3>
              <ul className="space-y-1.5">
                {pts.map((p) => {
                  const href = pointHref(p);
                  return (
                    <li key={p.contact_point_id ?? p.value} className="text-sm">
                      <span className="block text-xs text-muted-foreground">{p.label || (p.type === 'MOBILE' ? 'mobile' : p.type === 'FAX' ? 'fax' : 'other')}{p.is_primary ? ' · primary' : ''}</span>
                      {href ? (
                        <a href={href} target={href.startsWith('http') ? '_blank' : undefined} rel="noreferrer" className="whitespace-pre-line break-words text-primary hover:underline">{p.value}</a>
                      ) : <span className="whitespace-pre-line break-words">{p.value}</span>}
                    </li>
                  );
                })}
              </ul>
            </section>
          );
        })}
        {c.important_dates.length > 0 && (
          <section>
            <h3 className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Dates</h3>
            <ul className="space-y-1.5 text-sm">
              {c.important_dates.map((d, i) => <li key={i}><span className="block text-xs text-muted-foreground">{d.label}</span>{formatContactDate(d.date)}</li>)}
            </ul>
          </section>
        )}
        {c.related_people.length > 0 && (
          <section>
            <h3 className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Related</h3>
            <ul className="space-y-1.5 text-sm">
              {c.related_people.map((r, i) => <li key={i}><span className="block text-xs text-muted-foreground">{r.label}</span>{r.name}</li>)}
            </ul>
          </section>
        )}
      </div>
      {c.notes && (
        <section>
          <h3 className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Notes</h3>
          <p className="whitespace-pre-line text-sm">{c.notes}</p>
        </section>
      )}

      <section className="border-t pt-4">
        <h3 className="mb-2 text-sm font-semibold">Timeline</h3>
        {canEdit && (
          <div className="mb-3 flex items-end gap-2 print:hidden">
            <Textarea value={note} onChange={(e) => setNote(e.target.value)} placeholder="Add a note: a call, a visit, something to remember…" rows={2} className="flex-1" />
            <Button size="sm" disabled={busy || note.trim() === ''} onClick={addNote}>Add</Button>
          </div>
        )}
        {(c.timeline ?? []).length === 0 ? <p className="text-sm text-muted-foreground">No notes yet.</p> : (
          <ul className="space-y-2">
            {(c.timeline ?? []).map((n) => (
              <li key={n.note_id} className={cn('rounded-md border p-2 text-sm', n.is_pinned && 'border-amber-300 bg-amber-50 dark:border-amber-700 dark:bg-amber-950/30')}>
                <div className="mb-1 flex items-center gap-2 text-xs text-muted-foreground">
                  <span>{n.author_name} · {fmt(n.created_at)}</span>
                  {canEdit && (
                    <span className="ml-auto flex gap-1 print:hidden">
                      <button type="button" disabled={busy} onClick={() => pinNote(n.note_id, n.note_text, !n.is_pinned)} title={n.is_pinned ? 'Unpin' : 'Pin to top'} aria-label={n.is_pinned ? 'Unpin' : 'Pin to top'} className="hover:text-foreground">
                        {n.is_pinned ? <PinOff className="h-3.5 w-3.5" /> : <Pin className="h-3.5 w-3.5" />}
                      </button>
                      <button type="button" disabled={busy} onClick={() => deleteNote(n.note_id)} title="Remove note" aria-label="Remove note" className="hover:text-destructive">
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </span>
                  )}
                </div>
                <p className="whitespace-pre-line">{n.note_text}</p>
              </li>
            ))}
          </ul>
        )}
      </section>
      <p className="text-xs text-muted-foreground">
        Added {fmt(c.created_at)}{c.created_by_name ? ` by ${c.created_by_name}` : ''} · Updated {fmt(c.updated_at)}{c.updated_by_name ? ` by ${c.updated_by_name}` : ''}
      </p>
    </div>
  );
}
