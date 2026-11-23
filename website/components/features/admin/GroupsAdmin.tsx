'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminDelete, adminPost, PageHead, useBanner } from './adminShared';

interface Group { group_id: number; group_name: string; is_all_customers: boolean; is_active: boolean; customer_ids: number[]; effective_count: number; user_count: number }
interface Option { customer_id: number; customer_number: string | null; customer_name: string; customer_type: string }

export function GroupsAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [groups, setGroups] = useState<Group[]>([]);
  const [options, setOptions] = useState<Option[]>([]);
  const [draft, setDraft] = useState<{ group_id?: number; group_name: string; is_active: boolean; customer_ids: number[]; is_all_customers?: boolean } | null>(null);
  const [filter, setFilter] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [g, o] = await Promise.all([
        adminCall<Group[]>(`/api/admin/groups?tenant_id=${tenantId}`),
        adminCall<Option[]>(`/api/admin/groups?tenant_id=${tenantId}&options=1`),
      ]);
      setGroups(g); setOptions(o);
    } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);
  useEffect(() => { void load(); }, [load]);

  const shown = useMemo(() => {
    const f = filter.trim().toLowerCase();
    const list = f ? options.filter((o) => `${o.customer_number ?? ''} ${o.customer_name}`.toLowerCase().includes(f)) : options;
    return list.slice(0, 300);
  }, [options, filter]);

  async function save() {
    if (!draft) return;
    setBusy(true);
    try {
      await adminPost('/api/admin/groups', { tenant_id: tenantId, group: draft });
      notify(`${draft.group_name} saved.`, 'success');
      setDraft(null); await load();
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }
  async function remove() {
    if (!draft?.group_id) return;
    setBusy(true);
    try {
      await adminDelete(`/api/admin/groups?tenant_id=${tenantId}&group_id=${draft.group_id}`);
      notify(`${draft.group_name} deleted.`, 'success');
      setDraft(null); await load();
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  const locked = !!draft?.is_all_customers;
  return (
    <div className="space-y-4 p-2 sm:p-3">
      <PageHead title="Customer Groups">
        Groups decide which customers a staff user can see, for example White Glove Service or High Risk. A customer in a group brings its departments and
        sites with it. Everyone who should see every customer gets the built-in All Customers group; staff with no group see no customers.
      </PageHead>
      {banner}
      <div className="grid gap-6 lg:grid-cols-[18rem_1fr]">
        <div className="space-y-2">
          <Button size="sm" onClick={() => setDraft({ group_name: '', is_active: true, customer_ids: [] })}>New group</Button>
          {groups.map((g) => (
            <button key={g.group_id} onClick={() => setDraft({ ...g })}
              className={`flex w-full items-center justify-between rounded-md border px-3 py-2 text-left text-sm hover:bg-muted ${draft?.group_id === g.group_id ? 'border-primary bg-muted' : ''}`}>
              <span>{g.group_name}{!g.is_active ? ' · inactive' : ''}</span>
              <span className="text-xs text-muted-foreground">{g.is_all_customers ? 'everyone' : `${g.effective_count} cust.`} · {g.user_count} users</span>
            </button>
          ))}
        </div>
        {draft ? (
          <div className="min-w-0 space-y-3">
            <div className="flex flex-wrap items-end gap-3">
              <div className="w-72 max-w-full"><Label className="text-xs">Group name</Label>
                <Input aria-label="Group name" value={draft.group_name} disabled={locked} onChange={(e) => setDraft({ ...draft, group_name: e.target.value })} /></div>
              <label className="flex items-center gap-2 text-sm"><Checkbox checked={draft.is_active} disabled={locked} onCheckedChange={(v) => setDraft({ ...draft, is_active: v === true })} /> Active</label>
              {!locked && <Button onClick={save} disabled={busy || !draft.group_name.trim()}>Save group</Button>}
              {!locked && draft.group_id && <Button variant="outline" onClick={remove} disabled={busy}>Delete</Button>}
            </div>
            {locked ? <p className="text-sm text-muted-foreground">All Customers always includes every customer and cannot be edited.</p> : (
              <>
                <div className="flex items-center gap-3">
                  <Input className="max-w-xs" placeholder="Filter customers" value={filter} onChange={(e) => setFilter(e.target.value)} />
                  <span className="text-sm text-muted-foreground">{draft.customer_ids.length} selected</span>
                </div>
                <div className="max-h-[28rem] overflow-y-auto rounded-md border">
                  {shown.map((o) => (
                    <label key={o.customer_id} className="flex items-center gap-2 border-b px-3 py-1.5 text-sm last:border-0">
                      <Checkbox checked={draft.customer_ids.includes(o.customer_id)}
                        onCheckedChange={(v) => setDraft({ ...draft, customer_ids: v === true ? [...draft.customer_ids, o.customer_id] : draft.customer_ids.filter((x) => x !== o.customer_id) })} />
                      <span className="text-muted-foreground">{o.customer_number}</span> {o.customer_name}
                    </label>
                  ))}
                  {shown.length === 0 && <p className="p-3 text-sm text-muted-foreground">No customers match.</p>}
                </div>
              </>
            )}
          </div>
        ) : <p className="text-sm text-muted-foreground">Choose a group, or create one.</p>}
      </div>
    </div>
  );
}
