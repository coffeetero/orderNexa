'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import type { ContactTag } from '@/lib/organizer/contacts';
import { api, TAG_COLORS, TagChip } from './contacts-ui';

/** Rename, recolour and delete contact tags. */
export function ContactTagsDialog({ tenantId, open, onOpenChange, tags, onChanged, canDelete }: {
  tenantId: number; open: boolean; onOpenChange: (o: boolean) => void; tags: ContactTag[]; onChanged: () => void; canDelete: boolean;
}) {
  const [names, setNames] = useState<Record<number, string>>({});
  const [newName, setNewName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<number | null>(null);

  const run = async (fn: () => Promise<unknown>) => {
    setError(null);
    try { await fn(); onChanged(); } catch (e) { setError((e as Error).message); }
  };
  const save = (t: ContactTag, patch: Partial<ContactTag>) =>
    run(() => api('/api/organizer/contacts/tags', 'POST', { tenant_id: tenantId, tag_id: t.tag_id, tag_name: t.tag_name, tag_color: t.tag_color, ...patch }));

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Tags</DialogTitle>
          <DialogDescription>Tags group contacts (suppliers, drivers, VIP…). Deleting a tag keeps the contacts.</DialogDescription>
        </DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <ul className="max-h-[50vh] space-y-2 overflow-auto">
          {tags.map((t) => (
            <li key={t.tag_id} className="flex items-center gap-2">
              <TagChip tag={t} className="max-w-[6rem] truncate" />
              <Input className="h-8 flex-1" value={names[t.tag_id] ?? t.tag_name}
                onChange={(e) => setNames((n) => ({ ...n, [t.tag_id]: e.target.value }))}
                onBlur={() => { const v = names[t.tag_id]; if (v !== undefined && v !== t.tag_name) void save(t, { tag_name: v }); }} />
              <select aria-label="Colour" className="h-8 rounded-md border bg-background px-1 text-xs" value={t.tag_color}
                onChange={(e) => save(t, { tag_color: e.target.value })}>
                {TAG_COLORS.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
              <span className="w-8 text-right text-xs text-muted-foreground">{t.contact_count ?? 0}</span>
              {canDelete && (confirm === t.tag_id ? (
                <Button size="sm" variant="destructive" onClick={() => { setConfirm(null); void run(() => api(`/api/organizer/contacts/tags?tenant_id=${tenantId}&id=${t.tag_id}`, 'DELETE')); }}>Delete</Button>
              ) : (
                <Button size="sm" variant="ghost" onClick={() => setConfirm(t.tag_id)}>Delete</Button>
              ))}
            </li>
          ))}
          {tags.length === 0 && <li className="text-sm text-muted-foreground">No tags yet.</li>}
        </ul>
        <div className="flex gap-2">
          <Input className="h-8" placeholder="New tag" value={newName} onChange={(e) => setNewName(e.target.value)} />
          <Button size="sm" disabled={!newName.trim()}
            onClick={() => run(async () => { await api('/api/organizer/contacts/tags', 'POST', { tenant_id: tenantId, tag_name: newName }); setNewName(''); })}>
            Add
          </Button>
        </div>
        <DialogFooter><Button variant="ghost" onClick={() => onOpenChange(false)}>Close</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
