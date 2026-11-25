'use client';

import { useCallback, useEffect, useState } from 'react';
import { Copy, Mail, UserPlus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

type Status = 'ACTIVE' | 'INVITED' | 'NOT_INVITED';
interface PortalUser { user_id: number; user_name: string | null; email: string | null; is_active: boolean; is_me: boolean; status: Status; invited_at: string | null; role_ids: number[] }
interface Role { role_id: number; role_name: string }
interface InviteResult { sent: boolean; email: string; link?: string; reason?: string }

const STATUS: Record<Status, string> = { ACTIVE: 'Signed in', INVITED: 'Invited', NOT_INVITED: 'Not invited' };
const TH = 'h-8 whitespace-nowrap bg-muted/50 px-3 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';

async function call<T>(url: string, body?: unknown): Promise<T> {
  const res = await fetch(url, body === undefined ? undefined : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = (await res.json().catch(() => ({}))) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Something went wrong. Try again.');
  return j.data as T;
}

/**
 * Customer portal › Users: a customer administrator looks after the people of their own business who may sign in. Add a
 * person, choose their role, send the invite, deactivate someone who left. They can never change their own access.
 */
export function PortalUsers() {
  const [users, setUsers] = useState<PortalUser[] | null>(null);
  const [roles, setRoles] = useState<Role[]>([]);
  const [sel, setSel] = useState<PortalUser | null>(null);
  const [adding, setAdding] = useState<{ user_name: string; email: string; role_id: number | null } | null>(null);
  const [showInactive, setShowInactive] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; error: boolean; link?: string } | null>(null);

  const load = useCallback(async () => {
    try {
      const d = await call<{ users: PortalUser[]; roles: Role[] }>('/api/portal/users');
      setUsers(d.users); setRoles(d.roles);
      return d.users;
    } catch (e) { setMsg({ text: (e as Error).message, error: true }); setUsers([]); return []; }
  }, []);
  useEffect(() => { void load(); }, [load]);

  const roleName = (ids: number[]) => roles.filter((r) => ids.includes(r.role_id)).map((r) => r.role_name).join(', ') || '—';
  const defaultRole = roles.find((r) => r.role_name === 'Customer Staff')?.role_id ?? roles[0]?.role_id ?? null;

  async function add(e: React.FormEvent) {
    e.preventDefault();
    if (!adding) return;
    setBusy(true); setMsg(null);
    try {
      const id = await call<number>('/api/portal/users', { action: 'create', user_name: adding.user_name, email: adding.email, role_ids: adding.role_id ? [adding.role_id] : [] });
      const list = await load();
      setAdding(null);
      setSel(list.find((u) => u.user_id === id) ?? null);
      setMsg({ text: `${adding.user_name} added. Send the invite when you are ready.`, error: false });
    } catch (err) { setMsg({ text: (err as Error).message, error: true }); } finally { setBusy(false); }
  }

  async function save() {
    if (!sel) return;
    setBusy(true); setMsg(null);
    try {
      await call('/api/portal/users', { action: 'save', user_id: sel.user_id, role_ids: sel.role_ids, is_active: sel.is_active });
      const list = await load();
      setSel(list.find((u) => u.user_id === sel.user_id) ?? null);
      setMsg({ text: 'Saved.', error: false });
    } catch (err) { setMsg({ text: (err as Error).message, error: true }); } finally { setBusy(false); }
  }

  async function invite() {
    if (!sel) return;
    setBusy(true); setMsg(null);
    try {
      const r = await call<InviteResult>('/api/portal/users/invite', { user_id: sel.user_id });
      setMsg(r.sent ? { text: `Invite sent to ${r.email}.`, error: false } : { text: `No email was sent (${r.reason ?? 'email is not set up'}). Give them this link:`, error: false, link: r.link });
      const list = await load();
      setSel(list.find((u) => u.user_id === sel.user_id) ?? null);
    } catch (err) { setMsg({ text: (err as Error).message, error: true }); } finally { setBusy(false); }
  }

  const shown = (users ?? []).filter((u) => showInactive || u.is_active || u.user_id === sel?.user_id);
  const hidden = (users ?? []).filter((u) => !u.is_active).length;
  const dirty = sel && users ? (() => { const was = users.find((u) => u.user_id === sel.user_id); return !!was && (was.is_active !== sel.is_active || was.role_ids.join() !== sel.role_ids.join()); })() : false;

  return (
    <div className="space-y-3 py-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <h1 className="text-lg font-semibold tracking-tight">Users</h1>
        <p className="text-sm text-muted-foreground">People in your business who may sign in. Add them, choose their role, then send the invite.</p>
        <Button size="sm" className="ml-auto" onClick={() => { setSel(null); setMsg(null); setAdding({ user_name: '', email: '', role_id: defaultRole }); }}>
          <UserPlus className="mr-1.5 h-4 w-4" /> Add user
        </Button>
      </div>

      {msg && (
        <p role="status" className={`rounded-md border px-3 py-2 text-sm ${msg.error ? 'border-destructive/30 bg-destructive/10 text-destructive' : 'border-border bg-card'}`}>
          {msg.text}{msg.link && <> <a href={msg.link} className="break-all text-primary underline">{msg.link}</a>
            <button type="button" className="ml-1 inline-flex align-middle text-muted-foreground hover:text-foreground" aria-label="Copy link"
              onClick={() => { void navigator.clipboard.writeText(msg.link!).catch(() => undefined); }}><Copy className="h-4 w-4" /></button></>}
        </p>
      )}

      <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section className="min-w-0 overflow-hidden rounded-lg border border-border bg-card shadow-sm">
          <div className="flex min-h-[40px] items-center justify-between gap-3 border-b border-border px-4 py-1.5">
            <h2 className="text-sm font-semibold">Your users</h2>
            <label className="flex items-center gap-2 text-xs text-muted-foreground">
              <Checkbox checked={showInactive} onCheckedChange={(v) => setShowInactive(v === true)} />
              Show inactive{hidden && !showInactive ? ` (${hidden} hidden)` : ''}
            </label>
          </div>
          {users === null ? (
            <div className="space-y-2 px-4 py-3">{Array.from({ length: 4 }, (_, i) => <div key={i} className="h-5 animate-pulse rounded bg-muted/70" />)}</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead><tr><th className={TH}>Name</th><th className={TH}>Role</th><th className={TH}>Sign-in</th><th className={TH}>Status</th></tr></thead>
                <tbody>
                  {shown.map((u) => (
                    <tr key={u.user_id} onClick={() => { setAdding(null); setMsg(null); setSel(u); }}
                      className={`cursor-pointer border-t border-border hover:bg-muted/40 ${sel?.user_id === u.user_id ? 'bg-accent text-accent-foreground' : ''} ${u.is_active ? '' : 'text-muted-foreground'}`}>
                      <td className="px-3 py-1.5"><div className="font-medium">{u.user_name ?? '—'}{u.is_me && <span className="ml-1.5 text-xs font-normal text-muted-foreground">(you)</span>}</div><div className="text-xs text-muted-foreground">{u.email}</div></td>
                      <td className="px-3 py-1.5">{roleName(u.role_ids)}</td>
                      <td className="px-3 py-1.5">{STATUS[u.status]}</td>
                      <td className="px-3 py-1.5">{u.is_active ? 'Active' : 'Inactive'}</td>
                    </tr>
                  ))}
                  {shown.length === 0 && <tr><td colSpan={4} className="px-3 py-3 text-sm text-muted-foreground">No users yet. Add the first one.</td></tr>}
                </tbody>
              </table>
            </div>
          )}
        </section>

        {(adding || sel) && (
          <section className="h-fit space-y-3 rounded-lg border border-border bg-card p-4 shadow-sm">
            {adding ? (
              <form onSubmit={add} className="space-y-3">
                <h2 className="text-sm font-semibold">Add a user</h2>
                <div className="space-y-1.5"><Label htmlFor="pu-name">Name *</Label><Input id="pu-name" value={adding.user_name} onChange={(e) => setAdding({ ...adding, user_name: e.target.value })} required autoFocus /></div>
                <div className="space-y-1.5"><Label htmlFor="pu-email">Email *</Label><Input id="pu-email" type="email" value={adding.email} onChange={(e) => setAdding({ ...adding, email: e.target.value })} required /></div>
                <fieldset className="space-y-1">
                  <legend className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Role</legend>
                  {roles.map((r) => (
                    <label key={r.role_id} className="flex items-center gap-2 text-sm">
                      <input type="radio" name="pu-role" checked={adding.role_id === r.role_id} onChange={() => setAdding({ ...adding, role_id: r.role_id })} className="h-4 w-4 accent-[hsl(var(--primary))]" />
                      {r.role_name}
                    </label>
                  ))}
                </fieldset>
                <div className="flex gap-2">
                  <Button type="button" size="sm" variant="outline" onClick={() => setAdding(null)}>Cancel</Button>
                  <Button type="submit" size="sm" disabled={busy}>{busy ? 'Adding…' : 'Add user'}</Button>
                </div>
              </form>
            ) : sel && (
              <div className="space-y-3">
                <div>
                  <h2 className="text-sm font-semibold">{sel.user_name}</h2>
                  <p className="break-all text-xs text-muted-foreground">{sel.email} · {STATUS[sel.status]}</p>
                </div>
                {sel.is_me ? (
                  <p className="rounded-md bg-muted px-3 py-2 text-sm text-muted-foreground">This is you. Another administrator of your business can change your access.</p>
                ) : (
                  <>
                    <Button size="sm" onClick={invite} disabled={busy || !sel.is_active || dirty}>
                      <Mail className="mr-1.5 h-4 w-4" />{sel.status === 'ACTIVE' ? 'Send sign-in email' : sel.status === 'INVITED' ? 'Send the invite again' : 'Send invite'}
                    </Button>
                    <label className="flex items-center gap-2 text-sm"><Checkbox checked={sel.is_active} onCheckedChange={(v) => setSel({ ...sel, is_active: v === true })} /> Active</label>
                    <fieldset className="space-y-1">
                      <legend className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Role</legend>
                      {roles.map((r) => (
                        <label key={r.role_id} className="flex items-center gap-2 text-sm">
                          <input type="radio" name="pu-sel-role" checked={sel.role_ids.includes(r.role_id)} onChange={() => setSel({ ...sel, role_ids: [r.role_id] })} className="h-4 w-4 accent-[hsl(var(--primary))]" />
                          {r.role_name}
                        </label>
                      ))}
                    </fieldset>
                    <div className="flex gap-2">
                      <Button size="sm" variant="outline" onClick={() => setSel(null)}>Cancel</Button>
                      <Button size="sm" onClick={save} disabled={busy || !dirty}>{busy ? 'Saving…' : 'Save'}</Button>
                    </div>
                    <p className="text-xs text-muted-foreground">Someone who left? Untick Active and save: they can no longer sign in for your business.</p>
                  </>
                )}
              </div>
            )}
          </section>
        )}
      </div>
    </div>
  );
}
