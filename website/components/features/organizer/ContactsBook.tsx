'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ArrowLeft, Download, Plus, Search, Star, Tags, Upload, Users } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useNavGuard } from '@/components/layout/nav-context';
import { useDeepLinkId } from '@/lib/use-deep-link';
import { cn } from '@/lib/utils';
import { toContactsCsv, toVCards, type ContactDetail, type ContactTag } from '@/lib/organizer/contacts';
import { api, Avatar, downloadText, TagChip, type ContactRow } from './contacts-ui';
import { ContactForm } from './ContactForm';
import { ContactView } from './ContactView';
import { ContactImportDialog } from './ContactImportDialog';
import { ContactDuplicatesDialog } from './ContactDuplicatesDialog';
import { ContactTagsDialog } from './ContactTagsDialog';

type Filter = 'all' | 'company' | 'customers' | 'favorites';
const FILTERS: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' }, { key: 'company', label: 'Company' }, { key: 'customers', label: 'Customers' }, { key: 'favorites', label: 'Favourites' },
];

const letterOf = (r: ContactRow) => {
  const ch = (r.sort_name || r.full_name).charAt(0).toUpperCase();
  return /[A-Z]/.test(ch) ? ch : '#';
};

export function ContactsBook({ tenantId, canEdit, canDelete }: { tenantId: number; canEdit: boolean; canDelete: boolean }) {
  const [rows, setRows] = useState<ContactRow[] | null>(null);
  const [tags, setTags] = useState<ContactTag[]>([]);
  const [filter, setFilter] = useState<Filter>('all');
  const [tagFilter, setTagFilter] = useState<number | null>(null);
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<ContactDetail | null>(null);
  const [mode, setMode] = useState<'view' | 'edit' | 'new'>('view');
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [dialog, setDialog] = useState<'import' | 'duplicates' | 'tags' | null>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  useNavGuard(mode !== 'view');

  const loadList = useCallback(() => {
    api<ContactRow[]>(`/api/organizer/contacts?tenant_id=${tenantId}`).then(setRows).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  const loadTags = useCallback(() => {
    api<ContactTag[]>(`/api/organizer/contacts/tags?tenant_id=${tenantId}`).then(setTags).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  const loadDetail = useCallback((id: number) => {
    api<ContactDetail>(`/api/organizer/contacts?tenant_id=${tenantId}&id=${id}`)
      .then((d) => { setDetail(d); setSelectedId(d.contact_id); })
      .catch((e: Error) => { setError(e.message); setDetail(null); });
  }, [tenantId]);
  useEffect(() => { loadList(); loadTags(); }, [loadList, loadTags]);
  useDeepLinkId('contact', rows !== null, (id) => { setMode('view'); loadDetail(id); });

  const select = (id: number) => {
    if (mode !== 'view' && !window.confirm('Leave without saving your changes?')) return;
    setMode('view');
    setNotice(null);
    setError(null);
    setSelectedId(id);
    setDetail((d) => (d?.contact_id === id ? d : null));
    loadDetail(id);
  };

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    const digits = q.replace(/\D/g, '');
    return (rows ?? []).filter((r) =>
      (filter === 'all' || (filter === 'company' && r.kind === 'COMPANY') || (filter === 'customers' && r.kind === 'CUSTOMER') || (filter === 'favorites' && r.is_favorite))
      && (tagFilter === null || r.tag_ids.includes(tagFilter))
      && (q === '' || q.split(/\s+/).every((w) => r.search.includes(w)) || (digits.length >= 3 && r.search.includes(digits))));
  }, [rows, filter, tagFilter, search]);

  const grouped = useMemo(() => {
    const out: { letter: string; items: ContactRow[] }[] = [];
    for (const r of shown) {
      const l = letterOf(r);
      if (out.length === 0 || out[out.length - 1].letter !== l) out.push({ letter: l, items: [r] });
      else out[out.length - 1].items.push(r);
    }
    return out;
  }, [shown]);

  const exportAs = async (format: 'vcf' | 'csv') => {
    setError(null);
    try {
      const data = await api<ContactDetail[]>('/api/organizer/contacts', 'POST', { tenant_id: tenantId, export: shown.map((r) => r.contact_id) });
      const stamp = new Date().toISOString().slice(0, 10);
      if (format === 'vcf') downloadText(`contacts-${stamp}.vcf`, toVCards(data), 'text/vcard;charset=utf-8');
      else downloadText(`contacts-${stamp}.csv`, toContactsCsv(data), 'text/csv;charset=utf-8');
    } catch (e) { setError((e as Error).message); }
  };

  const afterSave = (c: ContactDetail) => {
    setMode('view');
    setNotice(null);
    loadList();
    loadTags();
    loadDetail(c.contact_id);
  };
  const afterDelete = (result: string) => {
    setNotice(result === 'DEACTIVATED' ? 'The contact had notes, so it was deactivated and its notes kept.' : 'Contact deleted.');
    setDetail(null);
    setSelectedId(null);
    loadList();
    loadTags();
  };

  const showDetailPane = mode !== 'view' || selectedId !== null;

  return (
    <div className="flex h-[calc(100dvh-7.5rem)] min-h-[32rem] gap-3 p-2 sm:p-3">
      {/* List pane */}
      <aside className={cn('flex w-full flex-col rounded-lg border bg-card lg:w-[24rem] lg:shrink-0', showDetailPane && 'hidden lg:flex')}>
        <div className="space-y-2 border-b p-3">
          <div className="flex items-center justify-between gap-2">
            <h1 className="text-xl font-semibold">Contacts</h1>
            <div className="flex gap-1">
              {canEdit && (
                <Button size="sm" onClick={() => { setMode('new'); setDetail(null); setSelectedId(null); setNotice(null); }}>
                  <Plus className="mr-1 h-4 w-4" />New
                </Button>
              )}
              <DropdownMenu>
                <DropdownMenuTrigger asChild><Button size="sm" variant="outline" aria-label="More">•••</Button></DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  {canEdit && <DropdownMenuItem onSelect={() => setDialog('import')}><Upload className="mr-2 h-4 w-4" />Import vCard / CSV…</DropdownMenuItem>}
                  <DropdownMenuItem disabled={shown.length === 0} onSelect={() => exportAs('vcf')}><Download className="mr-2 h-4 w-4" />Export vCard ({shown.length})</DropdownMenuItem>
                  <DropdownMenuItem disabled={shown.length === 0} onSelect={() => exportAs('csv')}><Download className="mr-2 h-4 w-4" />Export CSV ({shown.length})</DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => setDialog('duplicates')}><Users className="mr-2 h-4 w-4" />Find duplicates…</DropdownMenuItem>
                  {canEdit && <DropdownMenuItem onSelect={() => setDialog('tags')}><Tags className="mr-2 h-4 w-4" />Manage tags…</DropdownMenuItem>}
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input ref={searchRef} type="search" placeholder="Search name, company, email, phone" value={search}
              onChange={(e) => setSearch(e.target.value)} className="pl-8" />
          </div>
          <div className="flex flex-wrap gap-1">
            {FILTERS.map((f) => (
              <button key={f.key} type="button" onClick={() => setFilter(f.key)}
                className={cn('rounded-full px-2.5 py-0.5 text-xs font-medium', filter === f.key ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground')}>
                {f.key === 'favorites' && <Star className="mr-0.5 inline h-3 w-3" />}{f.label}
              </button>
            ))}
          </div>
          {notice && !showDetailPane && <p className="text-xs text-muted-foreground lg:hidden">{notice}</p>}
          {tags.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {tags.map((t) => (
                <TagChip key={t.tag_id} tag={t} active={tagFilter === null ? undefined : tagFilter === t.tag_id}
                  onClick={() => setTagFilter(tagFilter === t.tag_id ? null : t.tag_id)} />
              ))}
            </div>
          )}
        </div>
        <div className="flex-1 overflow-y-auto">
          {rows === null ? <p className="p-3 text-sm text-muted-foreground">Loading…</p>
            : shown.length === 0 ? (
              <p className="p-3 text-sm text-muted-foreground">
                {rows.length === 0 ? 'No contacts yet. Add one, or import a vCard or CSV file.' : 'No contact matches.'}
              </p>
            ) : grouped.map((g) => (
              <div key={g.letter}>
                <div className="sticky top-0 z-10 border-b bg-muted/80 px-3 py-0.5 text-xs font-semibold text-muted-foreground backdrop-blur">{g.letter}</div>
                <ul>
                  {g.items.map((r) => (
                    <li key={r.contact_id}>
                      <button type="button" onClick={() => select(r.contact_id)}
                        className={cn('flex w-full items-center gap-3 border-b px-3 py-2 text-left hover:bg-muted/60', selectedId === r.contact_id && 'bg-primary/10')}>
                        <Avatar name={r.full_name} size="sm" />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-sm font-medium">{r.full_name}</span>
                          <span className="block truncate text-xs text-muted-foreground">
                            {r.kind === 'CUSTOMER' ? (r.customer_name ?? 'Customer') : (r.company_name || r.job_title || r.email || r.phone || '')}
                          </span>
                        </span>
                        {r.is_favorite && <Star className="h-3.5 w-3.5 shrink-0 fill-amber-400 text-amber-500" />}
                        {r.kind === 'CUSTOMER' && <span className="shrink-0 rounded bg-sky-100 px-1.5 text-[10px] font-medium text-sky-800 dark:bg-sky-900/40 dark:text-sky-200">Customer</span>}
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
        </div>
        <div className="border-t px-3 py-1.5 text-xs text-muted-foreground">{shown.length} of {rows?.length ?? 0} contacts</div>
      </aside>

      {/* Detail pane */}
      <main className={cn('flex-1 overflow-y-auto rounded-lg border bg-card p-4 sm:p-6', !showDetailPane && 'hidden lg:block')}>
        <button type="button" className="mb-3 flex items-center gap-1 text-sm text-primary lg:hidden"
          onClick={() => { if (mode !== 'view' && !window.confirm('Leave without saving your changes?')) return; setMode('view'); setSelectedId(null); setDetail(null); }}>
          <ArrowLeft className="h-4 w-4" /> Contacts
        </button>
        {error && <p role="alert" className="mb-3 text-sm text-destructive">{error}</p>}
        {notice && <p className="mb-3 text-sm text-muted-foreground">{notice}</p>}
        {mode === 'new' ? (
          <ContactForm key="new" tenantId={tenantId} contact={null} tags={tags} onSaved={afterSave} onTagsChanged={loadTags}
            onCancel={() => setMode('view')} />
        ) : mode === 'edit' && detail ? (
          <ContactForm key={`edit-${detail.contact_id}`} tenantId={tenantId} contact={detail} tags={tags} onSaved={afterSave} onTagsChanged={loadTags}
            onCancel={() => setMode('view')} />
        ) : detail ? (
          <ContactView key={detail.contact_id} tenantId={tenantId} contact={detail} canEdit={canEdit} canDelete={canDelete}
            onEdit={() => setMode('edit')} onDeleted={afterDelete} onError={setError}
            onChanged={() => { loadDetail(detail.contact_id); loadList(); }} />
        ) : selectedId !== null ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : (
          <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Pick a contact, or add a new one.</div>
        )}
      </main>

      {canEdit && <ContactImportDialog tenantId={tenantId} open={dialog === 'import'} onOpenChange={(o) => setDialog(o ? 'import' : null)}
        onImported={() => { loadList(); loadTags(); }} />}
      <ContactDuplicatesDialog tenantId={tenantId} open={dialog === 'duplicates'} onOpenChange={(o) => setDialog(o ? 'duplicates' : null)}
        canMerge={canEdit && canDelete} onMerged={(id) => { loadList(); loadTags(); select(id); }} />
      <ContactTagsDialog tenantId={tenantId} open={dialog === 'tags'} onOpenChange={(o) => setDialog(o ? 'tags' : null)}
        tags={tags} canDelete={canDelete} onChanged={() => { loadTags(); loadList(); if (detail) loadDetail(detail.contact_id); }} />
    </div>
  );
}
