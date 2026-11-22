'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { adminCall, adminPost, PageHead, useBanner } from './adminShared';

interface UserRow { user_id: number; user_name: string | null; email: string | null; user_type: string; is_active: boolean; role_ids: number[]; group_ids: number[]; customers: string[] }
interface Role { role_id: number; role_name: string; role_audience: string; is_active: boolean }
interface Group { group_id: number; group_name: string; is_all_customers: boolean; is_active: boolean }

export function UsersAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [users, setUsers] = useState<UserRow[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [sel, setSel] = useState<UserRow | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [u, r, g] = await Promise.all([
        adminCall<UserRow[]>(`/api/admin/users?tenant_id=${tenantId}`),
        adminCall<Role[]>(`/api/admin/roles?tenant_id=${tenantId}`),
        adminCall<Group[]>(`/api/admin/groups?tenant_id=${tenantId}`),
      ]);
      setUsers(u); setRoles(r); setGroups(g);
    } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);
  useEffect(() => { void load(); }, [load]);

  const audience = sel?.user_type === 'CUSTOMER_USER' ? 'CUSTOMER' : 'TENANT';
  const flip = (list: number[], id: number, on: boolean) => (on ? [...list, id] : list.filter((x) => x !== id));

  async function save() {
    if (!sel) return;
    setBusy(true);
    try {
      await adminPost('/api/admin/users', { tenant_id: tenantId, user_id: sel.user_id, role_ids: sel.role_ids, group_ids: sel.group_ids, is_active: sel.is_active });
      notify(`${sel.user_name ?? sel.email} saved.`, 'success');
      await load(); setSel(null);
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <PageHead title="Users">
        Give each person their roles and, for your own staff, the customer groups they can see. A user with no role can sign in but sees nothing;
        a staff user with no group sees no customers. New users are not created here yet.
      </PageHead>
      {banner}
      <div className="grid gap-6 lg:grid-cols-[1fr_22rem]">
        <div className="overflow-x-auto rounded-md border">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs"><tr><th className="px-3 py-2">User</th><th className="px-3 py-2">Type</th><th className="px-3 py-2">Roles</th><th className="px-3 py-2">Status</th></tr></thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.user_id} onClick={() => setSel(u)} className={`cursor-pointer border-t hover:bg-muted ${sel?.user_id === u.user_id ? 'bg-muted' : ''}`}>
                  <td className="px-3 py-2"><div className="font-medium">{u.user_name ?? '—'}</div><div className="text-xs text-muted-foreground">{u.email}{u.customers.length ? ` · ${u.customers.join(', ')}` : ''}</div></td>
                  <td className="px-3 py-2">{u.user_type === 'CUSTOMER_USER' ? 'Customer' : 'Staff'}</td>
                  <td className="px-3 py-2">{roles.filter((r) => u.role_ids.includes(r.role_id)).map((r) => r.role_name).join(', ') || <span className="text-muted-foreground">none</span>}</td>
                  <td className="px-3 py-2">{u.is_active ? 'Active' : 'Inactive'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {sel ? (
          <div className="space-y-4 rounded-md border p-4">
            <div><div className="font-medium">{sel.user_name ?? sel.email}</div><div className="text-xs text-muted-foreground">{audience === 'TENANT' ? 'Staff' : 'Customer'} user</div></div>
            <label className="flex items-center gap-2 text-sm"><Checkbox checked={sel.is_active} onCheckedChange={(v) => setSel({ ...sel, is_active: v === true })} /> Active in this tenancy</label>
            <div>
              <div className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Roles</div>
              {roles.filter((r) => r.role_audience === audience && r.is_active).map((r) => (
                <label key={r.role_id} className="flex items-center gap-2 py-0.5 text-sm">
                  <Checkbox checked={sel.role_ids.includes(r.role_id)} onCheckedChange={(v) => setSel({ ...sel, role_ids: flip(sel.role_ids, r.role_id, v === true) })} /> {r.role_name}
                </label>
              ))}
            </div>
            {audience === 'TENANT' && (
              <div>
                <div className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Customer groups</div>
                {groups.filter((g) => g.is_active).map((g) => (
                  <label key={g.group_id} className="flex items-center gap-2 py-0.5 text-sm">
                    <Checkbox checked={sel.group_ids.includes(g.group_id)} onCheckedChange={(v) => setSel({ ...sel, group_ids: flip(sel.group_ids, g.group_id, v === true) })} /> {g.group_name}
                  </label>
                ))}
              </div>
            )}
            <div className="flex gap-2"><Button onClick={save} disabled={busy}>Save</Button><Button variant="outline" onClick={() => setSel(null)}>Cancel</Button></div>
          </div>
        ) : <p className="text-sm text-muted-foreground">Choose a user to edit their access.</p>}
      </div>
    </div>
  );
}
