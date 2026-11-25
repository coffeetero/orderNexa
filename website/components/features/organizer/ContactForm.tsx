'use client';

import { useEffect, useRef, useState } from 'react';
import { Plus, Star, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';
import { phoneType, type ContactDetail, type ContactPoint, type ContactTag, type PointType } from '@/lib/organizer/contacts';
import { api, Avatar, resizePhoto, TagChip } from './contacts-ui';

type Kind = 'phone' | 'email' | 'address' | 'website' | 'social';
const KINDS: { kind: Kind; title: string; add: string; labels: string[]; placeholder: string }[] = [
  { kind: 'phone', title: 'Phones', add: 'Add phone', labels: ['mobile', 'work', 'home', 'main', 'iPhone', 'work fax', 'home fax', 'pager', 'other'], placeholder: 'Phone number' },
  { kind: 'email', title: 'Emails', add: 'Add email', labels: ['work', 'home', 'other'], placeholder: 'name@example.com' },
  { kind: 'address', title: 'Addresses', add: 'Add address', labels: ['work', 'home', 'other'], placeholder: 'Street\nCity, State ZIP\nCountry' },
  { kind: 'website', title: 'Websites', add: 'Add website', labels: ['homepage', 'work', 'home', 'other'], placeholder: 'https://' },
  { kind: 'social', title: 'Social profiles', add: 'Add social profile', labels: ['LinkedIn', 'Facebook', 'Instagram', 'X', 'WhatsApp', 'other'], placeholder: 'Profile link or handle' },
];
const DATE_LABELS = ['birthday', 'anniversary', 'other'];
const RELATED_LABELS = ['spouse', 'partner', 'child', 'parent', 'sibling', 'assistant', 'manager', 'friend', 'other'];

const kindOf = (t: PointType): Kind =>
  t === 'EMAIL' ? 'email' : t === 'ADDRESS' ? 'address' : t === 'WEBSITE' ? 'website' : t === 'OTHER' ? 'social' : 'phone';
const typeFor = (k: Kind, label: string): PointType =>
  k === 'email' ? 'EMAIL' : k === 'address' ? 'ADDRESS' : k === 'website' ? 'WEBSITE' : k === 'social' ? 'OTHER' : phoneType(label);

interface Row extends ContactPoint { key: number }
interface Form {
  name_prefix: string; first_name: string; middle_name: string; last_name: string; name_suffix: string; nickname: string;
  company_name: string; job_title: string; department: string; notes: string; is_favorite: boolean;
  photo_data: string | null; customer_id: number | null; customer_label: string;
  points: Row[]; dates: { label: string; date: string }[]; related: { label: string; name: string }[]; tag_ids: number[];
}
interface CustomerOption { customer_id: number; customer_name: string; customer_number: string | null }

let seq = 0;
const s = (v: string | null | undefined) => v ?? '';
const customerLabel = (o: { customer_number: string | null; customer_name: string | null }) => [o.customer_number, o.customer_name].filter(Boolean).join(' · ');

function toForm(c: ContactDetail | null): Form {
  return {
    name_prefix: s(c?.name_prefix), first_name: s(c?.first_name), middle_name: s(c?.middle_name), last_name: s(c?.last_name),
    name_suffix: s(c?.name_suffix), nickname: s(c?.nickname), company_name: s(c?.company_name), job_title: s(c?.job_title),
    department: s(c?.department), notes: s(c?.notes), is_favorite: c?.is_favorite ?? false, photo_data: c?.photo_data ?? null,
    customer_id: c?.customer_id ?? null, customer_label: c ? customerLabel(c) : '',
    points: (c?.points ?? []).map((p) => ({ ...p, label: p.label ?? '', key: ++seq })),
    dates: c?.important_dates.map((d) => ({ ...d })) ?? [],
    related: c?.related_people.map((r) => ({ ...r })) ?? [],
    tag_ids: c?.tags.map((t) => t.tag_id) ?? [],
  };
}

interface Props {
  tenantId: number;
  contact: ContactDetail | null;
  tags: ContactTag[];
  onSaved: (c: ContactDetail) => void;
  onCancel: () => void;
  onTagsChanged: () => void;
}

export function ContactForm({ tenantId, contact, tags, onSaved, onCancel, onTagsChanged }: Props) {
  const [f, setF] = useState<Form>(() => toForm(contact));
  const [showMore, setShowMore] = useState(() => Boolean(contact?.name_prefix || contact?.middle_name || contact?.name_suffix || contact?.nickname));
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [newTag, setNewTag] = useState('');
  const [customers, setCustomers] = useState<CustomerOption[] | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setF((x) => ({ ...x, [k]: v }));
  const [owner, setOwner] = useState<'COMPANY' | 'CUSTOMER'>(contact?.kind ?? 'COMPANY');

  useEffect(() => {
    if (owner !== 'CUSTOMER' || customers !== null) return;
    api<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then((rows) => setCustomers(rows ?? []))
      .catch((e: Error) => setError(e.message));
  }, [owner, customers, tenantId]);

  const updPoint = (key: number, patch: Partial<Row>) => setF((x) => ({ ...x, points: x.points.map((p) => (p.key === key ? { ...p, ...patch } : p)) }));
  const setPrimary = (key: number) => setF((x) => {
    const target = x.points.find((p) => p.key === key);
    if (!target) return x;
    const k = kindOf(target.type);
    return { ...x, points: x.points.map((p) => (kindOf(p.type) === k ? { ...p, is_primary: p.key === key ? !p.is_primary : false } : p)) };
  });
  const addPoint = (k: Kind) => {
    const label = KINDS.find((x) => x.kind === k)?.labels[0] ?? '';
    setF((x) => ({ ...x, points: [...x.points, { key: ++seq, type: typeFor(k, label), label, value: '', is_primary: false }] }));
  };

  const pickPhoto = async (file: File) => {
    try { set('photo_data', await resizePhoto(file)); } catch (e) { setError((e as Error).message); }
    if (fileRef.current) fileRef.current.value = '';
  };

  const createTag = async () => {
    if (!newTag.trim()) return;
    try {
      const t = await api<ContactTag>('/api/organizer/contacts/tags', 'POST', { tenant_id: tenantId, tag_name: newTag });
      set('tag_ids', [...f.tag_ids, t.tag_id]);
      setNewTag('');
      onTagsChanged();
    } catch (e) { setError((e as Error).message); }
  };

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      let customerId: number | null = null;
      if (owner === 'CUSTOMER') {
        customerId = f.customer_id;
        if (customerId === null) throw new Error('Pick the customer this contact belongs to');
      }
      const saved = await api<ContactDetail>('/api/organizer/contacts', 'POST', {
        tenant_id: tenantId,
        contact: {
          contact_id: contact?.contact_id ?? null, customer_id: customerId,
          name_prefix: f.name_prefix, first_name: f.first_name, middle_name: f.middle_name, last_name: f.last_name,
          name_suffix: f.name_suffix, nickname: f.nickname, company_name: f.company_name, job_title: f.job_title,
          department: f.department, notes: f.notes, is_favorite: f.is_favorite, photo_data: f.photo_data,
          important_dates: f.dates, related_people: f.related, tag_ids: f.tag_ids,
          points: f.points.map(({ contact_point_id, type, label, value, is_primary }) => ({ contact_point_id, type, label, value, is_primary })),
        },
      });
      onSaved(saved);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  };

  const field = (k: keyof Form, label: string, props: React.ComponentProps<typeof Input> = {}) => (
    <div className="space-y-1">
      <Label htmlFor={`cf-${k}`} className="text-xs text-muted-foreground">{label}</Label>
      <Input id={`cf-${k}`} value={f[k] as string} onChange={(e) => set(k, e.target.value as never)} {...props} />
    </div>
  );

  return (
    <form className="space-y-5" onSubmit={(e) => { e.preventDefault(); void save(); }}>
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-xl font-semibold">{contact ? 'Edit contact' : 'New contact'}</h2>
        <div className="flex gap-2">
          <Button type="button" variant="ghost" onClick={onCancel} disabled={busy}>Cancel</Button>
          <Button type="submit" disabled={busy}>{busy ? 'Saving…' : 'Save'}</Button>
        </div>
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}

      <div className="flex items-center gap-4">
        <Avatar name={[f.first_name, f.last_name].filter(Boolean).join(' ') || f.company_name || '?'} photo={f.photo_data} size="lg" />
        <div className="flex flex-wrap gap-2">
          <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => e.target.files?.[0] && pickPhoto(e.target.files[0])} />
          <Button type="button" variant="outline" size="sm" onClick={() => fileRef.current?.click()}>{f.photo_data ? 'Change photo' : 'Add photo'}</Button>
          {f.photo_data && <Button type="button" variant="ghost" size="sm" onClick={() => set('photo_data', null)}>Remove photo</Button>}
          <label className="flex items-center gap-1.5 text-sm">
            <input type="checkbox" checked={f.is_favorite} onChange={(e) => set('is_favorite', e.target.checked)} className="h-4 w-4" />
            <Star className="h-4 w-4 text-amber-500" /> Favourite
          </label>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        {showMore && field('name_prefix', 'Prefix', { placeholder: 'Dr., Ms.' })}
        {field('first_name', 'First name', { autoFocus: !contact })}
        {showMore && field('middle_name', 'Middle name')}
        {field('last_name', 'Last name')}
        {showMore && field('name_suffix', 'Suffix', { placeholder: 'Jr., PhD' })}
        {showMore && field('nickname', 'Nickname')}
        {field('company_name', 'Company')}
        {field('job_title', 'Job title')}
        {field('department', 'Department')}
      </div>
      {!showMore && <button type="button" className="text-xs text-primary hover:underline" onClick={() => setShowMore(true)}>Prefix, middle name, suffix, nickname</button>}

      <div className="space-y-2">
        <Label className="text-xs text-muted-foreground">Belongs to</Label>
        <div className="flex flex-wrap items-center gap-3 text-sm">
          <label className="flex items-center gap-1.5"><input type="radio" checked={owner === 'COMPANY'} onChange={() => { setOwner('COMPANY'); setF((x) => ({ ...x, customer_id: null, customer_label: '' })); }} /> Our company</label>
          <label className="flex items-center gap-1.5"><input type="radio" checked={owner === 'CUSTOMER'} onChange={() => setOwner('CUSTOMER')} /> A customer</label>
          {owner === 'CUSTOMER' && (
            <>
              <Input list="cf-customers" className="max-w-sm" placeholder={customers === null ? 'Loading customers…' : 'Type a customer number or name'}
                value={f.customer_label}
                onChange={(e) => {
                  const v = e.target.value;
                  const hit = customers?.find((o) => customerLabel(o) === v) ?? null;
                  setF((x) => ({ ...x, customer_label: v, customer_id: hit?.customer_id ?? null }));
                }} />
              <datalist id="cf-customers">{(customers ?? []).map((o) => <option key={o.customer_id} value={customerLabel(o)} />)}</datalist>
            </>
          )}
        </div>
      </div>

      {KINDS.map((k) => {
        const rows = f.points.filter((p) => kindOf(p.type) === k.kind);
        return (
          <section key={k.kind} className="space-y-2">
            <h3 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{k.title}</h3>
            <datalist id={`cf-labels-${k.kind}`}>{k.labels.map((l) => <option key={l} value={l} />)}</datalist>
            {rows.map((p) => (
              <div key={p.key} className="flex items-start gap-2">
                <Input list={`cf-labels-${k.kind}`} value={p.label ?? ''} aria-label="Label" className="w-32 shrink-0"
                  onChange={(e) => updPoint(p.key, { label: e.target.value, type: typeFor(k.kind, e.target.value) })} />
                {k.kind === 'address' ? (
                  <Textarea value={p.value} rows={3} placeholder={k.placeholder} aria-label={k.title} className="flex-1"
                    onChange={(e) => updPoint(p.key, { value: e.target.value })} />
                ) : (
                  <Input value={p.value} placeholder={k.placeholder} aria-label={k.title} className="flex-1"
                    type={k.kind === 'email' ? 'email' : k.kind === 'phone' ? 'tel' : 'text'}
                    onChange={(e) => updPoint(p.key, { value: e.target.value })} />
                )}
                <button type="button" onClick={() => setPrimary(p.key)} title="Primary" aria-label="Primary"
                  className={cn('mt-2 text-muted-foreground hover:text-amber-500', p.is_primary && 'text-amber-500')}>
                  <Star className={cn('h-4 w-4', p.is_primary && 'fill-amber-400')} />
                </button>
                <button type="button" onClick={() => setF((x) => ({ ...x, points: x.points.filter((q) => q.key !== p.key) }))}
                  title="Remove" aria-label="Remove" className="mt-2 text-muted-foreground hover:text-destructive"><X className="h-4 w-4" /></button>
              </div>
            ))}
            <button type="button" className="flex items-center gap-1 text-sm text-primary hover:underline" onClick={() => addPoint(k.kind)}>
              <Plus className="h-3.5 w-3.5" />{k.add}
            </button>
          </section>
        );
      })}

      <section className="space-y-2">
        <h3 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Dates</h3>
        <datalist id="cf-date-labels">{DATE_LABELS.map((l) => <option key={l} value={l} />)}</datalist>
        {f.dates.map((d, i) => (
          <div key={i} className="flex items-center gap-2">
            <Input list="cf-date-labels" value={d.label} aria-label="Date label" className="w-32 shrink-0"
              onChange={(e) => set('dates', f.dates.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)))} />
            <Input value={d.date} placeholder="1980-05-12 or --05-12" aria-label="Date" className="w-48"
              onChange={(e) => set('dates', f.dates.map((x, j) => (j === i ? { ...x, date: e.target.value } : x)))} />
            <span className="text-xs text-muted-foreground">--MM-DD = no year</span>
            <button type="button" onClick={() => set('dates', f.dates.filter((_, j) => j !== i))} title="Remove" aria-label="Remove"
              className="text-muted-foreground hover:text-destructive"><X className="h-4 w-4" /></button>
          </div>
        ))}
        <button type="button" className="flex items-center gap-1 text-sm text-primary hover:underline"
          onClick={() => set('dates', [...f.dates, { label: f.dates.some((d) => d.label === 'birthday') ? 'anniversary' : 'birthday', date: '' }])}>
          <Plus className="h-3.5 w-3.5" />Add date
        </button>
      </section>

      <section className="space-y-2">
        <h3 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Related people</h3>
        <datalist id="cf-related-labels">{RELATED_LABELS.map((l) => <option key={l} value={l} />)}</datalist>
        {f.related.map((r, i) => (
          <div key={i} className="flex items-center gap-2">
            <Input list="cf-related-labels" value={r.label} aria-label="Relation" className="w-32 shrink-0"
              onChange={(e) => set('related', f.related.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)))} />
            <Input value={r.name} placeholder="Name" aria-label="Name" className="flex-1"
              onChange={(e) => set('related', f.related.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} />
            <button type="button" onClick={() => set('related', f.related.filter((_, j) => j !== i))} title="Remove" aria-label="Remove"
              className="text-muted-foreground hover:text-destructive"><X className="h-4 w-4" /></button>
          </div>
        ))}
        <button type="button" className="flex items-center gap-1 text-sm text-primary hover:underline"
          onClick={() => set('related', [...f.related, { label: 'spouse', name: '' }])}>
          <Plus className="h-3.5 w-3.5" />Add related person
        </button>
      </section>

      <section className="space-y-2">
        <h3 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Tags</h3>
        <div className="flex flex-wrap items-center gap-1.5">
          {tags.map((t) => (
            <TagChip key={t.tag_id} tag={t} active={f.tag_ids.includes(t.tag_id)}
              onClick={() => set('tag_ids', f.tag_ids.includes(t.tag_id) ? f.tag_ids.filter((x) => x !== t.tag_id) : [...f.tag_ids, t.tag_id])} />
          ))}
          <Input value={newTag} onChange={(e) => setNewTag(e.target.value)} placeholder="New tag" className="h-7 w-32 text-xs"
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void createTag(); } }} />
          {newTag.trim() && <Button type="button" size="sm" variant="outline" className="h-7" onClick={createTag}>Add tag</Button>}
        </div>
      </section>

      <div className="space-y-1">
        <Label htmlFor="cf-notes" className="text-xs text-muted-foreground">Notes</Label>
        <Textarea id="cf-notes" value={f.notes} rows={3} onChange={(e) => set('notes', e.target.value)} />
      </div>
    </form>
  );
}
