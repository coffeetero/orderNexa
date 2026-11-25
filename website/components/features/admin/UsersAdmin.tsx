'use client';

import { useCallback, useEffect, useState } from 'react';
import { Copy, Mail, UserPlus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { AccountPicker } from '@/components/features/orders/AccountPicker';
import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';
import { adminCall, adminPost, PageHead, useBanner } from './adminShared';
import { EmailSenderPanel } from './EmailSenderPanel';

type InviteStatus = 'ACTIVE' | 'INVITED' | 'NOT_INVITED';
interface UserRow { user_id: number; user_name: string | null; email: string | null; user_type: string; is_active: boolean; status: InviteStatus; invited_at: string | null; ended?: boolean; last_active_at: string | null; last_place: string | null; last_ip: string | null; is_user_admin: boolean; role_ids: number[]; group_ids: number[]; customer_id: number | null; customers: string[] }
interface Role { role_id: number; role_name: string; role_audience: string; is_active: boolean }
interface Group { group_id: number; group_name: string; is_all_customers: boolean; is_active: boolean }
interface NewUser { email: string; user_name: string; account: CustomerOption | null; role_ids: number[]; group_ids: number[] }
interface InviteResult { sent: boolean; email: string; link?: string; reason?: string }

const STATUS_LABEL: Record<InviteStatus, string> = { ACTIVE: 'Signed in', INVITED: 'Invited', NOT_INVITED: 'Not invited' };
const shortDate = (v: string | null) => (v ? new Date(v).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '');

export function UsersAdmin({ tenantId, audience: pageAudience }: { tenantId: number; audience: 'TENANT' | 'CUSTOMER' }) {
  const { notify, banner } = useBanner();
  const [users, setUsers] = useState<UserRow[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [sel, setSel] = useState<UserRow | null>(null);
  const [adding, setAdding] = useState<NewUser | null>(null);
  const [customers, setCustomers] = useState<CustomerOption[] | null>(null);
  const [invite, setInvite] = useState<InviteResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [showInactive, setShowInactive] = useState(false);
  // the email being added belongs to a former staff member: offer to release it (their history stays on their old record)
  const [release, setRelease] = useState<{ userId: number; message: string } | null>(null);

  const load = useCallback(async () => {
    try {
      const [u, r, g] = await Promise.all([
        adminCall<UserRow[]>(`/api/admin/users?tenant_id=${tenantId}`),
        adminCall<Role[]>(`/api/admin/roles?tenant_id=${tenantId}`),
        adminCall<Group[]>(`/api/admin/groups?tenant_id=${tenantId}`),
      ]);
      const mine = u.filter((x) => (x.user_type === 'CUSTOMER_USER') === (pageAudience === 'CUSTOMER'));
      setUsers(mine); setRoles(r); setGroups(g);
      return mine;
    } catch (e) { notify((e as Error).message, 'error'); return []; }
  }, [tenantId, pageAudience, notify]);
  useEffect(() => { void load(); }, [load]);

  // the customer accounts list is only needed to add or edit a customer user
  const editing = adding !== null || sel !== null;
  useEffect(() => {
    if (pageAudience !== 'CUSTOMER' || !editing || customers !== null) return;
    adminCall<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then(setCustomers).catch((e: Error) => { setCustomers([]); notify(e.message, 'error'); });
  }, [pageAudience, editing, customers, tenantId, notify]);

  const audience = pageAudience;
  const flip = (list: number[], id: number, on: boolean) => (on ? [...list, id] : list.filter((x) => x !== id));
  const pick = (u: UserRow) => { setSel(u); setAdding(null); setInvite(null); };

  async function save() {
    if (!sel) return;
    setBusy(true);
    try {
      const was = users.find((u) => u.user_id === sel.user_id);
      const same = (a: number[], b: number[]) => a.length === b.length && a.every((x) => b.includes(x));
      // two saves, each only when its part changed: who the person is, and what they may do (which nobody may change for themselves)
      if (!was || was.user_name !== sel.user_name || was.email !== sel.email || was.customer_id !== sel.customer_id) {
        await adminPost('/api/admin/users/update', { tenant_id: tenantId, user_id: sel.user_id, user_name: sel.user_name ?? '', email: sel.email ?? '', customer_id: sel.customer_id });
      }
      if (!was || was.is_active !== sel.is_active || !same(was.role_ids, sel.role_ids) || !same(was.group_ids, sel.group_ids)) {
        await adminPost('/api/admin/users', { tenant_id: tenantId, user_id: sel.user_id, role_ids: sel.role_ids, group_ids: sel.group_ids, is_active: sel.is_active });
      }
      notify(`${sel.user_name ?? sel.email} saved.`, 'success');
      await load(); setSel(null);
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  async function create() {
    if (!adding) return;
    setBusy(true); setRelease(null);
    try {
      const res = await fetch('/api/admin/users/create', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, email: adding.email, user_name: adding.user_name,
          user_type: pageAudience === 'CUSTOMER' ? 'CUSTOMER_USER' : 'TENANCY_USER',
          customer_id: adding.account?.customer_id ?? null, role_ids: adding.role_ids, group_ids: adding.group_ids,
        }),
      });
      const j = (await res.json().catch(() => ({}))) as { data?: number; error?: string; release_user_id?: number };
      if (!res.ok || j.data === undefined) {
        if (j.release_user_id) { setRelease({ userId: j.release_user_id, message: j.error ?? '' }); return; }
        throw new Error(j.error ?? 'The user could not be added');
      }
      const userId = j.data;
      notify(`${adding.user_name} added. Send the invite when you are ready.`, 'success');
      const list = await load();
      setAdding(null);
      setSel(list.find((u) => u.user_id === userId) ?? null);
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  async function releaseAndAdd() {
    if (!release) return;
    setBusy(true);
    try {
      await adminPost('/api/admin/users/release', { tenant_id: tenantId, user_id: release.userId });
      setRelease(null);
    } catch (e) { notify((e as Error).message, 'error'); setBusy(false); return; }
    setBusy(false);
    await create();
  }

  async function sendInvite() {
    if (!sel) return;
    setBusy(true); setInvite(null);
    try {
      const r = await adminPost<InviteResult>('/api/admin/users/invite', { tenant_id: tenantId, user_id: sel.user_id });
      setInvite(r);
      notify(r.sent ? `Invite sent to ${r.email}.` : `Invite created for ${r.email}, but no email was sent: ${r.reason ?? ''}`, r.sent ? 'success' : 'error');
      const list = await load();
      setSel(list.find((u) => u.user_id === sel.user_id) ?? null);
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  async function copyLink(link: string) {
    try { await navigator.clipboard.writeText(link); notify('Link copied.', 'success'); } catch { notify('Copy failed — select the link and copy it.', 'error'); }
  }

  const roleList = (chosen: number[], set: (ids: number[]) => void) => (
    <div>
      <div className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Roles</div>
      {roles.filter((r) => r.role_audience === audience && r.is_active).map((r) => (
        <label key={r.role_id} className="flex items-center gap-2 py-0.5 text-sm">
          <Checkbox checked={chosen.includes(r.role_id)} onCheckedChange={(v) => set(flip(chosen, r.role_id, v === true))} /> {r.role_name}
        </label>
      ))}
    </div>
  );
  const groupList = (chosen: number[], set: (ids: number[]) => void) => audience === 'TENANT' && (
    <div>
      <div className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">Customer groups</div>
      {groups.filter((g) => g.is_active).map((g) => (
        <label key={g.group_id} className="flex items-center gap-2 py-0.5 text-sm">
          <Checkbox checked={chosen.includes(g.group_id)} onCheckedChange={(v) => set(flip(chosen, g.group_id, v === true))} /> {g.group_name}
        </label>
      ))}
    </div>
  );

  return (
    <div className="space-y-4 p-2 sm:p-3">
      <PageHead title={pageAudience === 'CUSTOMER' ? 'Customer Users' : 'Company Users'}>
        Give each person their roles and, for your own staff, the customer groups they can see. A user with no role can sign in but sees nothing;
        a staff user with no group sees no customers. Add a user, then send them an invite to choose their password.
      </PageHead>
      {banner}
      {pageAudience === 'TENANT' && users.filter((u) => u.is_user_admin).length === 1 && (
        <p className="rounded-md border border-amber-500/40 px-3 py-2 text-sm text-amber-700 dark:text-amber-400">
          Only {users.find((u) => u.is_user_admin)?.user_name} can manage users. Give a second person that access, so nobody gets locked out.
        </p>
      )}
      {pageAudience === 'CUSTOMER' && <EmailSenderPanel tenantId={tenantId} notify={notify} />}
      {release && adding && (
        <div className="space-y-2 rounded-md border border-warning/40 bg-warning-soft px-3 py-2 text-sm">
          <p>{release.message}</p>
          <p className="text-xs text-muted-foreground">Releasing ends their old account for good: it stays in history under their old user number, and their old sign-in stops working. The new account gets its own user number and a new password.</p>
          <div className="flex gap-2">
            <Button size="sm" variant="ghost" onClick={() => setRelease(null)} disabled={busy}>Cancel</Button>
            <Button size="sm" onClick={releaseAndAdd} disabled={busy}>{busy ? 'Releasing…' : 'Release email and add'}</Button>
          </div>
        </div>
      )}
      <div className="flex flex-wrap items-center justify-end gap-x-4 gap-y-2">
        <label className="mr-auto flex items-center gap-2 text-sm text-muted-foreground">
          <Checkbox checked={showInactive} onCheckedChange={(v) => setShowInactive(v === true)} />
          Show inactive users{users.some((u) => !u.is_active) && !showInactive ? ` (${users.filter((u) => !u.is_active).length} hidden)` : ''}
        </label>
        <Button size="sm" onClick={() => { setSel(null); setInvite(null); setAdding({ email: '', user_name: '', account: null, role_ids: [], group_ids: [] }); }}>
          <UserPlus className="mr-1.5 h-4 w-4" /> Add user
        </Button>
      </div>
      <div className="grid gap-6 lg:grid-cols-[1fr_22rem]">
        <div className="overflow-x-auto rounded-md border">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs"><tr><th className="px-3 py-2">User</th><th className="px-3 py-2">Type</th><th className="px-3 py-2">Roles</th><th className="px-3 py-2">Sign-in</th>{pageAudience === 'TENANT' && <th className="px-3 py-2">Last activity</th>}<th className="px-3 py-2">Status</th></tr></thead>
            <tbody>
              {users.filter((u) => showInactive || u.is_active || u.user_id === sel?.user_id).map((u) => (
                <tr key={u.user_id} onClick={() => pick(u)} className={`cursor-pointer border-t hover:bg-muted ${sel?.user_id === u.user_id ? 'bg-muted' : ''} ${u.is_active ? '' : 'text-muted-foreground'}`}>
                  <td className="px-3 py-2"><div className="font-medium">{u.user_name ?? '—'}</div><div className="text-xs text-muted-foreground">{u.email}{u.customers.length ? ` · ${u.customers.join(', ')}` : ''}</div></td>
                  <td className="px-3 py-2">{u.user_type === 'CUSTOMER_USER' ? 'Customer' : 'Staff'}</td>
                  <td className="px-3 py-2">{roles.filter((r) => u.role_ids.includes(r.role_id)).map((r) => r.role_name).join(', ') || <span className="text-muted-foreground">none</span>}</td>
                  <td className="px-3 py-2"><span className={u.status === 'ACTIVE' ? '' : 'text-amber-700 dark:text-amber-400'}>{STATUS_LABEL[u.status]}</span>{u.status === 'INVITED' && <div className="text-xs text-muted-foreground">{shortDate(u.invited_at)}</div>}</td>
                  {/* a customer's users' activity belongs to that customer (second-level support sees name, email, role, status) */}
                  {pageAudience === 'TENANT' && <td className="px-3 py-2">
                    {u.last_active_at ? (
                      <><div className="whitespace-nowrap">{new Date(u.last_active_at).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}</div>
                        {(u.last_place || u.last_ip) && <div className="text-xs text-muted-foreground" title={u.last_ip ? `IP ${u.last_ip}` : undefined}>{u.last_place ?? `IP ${u.last_ip}`}</div>}</>
                    ) : <span className="text-muted-foreground">never</span>}
                  </td>}
                  <td className="px-3 py-2">{u.ended ? 'Ended' : u.is_active ? 'Active' : 'Inactive'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {adding ? (
          <div className="space-y-4 rounded-md border p-4">
            <div className="font-medium">New {audience === 'TENANT' ? 'staff' : 'customer'} user</div>
            <div className="space-y-1.5"><Label htmlFor="nu-email">Email</Label><Input id="nu-email" type="email" value={adding.email} onChange={(e) => setAdding({ ...adding, email: e.target.value })} /></div>
            <div className="space-y-1.5"><Label htmlFor="nu-name">Name</Label><Input id="nu-name" value={adding.user_name} onChange={(e) => setAdding({ ...adding, user_name: e.target.value })} /></div>
            {audience === 'CUSTOMER' && (
              <div className="space-y-1.5"><Label htmlFor="nu-acct">Customer account</Label>
                <AccountPicker customers={customers} value={adding.account} onChange={(a) => setAdding({ ...adding, account: a })} id="nu-acct" />
              </div>
            )}
            {roleList(adding.role_ids, (ids) => setAdding({ ...adding, role_ids: ids }))}
            {groupList(adding.group_ids, (ids) => setAdding({ ...adding, group_ids: ids }))}
            <div className="flex gap-2"><Button variant="outline" onClick={() => setAdding(null)}>Cancel</Button><Button onClick={create} disabled={busy}>Add user</Button></div>
          </div>
        ) : sel ? (
          <div className="space-y-4 rounded-md border p-4">
            <div className="font-medium">{audience === 'TENANT' ? 'Staff' : 'Customer'} user</div>
            <div className="space-y-1.5"><Label htmlFor="eu-name">Name</Label><Input id="eu-name" value={sel.user_name ?? ''} onChange={(e) => setSel({ ...sel, user_name: e.target.value })} /></div>
            <div className="space-y-1.5"><Label htmlFor="eu-email">Email</Label>
              <Input id="eu-email" type="email" value={sel.email ?? ''} disabled={sel.status === 'ACTIVE'} onChange={(e) => setSel({ ...sel, email: e.target.value })} />
              <p className="text-xs text-muted-foreground">{sel.status === 'ACTIVE' ? 'The email is fixed once the person has signed in.' : sel.status === 'INVITED' ? 'Changing the email cancels the invite already sent; send a new one after saving.' : ''}</p>
            </div>
            {audience === 'CUSTOMER' && (
              <div className="space-y-1.5"><Label htmlFor="eu-acct">Customer account</Label>
                <AccountPicker customers={customers} value={customers?.find((c) => c.customer_id === sel.customer_id) ?? null} onChange={(a) => setSel({ ...sel, customer_id: a?.customer_id ?? null })} id="eu-acct" />
              </div>
            )}
            <div className="space-y-2 rounded-md bg-muted/40 p-3 text-sm">
              <div>{STATUS_LABEL[sel.status]}{sel.status === 'INVITED' && ` on ${shortDate(sel.invited_at)}`}</div>
              <Button size="sm" onClick={sendInvite} disabled={busy || !sel.is_active || sel.email !== users.find((u) => u.user_id === sel.user_id)?.email}>
                <Mail className="mr-1.5 h-4 w-4" /> {sel.status === 'NOT_INVITED' ? 'Send invite' : sel.status === 'INVITED' ? 'Resend invite' : 'Send sign-in email'}
              </Button>
              {invite?.link && (
                <div className="space-y-1">
                  <div className="text-xs text-muted-foreground">Email is not set up yet. Pass this one-time link on yourself:</div>
                  <div className="flex items-center gap-1">
                    <Input readOnly value={invite.link} onFocus={(e) => e.currentTarget.select()} className="h-8 text-xs" />
                    <Button size="sm" variant="ghost" onClick={() => copyLink(invite.link!)} aria-label="Copy link"><Copy className="h-4 w-4" /></Button>
                  </div>
                </div>
              )}
            </div>
            <label className="flex items-center gap-2 text-sm"><Checkbox checked={sel.is_active} onCheckedChange={(v) => setSel({ ...sel, is_active: v === true })} /> Active in this company</label>
            {roleList(sel.role_ids, (ids) => setSel({ ...sel, role_ids: ids }))}
            {groupList(sel.group_ids, (ids) => setSel({ ...sel, group_ids: ids }))}
            <div className="flex gap-2"><Button variant="outline" onClick={() => setSel(null)}>Cancel</Button><Button onClick={save} disabled={busy}>Save</Button></div>
          </div>
        ) : <p className="text-sm text-muted-foreground">Choose a user to edit them, or add a new one.</p>}
      </div>
    </div>
  );
}
