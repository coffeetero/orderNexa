'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminDelete, adminPost, PageHead, useBanner } from './adminShared';

interface Role { role_id: number; role_name: string; role_audience: 'TENANT' | 'CUSTOMER'; owner_customer_id: number | null; is_system: boolean; is_active: boolean; user_count: number; area_count: number }
interface Area { area_key: string; module: string; area_name: string; can_read: boolean; can_write: boolean; can_approve: boolean; can_void: boolean; can_delete: boolean }
type Flag = 'can_read' | 'can_write' | 'can_approve' | 'can_void' | 'can_delete';
const FLAGS: { key: Flag; label: string }[] = [
  { key: 'can_read', label: 'Read' }, { key: 'can_write', label: 'Write' }, { key: 'can_approve', label: 'Approve' },
  { key: 'can_void', label: 'Void' }, { key: 'can_delete', label: 'Delete' },
];

export function RolesAdmin({ tenantId, audience }: { tenantId: number; audience: 'TENANT' | 'CUSTOMER' }) {
  const { notify, banner } = useBanner();
  const [roles, setRoles] = useState<Role[]>([]);
  const [selected, setSelected] = useState<Role | null>(null);
  const [draft, setDraft] = useState<{ role_id?: number; role_name: string; role_audience: 'TENANT' | 'CUSTOMER'; is_active: boolean } | null>(null);
  const [areas, setAreas] = useState<Area[]>([]);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try { setRoles(await adminCall<Role[]>(`/api/admin/roles?tenant_id=${tenantId}`)); } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);
  useEffect(() => { void load(); }, [load]);

  async function open(role: Role | null, audience: 'TENANT' | 'CUSTOMER' = 'TENANT') {
    try {
      const q = role ? `role_id=${role.role_id}` : `audience=${audience}`;
      setAreas(await adminCall<Area[]>(`/api/admin/roles?tenant_id=${tenantId}&access=1&${q}`));
      setSelected(role);
      setDraft(role ? { role_id: role.role_id, role_name: role.role_name, role_audience: role.role_audience, is_active: role.is_active }
                    : { role_name: '', role_audience: audience, is_active: true });
    } catch (e) { notify((e as Error).message, 'error'); }
  }

  const readOnly = !!selected?.is_system;
  const toggle = (key: string, flag: Flag, on: boolean) =>
    setAreas((rows) => rows.map((a) => {
      if (a.area_key !== key) return a;
      const next = { ...a, [flag]: on };
      if (flag === 'can_read' && !on) { next.can_write = next.can_approve = next.can_void = next.can_delete = false; }
      if (flag !== 'can_read' && on) next.can_read = true;
      return next;
    }));
  const setRow = (key: string, on: boolean) =>
    setAreas((rows) => rows.map((a) => a.area_key === key ? { ...a, can_read: on, can_write: on, can_approve: on, can_void: on, can_delete: on } : a));

  async function save() {
    if (!draft) return;
    setBusy(true);
    try {
      const id = await adminPost<number>('/api/admin/roles', { tenant_id: tenantId, role: { ...draft, access: areas } });
      notify(`${draft.role_name} saved.`, 'success');
      await load();
      const fresh = (await adminCall<Role[]>(`/api/admin/roles?tenant_id=${tenantId}`)).find((r) => r.role_id === id) ?? null;
      if (fresh) await open(fresh);
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }
  async function remove() {
    if (!selected) return;
    setBusy(true);
    try {
      await adminDelete(`/api/admin/roles?tenant_id=${tenantId}&role_id=${selected.role_id}`);
      notify(`${selected.role_name} deleted.`, 'success');
      setSelected(null); setDraft(null); await load();
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  const byModule = useMemo(() => {
    const m = new Map<string, Area[]>();
    areas.forEach((a) => m.set(a.module, [...(m.get(a.module) ?? []), a]));
    return Array.from(m.entries());
  }, [areas]);

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <PageHead title={audience === 'TENANT' ? 'Company Roles' : 'Customer Roles'}>
        A role is a named set of rights. For each area choose what the role may do; write, approve, void and delete all include read.
        Users get one or more roles.{' '}
        {audience === 'TENANT'
          ? 'These roles are for your own staff and are never visible to customers.'
          : 'These roles are for people at your customers (the portal). Customers can create roles of their own for their staff; they appear here so you can help them.'}
      </PageHead>
      {banner}
      <div className="grid gap-6 lg:grid-cols-[18rem_1fr]">
        <div className="space-y-2">
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={() => open(null, audience)}>{audience === 'TENANT' ? 'New company role' : 'New customer role'}</Button>
          </div>
          {[audience].map((aud) => (
            <div key={aud}>
              {roles.filter((r) => r.role_audience === aud).map((r) => (
                <button key={r.role_id} onClick={() => open(r)}
                  className={`mt-1 flex w-full items-center justify-between rounded-md border px-3 py-2 text-left text-sm hover:bg-muted ${selected?.role_id === r.role_id ? 'border-primary bg-muted' : ''}`}>
                  <span>{r.role_name}{r.is_system ? ' · system' : ''}{r.owner_customer_id ? ' · made by a customer' : ''}{!r.is_active ? ' · inactive' : ''}</span>
                  <span className="text-xs text-muted-foreground">{r.user_count} users</span>
                </button>
              ))}
            </div>
          ))}
        </div>

        {draft ? (
          <div className="min-w-0 space-y-3">
            <div className="flex flex-wrap items-end gap-3">
              <div className="w-72 max-w-full">
                <Label className="text-xs">Role name ({draft.role_audience === 'TENANT' ? 'company' : 'customer'} role)</Label>
                <Input aria-label="Role name" value={draft.role_name} disabled={readOnly} onChange={(e) => setDraft({ ...draft, role_name: e.target.value })} />
              </div>
              <label className="flex items-center gap-2 text-sm">
                <Checkbox checked={draft.is_active} disabled={readOnly} onCheckedChange={(v) => setDraft({ ...draft, is_active: v === true })} /> Active
              </label>
              {!readOnly && <Button onClick={save} disabled={busy || !draft.role_name.trim()}>Save role</Button>}
              {!readOnly && selected && <Button variant="outline" onClick={remove} disabled={busy}>Delete</Button>}
            </div>
            {readOnly && <p className="text-sm text-muted-foreground">System roles always have every right of their kind and cannot be changed.</p>}
            <div className="overflow-x-auto rounded-md border">
              <table className="w-full text-sm">
                <thead className="bg-muted/50 text-left text-xs">
                  <tr><th className="px-3 py-2">Area</th>{FLAGS.map((f) => <th key={f.key} className="px-2 py-2 text-center">{f.label}</th>)}<th className="px-2 py-2" /></tr>
                </thead>
                <tbody>
                  {byModule.map(([module, rows]) => (
                    <FragmentRows key={module} module={module} rows={rows} readOnly={readOnly} toggle={toggle} setRow={setRow} />
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ) : <p className="text-sm text-muted-foreground">Choose a role, or create one.</p>}
      </div>
    </div>
  );
}

function FragmentRows({ module, rows, readOnly, toggle, setRow }: {
  module: string; rows: Area[]; readOnly: boolean; toggle: (k: string, f: Flag, on: boolean) => void; setRow: (k: string, on: boolean) => void;
}) {
  return (
    <>
      <tr className="bg-muted/30"><td colSpan={7} className="px-3 py-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">{module}</td></tr>
      {rows.map((a) => (
        <tr key={a.area_key} className="border-t">
          <td className="px-3 py-1.5">{a.area_name}</td>
          {FLAGS.map((f) => (
            <td key={f.key} className="px-2 py-1.5 text-center">
              <Checkbox aria-label={`${a.area_name} ${f.label}`} checked={a[f.key]} disabled={readOnly} onCheckedChange={(v) => toggle(a.area_key, f.key, v === true)} />
            </td>
          ))}
          <td className="px-2 py-1.5 text-right">
            {!readOnly && <button className="text-xs text-muted-foreground underline" onClick={() => setRow(a.area_key, !(a.can_read && a.can_write && a.can_approve && a.can_void && a.can_delete))}>all/none</button>}
          </td>
        </tr>
      ))}
    </>
  );
}
