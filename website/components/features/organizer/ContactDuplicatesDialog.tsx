'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { api } from './contacts-ui';

interface DupContact { contact_id: number; full_name: string; kind: 'COMPANY' | 'CUSTOMER'; customer_name: string | null; company_name: string | null; updated_at: string }
interface DupGroup { match_type: 'name' | 'email' | 'phone'; match_value: string; contacts: DupContact[] }

export function ContactDuplicatesDialog({ tenantId, open, onOpenChange, onMerged, canMerge }: {
  tenantId: number; open: boolean; onOpenChange: (o: boolean) => void; onMerged: (keepId: number) => void; canMerge: boolean;
}) {
  const [groups, setGroups] = useState<DupGroup[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setGroups(null);
    api<DupGroup[]>(`/api/organizer/contacts/duplicates?tenant_id=${tenantId}`).then(setGroups).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  useEffect(() => { if (open) load(); }, [open, load]);

  /** Keep one contact; merge every other contact of the group into it. Customer contacts can only be merged into the same customer's contact. */
  const keep = async (g: DupGroup, keepId: number) => {
    setBusy(true);
    setError(null);
    try {
      for (const c of g.contacts) {
        if (c.contact_id !== keepId) await api('/api/organizer/contacts/duplicates', 'POST', { tenant_id: tenantId, keep_id: keepId, merge_id: c.contact_id });
      }
      onMerged(keepId);
      load();
    } catch (e) {
      setError((e as Error).message);
      load();
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Possible duplicates</DialogTitle>
          <DialogDescription>
            Contacts with the same name, email or phone. Pick the one to keep: the others are merged into it (their details,
            tags and notes are added) and then removed.
          </DialogDescription>
        </DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <div className="max-h-[60vh] space-y-3 overflow-auto">
          {groups === null ? <p className="text-sm text-muted-foreground">Looking…</p>
            : groups.length === 0 ? <p className="text-sm text-muted-foreground">No duplicates found.</p>
            : groups.map((g) => (
              <div key={`${g.match_type}:${g.match_value}`} className="rounded-md border p-3">
                <p className="mb-2 text-xs text-muted-foreground">Same {g.match_type}: <span className="font-medium text-foreground">{g.match_value}</span></p>
                <ul className="space-y-1.5">
                  {g.contacts.map((c) => (
                    <li key={c.contact_id} className="flex items-center gap-2 text-sm">
                      <span className="flex-1">
                        <span className="font-medium">{c.full_name}</span>
                        <span className="text-muted-foreground"> · {c.kind === 'CUSTOMER' ? `customer ${c.customer_name ?? ''}` : c.company_name ?? 'company contact'}</span>
                      </span>
                      {canMerge && <Button size="sm" variant="outline" disabled={busy} onClick={() => keep(g, c.contact_id)}>Keep this one</Button>}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
        </div>
        <DialogFooter><Button variant="ghost" onClick={() => onOpenChange(false)}>Close</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
