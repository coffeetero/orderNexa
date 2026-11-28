'use client';

import { forwardRef, useCallback, useEffect, useImperativeHandle, useMemo, useState } from 'react';
import { AlertTriangle, Info, MapPin, Plus, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import type { CustomerContactsTabHandle } from '@/components/features/account/CustomerContactsTab';

/* ── data from the three APIs ───────────────────────────────────────────────── */
type Address = {
  contact_point_id: number; address: string; instructions: string | null; bill: boolean; ship: boolean;
  is_verified: boolean; suggested_address: string | null; validation_status: string | null;
  geocode_status: string | null; latitude: number | null; longitude: number | null;
};
type Addresses = { pickup: boolean; inherited_from: { customer_id: number; customer_name: string } | null; addresses: Address[]; missing_bill: boolean; missing_ship: boolean };
type Point = { contact_point_id: number | null; type: string; value: string; label: string; sequence: number; is_primary: boolean; is_active?: boolean; do_not_contact?: boolean; use_as_shipping?: boolean; country_dial_code?: string };
type Contact = { contact_id: number; contact_type: string; card_name: string; display_name: string; first_name: string; last_name: string; job_title: string; department: string; is_primary: boolean; contact_points: Point[] };
type Note = { note_id: number; note_title: string | null; note_text: string; note_type: string | null; is_important: boolean; is_pinned: boolean; visibility: string; author_name: string; created_at: string };

/* ── what is selected / being edited ────────────────────────────────────────── */
type Sel =
  | { kind: 'address'; id: number | null }
  | { kind: 'note'; id: number | null }
  | { kind: 'legacy'; contactId: number; pointId: number }
  | { kind: 'person'; id: number | null };
type AddressForm = { address: string; instructions: string; bill: boolean; ship: boolean; validated: boolean };
type PersonForm = { first_name: string; last_name: string; job_title: string; points: Point[] };
type Form = { kind: 'address'; f: AddressForm } | { kind: 'note'; text: string } | { kind: 'legacy'; text: string } | { kind: 'person'; f: PersonForm };

const PERSON_TYPES = ['PHONE', 'MOBILE', 'EMAIL', 'FAX', 'WEBSITE', 'OTHER'] as const;
const TYPE_LABEL: Record<string, string> = { PHONE: 'Phone', MOBILE: 'Mobile', EMAIL: 'Email', FAX: 'Fax', WEBSITE: 'Website', OTHER: 'Other' };
const box = 'w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm leading-5 focus:outline-none focus:ring-1 focus:ring-ring';
const role = (a: { bill: boolean; ship: boolean }) => (a.bill && a.ship ? 'Billing & Shipping' : a.bill ? 'Billing' : a.ship ? 'Shipping' : 'Address');
const streetCity = (t: string) => { const l = t.split('\n'); return l.length > 1 ? `${l[l.length - 2]}, ${l[l.length - 1]}` : l[0]; };
const personName = (c: Contact) => [c.first_name, c.last_name].filter(Boolean).join(' ') || c.display_name || c.card_name;
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/** Lines of Google's suggestion that differ from the typed address. */
function changedLines(typed: string, suggested: string): Set<number> {
  const norm = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();
  const t = typed.split('\n').map(norm);
  return new Set(suggested.split('\n').map((l, i) => (t.includes(norm(l)) ? -1 : i)).filter((i) => i >= 0));
}

async function call<T>(url: string, init?: RequestInit): Promise<{ data: T | null; error: string | null }> {
  const res = await fetch(url, init);
  const j = (await res.json().catch(() => ({}))) as { data?: T; error?: string };
  if (!res.ok || j.error) return { data: null, error: j.error ?? 'Something went wrong.' };
  return { data: (j.data ?? null) as T | null, error: null };
}
/** A message that needs the person's attention: a popup, not a toast (toasts are for notifications). */
type Popup = { title: string; text: string; confirm?: { label: string; run: () => void } };
const json = (method: string, body: unknown): RequestInit => ({ method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

/**
 * Customers › Contacts: the customer's contact records in one list — its addresses (named by role: Billing & Shipping,
 * Billing, Shipping or Address), its notes and its contact persons — with the selected record's card on the right.
 * An address card: the address box with its Instructions, and the Billing Address / Shipping Address / Validated boxes
 * and a map link beside it; Google's suggestion under it. Rules are in the database (fnd_customer_addresses.sql);
 * notes are the customer's notes (fnd_notes), persons and old-system notes its contacts (fnd_contacts).
 */
export const CustomerContactRecords = forwardRef<CustomerContactsTabHandle, { tenantId: number; customerId: number; onDirtyChange?: (dirty: boolean) => void }>(
  function CustomerContactRecords({ tenantId, customerId, onDirtyChange }, ref) {
    const [addr, setAddr] = useState<Addresses | null>(null);
    const [contacts, setContacts] = useState<Contact[]>([]);
    const [notes, setNotes] = useState<Note[]>([]);
    const [sel, setSel] = useState<Sel | null>(null);
    const [form, setForm] = useState<Form | null>(null);
    const [saved, setSaved] = useState<Form | null>(null);
    const [busy, setBusy] = useState(false);
    const [menu, setMenu] = useState(false);
    const [popup, setPopup] = useState<Popup | null>(null);
    const warn = useCallback((text: string) => setPopup({ title: 'Cannot save', text }), []);
    const ask = (text: string, label: string, run: () => void) => setPopup({ title: 'Please confirm', text, confirm: { label, run } });
    // API call: a refusal (rule broken, missing value…) opens the popup
    const req = useCallback(async <T,>(url: string, init?: RequestInit): Promise<T | null> => {
      const r = await call<T>(url, init);
      if (r.error) { warn(r.error); return null; }
      return r.data;
    }, [warn]);

    const load = useCallback(async () => {
      const q = `tenant_id=${tenantId}&customer_id=${customerId}`;
      const [a, c, n] = await Promise.all([
        req<Addresses>(`/api/customers/addresses?${q}`), req<Contact[]>(`/api/customers/contacts?${q}`), req<Note[]>(`/api/customers/notes?${q}`),
      ]);
      setAddr(a); setContacts(c ?? []); setNotes(n ?? []);
      return { a, c: c ?? [], n: n ?? [] };
    }, [tenantId, customerId, req]);

    const people = useMemo(() => contacts.filter((c) => c.contact_type === 'PERSON'), [contacts]);
    const legacy = useMemo(() => contacts.filter((c) => c.contact_type === 'OTHER_CONTACTS')
      .flatMap((c) => c.contact_points.filter((p) => p.type === 'NOTE' && p.contact_point_id).map((p) => ({ c, p }))), [contacts]);
    const readOnly = !!addr?.inherited_from;

    // the form of a selection, from the loaded records
    const formOf = useCallback((s: Sel, a = addr, c = contacts, n = notes): Form | null => {
      if (s.kind === 'address') {
        const x = a?.addresses.find((r) => r.contact_point_id === s.id);
        return { kind: 'address', f: x ? { address: x.address, instructions: x.instructions ?? '', bill: x.bill, ship: x.ship, validated: x.is_verified }
          : { address: '', instructions: '', bill: !a?.addresses.length, ship: !a?.addresses.length && !a?.pickup, validated: false } };
      }
      if (s.kind === 'note') return { kind: 'note', text: n.find((r) => r.note_id === s.id)?.note_text ?? '' };
      if (s.kind === 'legacy') return { kind: 'legacy', text: c.find((r) => r.contact_id === s.contactId)?.contact_points.find((p) => p.contact_point_id === s.pointId)?.value ?? '' };
      const p = c.find((r) => r.contact_id === s.id);
      return { kind: 'person', f: p ? { first_name: p.first_name, last_name: p.last_name, job_title: p.job_title, points: p.contact_points.filter((x) => x.type !== 'NOTE' && x.type !== 'ADDRESS') }
        : { first_name: '', last_name: '', job_title: '', points: [{ contact_point_id: null, type: 'PHONE', value: '', label: '', sequence: 1, is_primary: true }] } };
    }, [addr, contacts, notes]);

    const open = useCallback((s: Sel, a?: Addresses | null, c?: Contact[], n?: Note[]) => {
      const f = formOf(s, a ?? addr, c ?? contacts, n ?? notes);
      setSel(s); setForm(f); setSaved(f); setMenu(false);
    }, [formOf, addr, contacts, notes]);

    useEffect(() => {
      let live = true;
      setSel(null); setForm(null); setSaved(null);
      void load().then(({ a, c, n }) => {
        if (!live) return;
        const first = a?.addresses[0];
        if (first) open({ kind: 'address', id: first.contact_point_id }, a, c, n);
      });
      return () => { live = false; };
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [tenantId, customerId]);

    const dirty = !!form && !same(form, saved);
    useEffect(() => { onDirtyChange?.(dirty); }, [dirty, onDirtyChange]);

    const choose = (s: Sel) => {
      if (dirty) { ask('Discard the changes to this record?', 'Discard', () => open(s)); return; }
      open(s);
    };
    const cancel = useCallback(() => { setForm(saved); if (sel && 'id' in sel && sel.id === null) setSel(null); }, [saved, sel]);

    const reloadTo = async (s: Sel | null) => {
      const r = await load();
      if (s) open(s, r.a, r.c, r.n); else { setSel(null); setForm(null); setSaved(null); }
    };

    const save = useCallback(async () => {
      if (!sel || !form || !dirty) return;
      setBusy(true);
      try {
        if (form.kind === 'address' && sel.kind === 'address') {
          const r = await req<{ contact_point_id: number }>('/api/customers/addresses', json('POST', {
            tenant_id: tenantId, customer_id: customerId, contact_point_id: sel.id, address: form.f.address, instructions: form.f.instructions,
            bill: form.f.bill, ship: form.f.ship, validated: form.f.validated,
          }));
          if (!r) return;
          // a new or changed address is checked with Google straight away (quietly: the card shows the outcome)
          if (!form.f.validated) {
            await fetch('/api/address/validate', json('POST', { tenant_id: tenantId, contact_point_ids: [r.contact_point_id] })).catch(() => undefined);
          }
          await reloadTo({ kind: 'address', id: r.contact_point_id });
        } else if (form.kind === 'note' && sel.kind === 'note') {
          const cur = notes.find((n) => n.note_id === sel.id);
          const r = await req<{ note_id?: number }>('/api/customers/notes', json('POST', { tenant_id: tenantId, entry: {
            note_id: sel.id, entity_id: customerId, source_table: 'fnd_customers', note_text: form.text, note_title: cur?.note_title ?? '',
            note_type: cur?.note_type ?? '', is_important: cur?.is_important ?? false, is_pinned: cur?.is_pinned ?? false, visibility: cur?.visibility ?? 'tenant_only',
          } }));
          if (!r) return;
          await reloadTo({ kind: 'note', id: r.note_id ?? sel.id });
        } else if (form.kind === 'legacy' && sel.kind === 'legacy') {
          const c = contacts.find((x) => x.contact_id === sel.contactId);
          if (!c) return;
          const ok = await saveContact(c, c.contact_points.map((p) => (p.contact_point_id === sel.pointId ? { ...p, value: form.text } : p)));
          if (ok) await reloadTo(sel);
        } else if (form.kind === 'person' && sel.kind === 'person') {
          const c = contacts.find((x) => x.contact_id === sel.id);
          const name = [form.f.first_name.trim(), form.f.last_name.trim()].filter(Boolean).join(' ');
          if (!name) { warn('Enter the contact person\'s name.'); return; }
          const kept = (c?.contact_points ?? []).filter((p) => p.type === 'NOTE' || p.type === 'ADDRESS');
          const points = [...kept, ...form.f.points.filter((p) => p.value.trim())].map((p, i) => ({ ...p, sequence: i + 1 }));
          const r = await req<{ contact_id: number }>('/api/customers/contacts', json('POST', { tenant_id: tenantId, customer_id: customerId, contact: {
            contact_id: c?.contact_id ?? null, contact_type: 'PERSON', card_name: form.f.job_title.trim() || name, display_name: c?.display_name ?? '',
            first_name: form.f.first_name.trim(), last_name: form.f.last_name.trim(), job_title: form.f.job_title.trim(), department: c?.department ?? '',
            is_primary: c?.is_primary ?? false, is_active: true, contact_points: points,
          } }));
          if (!r) return;
          await reloadTo({ kind: 'person', id: r.contact_id });
        }
        toast.success('Saved.');
      } finally { setBusy(false); }
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [sel, form, dirty, tenantId, customerId, notes, contacts, req, warn]);

    useImperativeHandle(ref, () => ({ save, cancel }), [save, cancel]);

    async function saveContact(c: Contact, points: Point[], extra: Record<string, unknown> = {}): Promise<boolean> {
      const r = await req('/api/customers/contacts', json('POST', { tenant_id: tenantId, customer_id: customerId, contact: {
        contact_id: c.contact_id, contact_type: c.contact_type, card_name: c.card_name, display_name: c.display_name, first_name: c.first_name,
        last_name: c.last_name, job_title: c.job_title, department: c.department, is_primary: c.is_primary, is_active: true, contact_points: points, ...extra,
      } }));
      return r !== null;
    }

    const remove = () => { if (sel) ask('Remove this record?', 'Remove', () => void doRemove()); };
    const doRemove = async () => {
      if (!sel) return;
      setBusy(true);
      try {
        let ok = false;
        if (sel.kind === 'address' && sel.id) {
          ok = (await req('/api/customers/addresses', json('PATCH', { tenant_id: tenantId, customer_id: customerId, contact_point_id: sel.id, action: 'REMOVE' }))) !== null;
        } else if (sel.kind === 'note' && sel.id) {
          ok = (await req(`/api/customers/notes?tenant_id=${tenantId}&note_id=${sel.id}`, { method: 'DELETE' })) !== null;
        } else if (sel.kind === 'legacy') {
          const c = contacts.find((x) => x.contact_id === sel.contactId);
          ok = !!c && await saveContact(c, c.contact_points.filter((p) => p.contact_point_id !== sel.pointId));
        } else if (sel.kind === 'person' && sel.id) {
          const c = contacts.find((x) => x.contact_id === sel.id);
          ok = !!c && await saveContact(c, c.contact_points, { is_active: false });
        }
        if (ok) await reloadTo(null);
      } finally { setBusy(false); }
    };

    const addressAction = async (id: number, action: 'ACCEPT' | 'REJECT') => {
      setBusy(true);
      try {
        const r = await req('/api/customers/addresses', json('PATCH', { tenant_id: tenantId, customer_id: customerId, contact_point_id: id, action }));
        if (r !== null) await reloadTo({ kind: 'address', id });
      } finally { setBusy(false); }
    };

    const isSel = (s: Sel) => !!sel && same(sel, s);
    const selAddr = sel?.kind === 'address' ? addr?.addresses.find((a) => a.contact_point_id === sel.id) ?? null : null;
    const isNew = !!sel && 'id' in sel && sel.id === null;

    /* ── left list ── */
    const Row = ({ s, title, sub, tag }: { s: Sel; title: string; sub: string; tag?: React.ReactNode }) => (
      <button type="button" onClick={() => choose(s)}
        className={cn('block w-full border-l-[3px] px-3 py-1.5 text-left', isSel(s) ? 'border-primary bg-primary/10' : 'border-transparent hover:bg-muted/60')}>
        <span className="block truncate text-sm font-medium">{title}</span>
        <span className="block truncate text-xs text-muted-foreground">{sub}</span>
        {tag}
      </button>
    );
    const status = (a: Address) => a.is_verified ? <span className="mt-0.5 inline-block rounded-full border border-success/40 px-1.5 text-[10.5px] font-semibold leading-4 text-success">Validated</span>
      : a.suggested_address ? <span className="mt-0.5 inline-block rounded-full border border-warning/50 px-1.5 text-[10.5px] font-semibold leading-4 text-warning">Google suggests</span>
      : (a.validation_status === 'NOT_FOUND' || (!a.validation_status && a.geocode_status === 'ZERO_RESULTS')) ? <span className="mt-0.5 inline-block rounded-full border border-warning/50 px-1.5 text-[10.5px] font-semibold leading-4 text-warning">Not found</span>
      : null;

    const newItem = (s: Sel) => { if (dirty) { setMenu(false); ask('Discard the changes to this record?', 'Discard', () => open(s)); return; } open(s); };

    return (
      <>
      <AlertDialog open={!!popup} onOpenChange={(o) => { if (!o) setPopup(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{popup?.title}</AlertDialogTitle>
            <AlertDialogDescription>{popup?.text}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            {popup?.confirm ? (
              <>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction onClick={() => { const run = popup.confirm!.run; setPopup(null); run(); }}>{popup.confirm.label}</AlertDialogAction>
              </>
            ) : <AlertDialogAction>OK</AlertDialogAction>}
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <div className="grid min-h-[480px] max-w-full grid-cols-1 overflow-hidden rounded-lg border border-border/60 bg-card md:grid-cols-[280px_minmax(0,1fr)] xl:w-[calc(280px+50%)]">
        {/* list */}
        <nav aria-label="Contact records" className="border-b border-border/60 bg-muted/30 md:border-b-0 md:border-r">
          <div className="relative flex justify-end px-2.5 pt-2">
            <Button type="button" variant="outline" size="sm" className="h-7 gap-1 text-xs" aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu((m) => !m)}>
              <Plus className="h-3.5 w-3.5" />New
            </Button>
            {menu && (
              <div role="menu" className="absolute right-2.5 top-10 z-10 flex min-w-[160px] flex-col rounded-md border border-border bg-popover p-1 shadow-md">
                <button role="menuitem" type="button" className="rounded px-2.5 py-1.5 text-left text-sm hover:bg-muted" onClick={() => newItem({ kind: 'address', id: null })}>Address</button>
                <button role="menuitem" type="button" className="rounded px-2.5 py-1.5 text-left text-sm hover:bg-muted" onClick={() => newItem({ kind: 'note', id: null })}>Note</button>
                <button role="menuitem" type="button" className="rounded px-2.5 py-1.5 text-left text-sm hover:bg-muted" onClick={() => newItem({ kind: 'person', id: null })}>Contact Person</button>
              </div>
            )}
          </div>
          <p className="border-b border-border/60 px-3 py-1.5 text-sm font-bold">Contact Record</p>
          {!addr ? <p className="px-3 py-2 text-xs text-muted-foreground">Loading…</p> : (
            <>
              {addr.addresses.map((a) => (
                <Row key={`a${a.contact_point_id}`} s={{ kind: 'address', id: a.contact_point_id }} title={role(a)}
                  sub={streetCity(a.address) + (readOnly ? ` · from ${addr.inherited_from!.customer_name}` : '')} tag={status(a)} />
              ))}
              {notes.map((n) => <Row key={`n${n.note_id}`} s={{ kind: 'note', id: n.note_id }} title="Note" sub={n.note_text} />)}
              {legacy.map(({ c, p }) => <Row key={`l${p.contact_point_id}`} s={{ kind: 'legacy', contactId: c.contact_id, pointId: p.contact_point_id! }} title="Note (old system)" sub={p.value.replace(/\s*\n\s*/g, ' / ')} />)}
              {people.map((c) => <Row key={`p${c.contact_id}`} s={{ kind: 'person', id: c.contact_id }} title="Contact Person" sub={[personName(c), c.job_title].filter(Boolean).join(' · ')} />)}
              {!addr.addresses.length && !notes.length && !legacy.length && !people.length && <p className="px-3 py-2 text-xs text-muted-foreground">No records yet. Use New to add one.</p>}
            </>
          )}
        </nav>

        {/* card */}
        <section aria-live="polite" className="flex min-w-0 flex-col">
          {!sel || !form ? <p className="p-4 text-sm text-muted-foreground">Select a record, or use New to add one.</p> : (
            <>
              <div className="flex min-h-[44px] flex-wrap items-center gap-2 border-b border-border/60 px-3 py-1.5">
                <h2 className="text-sm font-semibold">
                  {form.kind === 'address' ? (isNew ? 'New address' : role(form.f)) : form.kind === 'person' ? 'Contact Person' : form.kind === 'legacy' ? 'Note (old system)' : 'Note'}
                </h2>
                {form.kind === 'address' && readOnly && <span className="rounded-full border border-info/40 px-2 text-xs font-medium leading-5 text-info">From account · {addr?.inherited_from?.customer_name}</span>}
                <div className="flex-1" />
                {!(form.kind === 'address' && readOnly && !isNew) && (
                  <>
                    {!isNew && (
                      <Button type="button" variant="ghost" size="sm" className="h-7 gap-1 text-xs" disabled={busy || (!!selAddr && (selAddr.bill || selAddr.ship))}
                        title={selAddr && (selAddr.bill || selAddr.ship) ? 'Move Billing and Shipping to another address first' : 'Remove'} onClick={remove}>
                        <Trash2 className="h-3.5 w-3.5" />Remove
                      </Button>
                    )}
                    <Button type="button" variant="outline" size="sm" className="h-7" disabled={busy || (!dirty && !isNew)} onClick={cancel}>Cancel</Button>
                    <Button type="button" size="sm" className="h-7" disabled={busy || !dirty} onClick={() => void save()}>{busy ? 'Saving…' : 'Save'}</Button>
                  </>
                )}
              </div>

              <div className="flex flex-col gap-3 p-4">
                {form.kind === 'address' && (() => {
                  const f = form.f, ro = readOnly && !isNew;
                  const setF = (p: Partial<AddressForm>) => setForm({ kind: 'address', f: { ...f, ...p } });
                  const changed = selAddr?.suggested_address ? changedLines(selAddr.address, selAddr.suggested_address) : new Set<number>();
                  return (
                    <>
                      {readOnly && !isNew && (
                        <p className="flex items-start gap-2 rounded-md bg-info-soft/40 px-2.5 py-2 text-sm text-info"><Info className="mt-0.5 h-4 w-4 shrink-0" />
                          <span>This customer has no addresses of its own, so it uses its account&apos;s. Use New › Address to bill or deliver it separately.</span></p>
                      )}
                      {addr?.missing_ship && !readOnly && (
                        <p className="flex items-start gap-2 rounded-md bg-warning-soft/40 px-2.5 py-2 text-sm text-warning"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                          <span><b className="text-foreground">No Shipping address.</b> This customer is delivered; tick Shipping Address on one address. Until then deliveries use the Billing address. Confirm against the old system.</span></p>
                      )}
                      {addr?.pickup && <p className="flex items-start gap-2 text-sm text-info"><Info className="mt-0.5 h-4 w-4 shrink-0" /><span>Pickup customer: only a Billing address is needed.</span></p>}
                      <div className="grid grid-cols-1 items-start gap-x-6 gap-y-3 sm:grid-cols-[minmax(0,460px)_auto]">
                        <div className="overflow-hidden rounded-md border border-input">
                          <textarea rows={5} aria-label="Address" readOnly={ro} value={f.address} onChange={(e) => setF({ address: e.target.value })}
                            placeholder={'Name or attention (optional)\nStreet\nCity, ST ZIP'} className="block w-full resize-none bg-transparent px-3 py-2 text-sm leading-5 focus:outline-none" />
                          <div className="grid grid-cols-[auto_minmax(0,1fr)] items-start border-t border-border/60">
                            <label htmlFor="addr-ins" className="pl-3 pt-2 text-sm font-semibold text-muted-foreground">Instructions:</label>
                            <textarea id="addr-ins" rows={2} readOnly={ro} value={f.instructions} onChange={(e) => setF({ instructions: e.target.value })}
                              placeholder="e.g. Delivery entrance on 55th St" className="block w-full resize-none bg-transparent px-2 py-2 text-sm leading-5 focus:outline-none" />
                          </div>
                        </div>
                        <div className="flex flex-col gap-2.5 pt-1 text-sm">
                          <label className={cn('flex items-center gap-2', ro && 'text-muted-foreground')}>
                            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" disabled={ro} checked={f.bill} onChange={(e) => setF({ bill: e.target.checked })} />Billing Address
                          </label>
                          {(!addr?.pickup || f.ship) && (
                            <label className={cn('flex items-center gap-2', ro && 'text-muted-foreground')}>
                              <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" disabled={ro} checked={f.ship} onChange={(e) => setF({ ship: e.target.checked })} />Shipping Address
                            </label>
                          )}
                          <label className={cn('flex items-center gap-2', ro && 'text-muted-foreground')}>
                            <input type="checkbox" className="h-4 w-4 accent-[hsl(var(--primary))]" disabled={ro} checked={f.validated} onChange={(e) => setF({ validated: e.target.checked })} />Validated
                          </label>
                          {selAddr?.latitude != null && selAddr.longitude != null && (
                            <a href={`https://www.google.com/maps/search/?api=1&query=${selAddr.latitude},${selAddr.longitude}`} target="_blank" rel="noreferrer"
                              className="mt-1 inline-flex items-center gap-1.5 font-medium text-primary hover:underline"><MapPin className="h-4 w-4" />Map</a>
                          )}
                        </div>
                      </div>
                      {selAddr?.suggested_address && !ro && (
                        <div className="grid grid-cols-1 items-start gap-x-4 gap-y-2 rounded-md border border-warning/30 bg-warning-soft/40 px-2.5 py-2 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto]">
                          <div><p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Typed</p><p className="whitespace-pre-line text-sm leading-5">{selAddr.address}</p></div>
                          <div><p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Google suggests</p>
                            <p className="text-sm leading-5">{selAddr.suggested_address.split('\n').map((l, i) => (
                              <span key={i} className="block">{changed.has(i) ? <mark className="rounded-sm bg-warning/25 px-0.5 text-inherit">{l}</mark> : l}</span>))}</p></div>
                          <div className="flex gap-1.5">
                            <Button type="button" size="sm" className="h-7" disabled={busy || dirty} onClick={() => addressAction(selAddr.contact_point_id, 'ACCEPT')}>Accept</Button>
                            <Button type="button" size="sm" variant="outline" className="h-7" disabled={busy || dirty} onClick={() => addressAction(selAddr.contact_point_id, 'REJECT')}>Reject</Button>
                          </div>
                        </div>
                      )}
                      {selAddr && !selAddr.is_verified && !selAddr.suggested_address && (selAddr.validation_status === 'NOT_FOUND' || (!selAddr.validation_status && selAddr.geocode_status === 'ZERO_RESULTS')) && (
                        <p className="flex items-start gap-2 rounded-md bg-warning-soft/40 px-2.5 py-2 text-sm text-warning"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                          <span>Google can&apos;t find this address. Correct it, or tick Validated if the drivers know it.</span></p>
                      )}
                      <p className="text-xs text-muted-foreground">Name or attention lines first, then the street, then city, state and ZIP; Google checks the last two. Instructions belong to this address and, when it is the Shipping address, print at the bottom of the invoice.</p>
                    </>
                  );
                })()}

                {(form.kind === 'note' || form.kind === 'legacy') && (
                  <>
                    <textarea rows={6} aria-label="Note" value={form.text} onChange={(e) => setForm({ ...form, text: e.target.value })}
                      placeholder="e.g. Call James to come to the door." className={box} />
                    <p className="text-xs text-muted-foreground">
                      {form.kind === 'legacy' ? 'Imported from the old system: move what matters to a Contact Person, then remove it.'
                        : sel.kind === 'note' && sel.id ? (() => { const n = notes.find((x) => x.note_id === sel.id); return n ? `Added by ${n.author_name} · ${new Date(n.created_at).toLocaleDateString()}` : ''; })()
                        : 'Also listed on the Notes tab.'}
                    </p>
                  </>
                )}

                {form.kind === 'person' && (() => {
                  const f = form.f;
                  const setF = (p: Partial<PersonForm>) => setForm({ kind: 'person', f: { ...f, ...p } });
                  const setPt = (i: number, p: Partial<Point>) => setF({ points: f.points.map((x, k) => (k === i ? { ...x, ...p } : x)) });
                  return (
                    <>
                      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <label className="text-xs font-semibold text-muted-foreground">First name<Input className="mt-1 h-8" value={f.first_name} onChange={(e) => setF({ first_name: e.target.value })} /></label>
                        <label className="text-xs font-semibold text-muted-foreground">Last name<Input className="mt-1 h-8" value={f.last_name} onChange={(e) => setF({ last_name: e.target.value })} /></label>
                        <label className="text-xs font-semibold text-muted-foreground sm:col-span-2">Role / title<Input className="mt-1 h-8" value={f.job_title} onChange={(e) => setF({ job_title: e.target.value })} placeholder="e.g. Accounts Payable" /></label>
                      </div>
                      <div className="flex flex-col gap-1.5">
                        <span className="text-xs font-semibold text-muted-foreground">Phone, email…</span>
                        {f.points.map((p, i) => (
                          <div key={i} className="grid grid-cols-[110px_minmax(0,1fr)_auto] items-center gap-2 sm:grid-cols-[110px_minmax(0,50%)_auto]">
                            <select aria-label="Type" value={p.type} onChange={(e) => setPt(i, { type: e.target.value })} className="h-8 rounded-md border border-input bg-transparent px-2 text-sm">
                              {PERSON_TYPES.map((t) => <option key={t} value={t}>{TYPE_LABEL[t]}</option>)}
                            </select>
                            <Input className="h-8" aria-label={TYPE_LABEL[p.type] ?? 'Value'} value={p.value} onChange={(e) => setPt(i, { value: e.target.value })} />
                            <Button type="button" variant="ghost" size="sm" className="h-8 w-8 p-0" title="Remove" onClick={() => setF({ points: f.points.filter((_, k) => k !== i) })}><Trash2 className="h-4 w-4" /></Button>
                          </div>
                        ))}
                        <div><Button type="button" variant="ghost" size="sm" className="h-7 gap-1 text-xs"
                          onClick={() => setF({ points: [...f.points, { contact_point_id: null, type: 'PHONE', value: '', label: '', sequence: f.points.length + 1, is_primary: false }] })}>
                          <Plus className="h-3.5 w-3.5" />Add phone or email</Button></div>
                      </div>
                      <p className="text-xs text-muted-foreground">Also shown in Organizer › Contacts, marked Customer.</p>
                    </>
                  );
                })()}
              </div>
            </>
          )}
        </section>
      </div>
      </>
    );
  },
);
