'use client';

import {
  useState, useEffect, useCallback, useRef,
  forwardRef, useImperativeHandle,
} from 'react';
import {
  Phone, Smartphone, Printer, Mail, MapPin, Globe, MoreHorizontal,
  Plus, Star, Trash2, Ban,
} from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { cn } from '@/lib/utils';

// ── Types ─────────────────────────────────────────────────────────────────────

const POINT_TYPES = ['PHONE', 'MOBILE', 'FAX', 'EMAIL', 'ADDRESS', 'WEBSITE', 'OTHER'] as const;
type PointType = typeof POINT_TYPES[number];


const TYPE_LABEL: Record<PointType, string> = {
  PHONE: 'Phone', MOBILE: 'Mobile', FAX: 'Fax',
  EMAIL: 'Email', ADDRESS: 'Address', WEBSITE: 'Website', OTHER: 'Other',
};

const TYPE_ICON: Record<PointType, React.ComponentType<{ className?: string }>> = {
  PHONE: Phone, MOBILE: Smartphone, FAX: Printer,
  EMAIL: Mail, ADDRESS: MapPin, WEBSITE: Globe, OTHER: MoreHorizontal,
};

interface ContactPoint {
  contact_point_id: number | null;
  type: PointType;
  value: string;
  label: string;
  sequence: number;
  is_primary: boolean;
  is_active: boolean;
  do_not_contact: boolean;
  country_dial_code: string;
  geocode_status?: string;
  formatted_address?: string | null;
  latitude?: number | null;
  longitude?: number | null;
}

interface Contact {
  contact_id: number;
  salutation: string;
  first_name: string;
  last_name: string;
  contact_name: string;
  job_title: string;
  department: string;
  is_primary: boolean;
  is_active: boolean;
  contact_points: ContactPoint[];
}

interface ContactForm {
  contact_id: number | null;
  salutation: string;
  first_name: string;
  last_name: string;
  contact_name: string;
  job_title: string;
  department: string;
  is_primary: boolean;
  is_active: boolean;
  contact_points: ContactPoint[];
}

export interface CustomerContactsTabHandle {
  save: () => Promise<void>;
  cancel: () => void;
}

interface CustomerContactsTabProps {
  tenantId: number;
  customerId: number | null;
  onDirtyChange: (dirty: boolean) => void;
}

// ── Constants & helpers ───────────────────────────────────────────────────────

const EMPTY_FORM: ContactForm = {
  contact_id: null, salutation: '', first_name: '', last_name: '',
  contact_name: '', job_title: '', department: '',
  is_primary: false, is_active: true, contact_points: [],
};

function contactToForm(c: Contact): ContactForm {
  return {
    contact_id: c.contact_id,
    salutation: c.salutation, first_name: c.first_name, last_name: c.last_name,
    contact_name: c.contact_name, job_title: c.job_title, department: c.department,
    is_primary: c.is_primary, is_active: c.is_active,
    contact_points: c.contact_points.map(p => ({ ...p })),
  };
}

function deriveContactName(first: string, last: string) {
  return [first.trim(), last.trim()].filter(Boolean).join(' ');
}

const AVATAR_COLORS = [
  'bg-blue-100 text-blue-700 dark:bg-blue-950/50 dark:text-blue-300',
  'bg-violet-100 text-violet-700 dark:bg-violet-950/50 dark:text-violet-300',
  'bg-rose-100 text-rose-700 dark:bg-rose-950/50 dark:text-rose-300',
  'bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300',
  'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300',
  'bg-cyan-100 text-cyan-700 dark:bg-cyan-950/50 dark:text-cyan-300',
  'bg-orange-100 text-orange-700 dark:bg-orange-950/50 dark:text-orange-300',
  'bg-pink-100 text-pink-700 dark:bg-pink-950/50 dark:text-pink-300',
];

function avatarColor(name: string) {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) | 0;
  return AVATAR_COLORS[Math.abs(hash) % AVATAR_COLORS.length];
}

function initials(name: string) {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 0 || !parts[0]) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function GeocodeStatus({ status, formattedAddress }: { status?: string; formattedAddress?: string | null }) {
  if (!status || status === 'SKIPPED') return null;
  if (status === 'PENDING')
    return <p className="mt-0.5 text-[11px] text-amber-600 dark:text-amber-400">Pending geocoding…</p>;
  if (status === 'PROCESSING')
    return <p className="mt-0.5 text-[11px] text-sky-600 dark:text-sky-400">Processing…</p>;
  if (status === 'OK')
    return <p className="mt-0.5 text-[11px] text-emerald-600 dark:text-emerald-400 truncate">{formattedAddress ?? 'Geocoded'}</p>;
  if (status === 'ZERO_RESULTS')
    return <p className="mt-0.5 text-[11px] text-orange-600 dark:text-orange-400">Address not found by geocoder</p>;
  if (status === 'FAILED')
    return <p className="mt-0.5 text-[11px] text-destructive">Geocoding failed</p>;
  return null;
}

// ── Component ─────────────────────────────────────────────────────────────────

export const CustomerContactsTab = forwardRef<CustomerContactsTabHandle, CustomerContactsTabProps>(
  function CustomerContactsTab({ tenantId, customerId, onDirtyChange }, ref) {
    const [contacts, setContacts]     = useState<Contact[]>([]);
    const [isLoading, setIsLoading]   = useState(false);
    const [selection, setSelection]   = useState<number | 'new' | null>(null);
    const [form, setForm]             = useState<ContactForm>(EMPTY_FORM);
    const [isSaving, setIsSaving]     = useState(false);
    const savedFormRef                = useRef<ContactForm>(EMPTY_FORM);
    const loadedCustomerIdRef         = useRef<number | null | undefined>(undefined);
    const contactsRef                 = useRef<Contact[]>([]);

    const isDirty    = JSON.stringify(form) !== JSON.stringify(savedFormRef.current);
    const isFormValid = form.contact_name.trim() !== '';

    useEffect(() => { contactsRef.current = contacts; }, [contacts]);
    useEffect(() => { onDirtyChange(isDirty); }, [isDirty, onDirtyChange]);

    const applySelection = (contact: Contact) => {
      const f = contactToForm(contact);
      setSelection(contact.contact_id);
      setForm(f);
      savedFormRef.current = f;
    };

    const applyNew = () => {
      setSelection('new');
      setForm(EMPTY_FORM);
      savedFormRef.current = EMPTY_FORM;
    };

    const load = useCallback(async (): Promise<Contact[]> => {
      if (!customerId) return [];
      setIsLoading(true);
      try {
        const res  = await fetch(`/api/customers/contacts?tenant_id=${tenantId}&customer_id=${customerId}`);
        const json = await res.json() as { data?: Contact[]; error?: string };
        if (!res.ok || json.error) {
          toast.error(json.error ?? 'Could not load contacts.', { duration: Infinity });
          return [];
        }
        const loaded = json.data ?? [];
        setContacts(loaded);
        loadedCustomerIdRef.current = customerId;
        return loaded;
      } finally {
        setIsLoading(false);
      }
    }, [tenantId, customerId]);

    useEffect(() => {
      if (customerId !== loadedCustomerIdRef.current) {
        setContacts([]);
        setSelection(null);
        setForm(EMPTY_FORM);
        savedFormRef.current = EMPTY_FORM;
        load().then((loaded) => {
          if (loaded.length > 0) {
            const primary = loaded.find(c => c.is_primary) ?? loaded[0];
            applySelection(primary);
          }
        });
      }
    }, [customerId, load]);

    const save = useCallback(async () => {
      if (!customerId || !isFormValid) return;
      setIsSaving(true);
      try {
        const res  = await fetch('/api/customers/contacts', {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({ tenant_id: tenantId, customer_id: customerId, contact: form }),
        });
        const json = await res.json() as { data?: { contact_id?: number }; error?: string };
        if (!res.ok || json.error) {
          toast.error(json.error ?? 'Could not save contact.', { duration: Infinity });
          return;
        }
        const savedId = json.data?.contact_id ?? form.contact_id;
        const loaded  = await load();
        const saved   = loaded.find(c => c.contact_id === savedId);
        if (saved) applySelection(saved);
        else if (loaded.length > 0) applySelection(loaded[0]);
      } finally {
        setIsSaving(false);
      }
    }, [customerId, form, isFormValid, load, tenantId]);

    const cancel = useCallback(() => {
      const f = savedFormRef.current;
      setForm(f);
      if (f.contact_id !== null) {
        const contact = contactsRef.current.find(c => c.contact_id === f.contact_id);
        if (contact) { setSelection(contact.contact_id); return; }
      }
      const list = contactsRef.current;
      if (list.length > 0) applySelection(list.find(c => c.is_primary) ?? list[0]);
      else { setSelection(null); setForm(EMPTY_FORM); savedFormRef.current = EMPTY_FORM; }
    }, []);

    useImperativeHandle(ref, () => ({ save, cancel }), [save, cancel]);

    // ── Field helpers ─────────────────────────────────────────────────────────

    const setField = <K extends keyof ContactForm>(k: K, v: ContactForm[K]) =>
      setForm(f => ({ ...f, [k]: v }));

    const updateNameField = (field: 'first_name' | 'last_name', value: string) =>
      setForm(f => {
        const prevDerived = deriveContactName(f.first_name, f.last_name);
        const newFirst    = field === 'first_name' ? value : f.first_name;
        const newLast     = field === 'last_name'  ? value : f.last_name;
        const newDerived  = deriveContactName(newFirst, newLast);
        const autoUpdate  = f.contact_name === '' || f.contact_name === prevDerived;
        return { ...f, [field]: value, contact_name: autoUpdate ? newDerived : f.contact_name };
      });

    const updatePoint = (idx: number, updates: Partial<ContactPoint>) =>
      setForm(f => ({
        ...f,
        contact_points: f.contact_points.map((p, i) => i === idx ? { ...p, ...updates } : p),
      }));

    const removePoint = (idx: number) =>
      setForm(f => ({ ...f, contact_points: f.contact_points.filter((_, i) => i !== idx) }));

    const addPoint = (type: PointType) => {
      const seq = form.contact_points.filter(p => p.type === type).length + 1;
      setForm(f => ({
        ...f,
        contact_points: [...f.contact_points, {
          contact_point_id: null, type, value: '', label: '', sequence: seq,
          is_primary: false, is_active: true, do_not_contact: false, country_dial_code: '',
        }],
      }));
    };

    const togglePointPrimary = (idx: number) =>
      setForm(f => {
        const type      = f.contact_points[idx].type;
        const wasPrimary = f.contact_points[idx].is_primary;
        return {
          ...f,
          contact_points: f.contact_points.map((p, i) => {
            if (i === idx) return { ...p, is_primary: !wasPrimary };
            if (p.type === type && !wasPrimary) return { ...p, is_primary: false };
            return p;
          }),
        };
      });

    // ── Early exit ────────────────────────────────────────────────────────────

    if (!customerId) {
      return (
        <p className="py-4 text-sm text-muted-foreground">
          Select a customer to view contacts.
        </p>
      );
    }


    // ── Render ────────────────────────────────────────────────────────────────

    return (
      <div className="flex flex-col overflow-hidden rounded-lg border border-border/60" style={{ height: '520px' }}>

        {/* Tab header */}
        <div className="flex flex-wrap shrink-0 items-center gap-2 border-b border-border/60 px-3 py-1.5">
          <Button type="button" variant="ghost" size="sm" onClick={applyNew} className="h-7 gap-1 px-2 text-xs">
            <Plus className="h-3.5 w-3.5" />
            Contact
          </Button>
          <div className="flex-1" />
          <Button
            type="button" variant="outline" size="sm"
            onClick={cancel} disabled={!isDirty} className="h-7"
          >
            Cancel
          </Button>
          <Button
            type="button" size="sm" onClick={save}
            disabled={isSaving || !isDirty || !isFormValid || selection === null}
            className="h-7"
          >
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
        </div>

        {/* Body: left list + right form */}
        <div className="flex flex-1 overflow-hidden divide-x divide-border/60">

          {/* Left panel — contact cards */}
          <div className="flex w-60 shrink-0 flex-col overflow-hidden">
            <div className="flex-1 overflow-y-auto">
              {isLoading ? (
                <p className="p-3 text-xs text-muted-foreground">Loading…</p>
              ) : contacts.length === 0 && selection !== 'new' ? (
                <p className="p-3 text-xs text-muted-foreground">No contacts yet.</p>
              ) : (
                contacts.map(contact => {
                  const usedTypes = Array.from(new Set(contact.contact_points.map(p => p.type))) as PointType[];
                  return (
                    <button
                      key={contact.contact_id}
                      type="button"
                      onClick={() => applySelection(contact)}
                      className={cn(
                        'w-full border-b border-border/40 px-3 py-2.5 text-left transition-colors',
                        selection === contact.contact_id ? 'bg-muted' : 'hover:bg-muted/50',
                        !contact.is_active && 'opacity-50',
                      )}
                    >
                      <div className="flex items-center gap-2.5">
                        {/* Avatar */}
                        <div className={cn(
                          'relative h-9 w-9 shrink-0 rounded-full flex items-center justify-center text-sm font-semibold select-none',
                          avatarColor(contact.contact_name || '?'),
                        )}>
                          {initials(contact.contact_name || '?')}
                          {contact.is_primary && (
                            <div className="absolute -right-0.5 -top-0.5 flex h-4 w-4 items-center justify-center rounded-full bg-background shadow-sm">
                              <Star className="h-2.5 w-2.5 text-amber-500" fill="currentColor" />
                            </div>
                          )}
                        </div>
                        {/* Text */}
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium leading-tight">
                            {contact.contact_name}
                          </p>
                          {contact.job_title && (
                            <p className="truncate text-xs text-muted-foreground leading-tight">
                              {contact.job_title}
                            </p>
                          )}
                          {usedTypes.length > 0 && (
                            <div className="mt-0.5 flex gap-1">
                              {usedTypes.map(t => {
                                const Icon = TYPE_ICON[t];
                                return <Icon key={t} className="h-3 w-3 text-muted-foreground/50" />;
                              })}
                            </div>
                          )}
                        </div>
                      </div>
                    </button>
                  );
                })
              )}
            </div>
          </div>

          {/* Right panel — form */}
          {selection === null ? (
            <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
              Select a contact or click + Contact
            </div>
          ) : (
            <div className="flex-1 overflow-y-auto px-4 py-3 space-y-4">

              {/* Contact details */}
              <div className="space-y-2.5">
                <div className="grid grid-cols-[76px_1fr_1fr] gap-2">
                  <div>
                    <p className="mb-0.5 text-xs text-muted-foreground">Salutation</p>
                    <Input
                      value={form.salutation}
                      onChange={e => setField('salutation', e.target.value)}
                      className="h-7 text-sm" placeholder="Mr."
                    />
                  </div>
                  <div>
                    <p className="mb-0.5 text-xs text-muted-foreground">First Name</p>
                    <Input
                      value={form.first_name}
                      onChange={e => updateNameField('first_name', e.target.value)}
                      className="h-7 text-sm"
                    />
                  </div>
                  <div>
                    <p className="mb-0.5 text-xs text-muted-foreground">Last Name</p>
                    <Input
                      value={form.last_name}
                      onChange={e => updateNameField('last_name', e.target.value)}
                      className="h-7 text-sm"
                    />
                  </div>
                </div>
                <div>
                  <p className="mb-0.5 text-xs text-muted-foreground">
                    Display Name <span className="text-destructive">*</span>
                  </p>
                  <Input
                    value={form.contact_name}
                    onChange={e => setField('contact_name', e.target.value)}
                    className="h-7 text-sm" placeholder="Full name or company"
                  />
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <p className="mb-0.5 text-xs text-muted-foreground">Job Title</p>
                    <Input
                      value={form.job_title}
                      onChange={e => setField('job_title', e.target.value)}
                      className="h-7 text-sm"
                    />
                  </div>
                  <div>
                    <p className="mb-0.5 text-xs text-muted-foreground">Department</p>
                    <Input
                      value={form.department}
                      onChange={e => setField('department', e.target.value)}
                      className="h-7 text-sm"
                    />
                  </div>
                </div>
                <div className="flex items-center gap-4">
                  <button
                    type="button"
                    onClick={() => setField('is_primary', !form.is_primary)}
                    className={cn(
                      'flex items-center gap-1.5 text-xs transition-colors',
                      form.is_primary ? 'text-amber-500' : 'text-muted-foreground hover:text-foreground',
                    )}
                  >
                    <Star className="h-3.5 w-3.5" fill={form.is_primary ? 'currentColor' : 'none'} />
                    Primary contact
                  </button>
                  <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer">
                    <input
                      type="checkbox"
                      checked={form.is_active}
                      onChange={e => setField('is_active', e.target.checked)}
                      className="h-3.5 w-3.5 rounded border-input"
                    />
                    Active
                  </label>
                </div>
              </div>

              {/* Divider */}
              <div className="border-t border-border/40" />

              {/* Contact points — flat rows */}
              <div className="space-y-1.5">
                {/* Column headers (only when rows exist) */}
                {form.contact_points.length > 0 && (
                  <div
                    className="grid items-center gap-2 px-0.5"
                    style={{ gridTemplateColumns: '108px 80px 1fr auto' }}
                  >
                    <p className="text-xs text-muted-foreground">Type</p>
                    <p className="text-xs text-muted-foreground">Label</p>
                    <p className="text-xs text-muted-foreground">Value</p>
                    <div className="w-[68px]" />
                  </div>
                )}

                {form.contact_points.map((p, i) => (
                  <div
                    key={p.contact_point_id ?? `new-${i}`}
                    className="grid items-start gap-2"
                    style={{ gridTemplateColumns: '108px 80px 1fr auto' }}
                  >
                    {/* Type */}
                    <Select
                      value={p.type}
                      onValueChange={(t) => updatePoint(i, { type: t as PointType })}
                    >
                      <SelectTrigger className="h-7 text-xs">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {POINT_TYPES.map(t => (
                          <SelectItem key={t} value={t} className="text-xs">
                            {TYPE_LABEL[t]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>

                    {/* Label */}
                    <Input
                      value={p.label}
                      onChange={e => updatePoint(i, { label: e.target.value })}
                      className="h-7 text-xs"
                      placeholder="e.g. Office"
                    />

                    {/* Value + geocode status */}
                    <div>
                      <textarea
                        value={p.value}
                        onChange={e => updatePoint(i, { value: e.target.value })}
                        rows={p.type === 'ADDRESS' ? 3 : 1}
                        className="w-full resize-none rounded border border-input bg-transparent px-2 py-1 text-sm placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-ring"
                        placeholder={
                          p.type === 'EMAIL'                    ? 'email@example.com' :
                          p.type === 'WEBSITE'                  ? 'https://' :
                          p.type === 'ADDRESS'                  ? '123 Main St\nCity, State 12345' :
                          p.type === 'PHONE' || p.type === 'MOBILE' || p.type === 'FAX'
                                                                ? '+1 555-1234' : ''
                        }
                      />
                      {p.type === 'ADDRESS' && (
                        <GeocodeStatus
                          status={p.geocode_status}
                          formattedAddress={p.formatted_address}
                        />
                      )}
                    </div>

                    {/* Controls */}
                    <div className="flex items-center gap-0.5 pt-0.5">
                      <button
                        type="button"
                        title={p.is_primary ? 'Primary' : 'Set as primary'}
                        onClick={() => togglePointPrimary(i)}
                        className={cn(
                          'rounded p-0.5 transition-colors',
                          p.is_primary ? 'text-amber-500' : 'text-muted-foreground/40 hover:text-amber-400',
                        )}
                      >
                        <Star className="h-3.5 w-3.5" fill={p.is_primary ? 'currentColor' : 'none'} />
                      </button>
                      <button
                        type="button"
                        title={p.do_not_contact ? 'Do not contact' : 'Mark as do not contact'}
                        onClick={() => updatePoint(i, { do_not_contact: !p.do_not_contact })}
                        className={cn(
                          'rounded p-0.5 transition-colors',
                          p.do_not_contact ? 'text-rose-500' : 'text-muted-foreground/40 hover:text-rose-400',
                        )}
                      >
                        <Ban className="h-3.5 w-3.5" />
                      </button>
                      <button
                        type="button"
                        onClick={() => removePoint(i)}
                        className="rounded p-0.5 text-muted-foreground/40 hover:text-destructive transition-colors"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </div>
                ))}

                {/* Add row */}
                <button
                  type="button"
                  onClick={() => addPoint('PHONE')}
                  className="mt-1 flex items-center gap-1 rounded border border-dashed border-border/50 px-2 py-1 text-xs text-muted-foreground hover:border-border hover:text-foreground transition-colors"
                >
                  <Plus className="h-3.5 w-3.5" />
                  Add contact method
                </button>
              </div>

            </div>
          )}
        </div>
      </div>
    );
  }
);
