'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminPost, useBanner } from './adminShared';

interface Settings {
  idle_timeout_minutes: number;
  min_password_length: number;
  password_max_age_days: number;
  password_history_count: number;
  inactive_alert_days: number;
}

const FIELDS: { key: keyof Settings; label: string; help: string; min: number; max: number; unit: string }[] = [
  { key: 'idle_timeout_minutes', label: 'Sign out after inactivity', help: 'Minutes without activity before a person is signed out. 0 means never.', min: 0, max: 1440, unit: 'minutes' },
  { key: 'min_password_length', label: 'Minimum password length', help: 'Shortest password a person may choose.', min: 8, max: 128, unit: 'characters' },
  { key: 'password_max_age_days', label: 'Force a password change every', help: 'Days before a password must be changed. 0 means never.', min: 0, max: 730, unit: 'days' },
  { key: 'password_history_count', label: 'Passwords that cannot be reused', help: 'How many of a person’s previous passwords are refused. 0 means reuse is allowed.', min: 0, max: 24, unit: 'passwords' },
  { key: 'inactive_alert_days', label: 'Ask about staff inactive for', help: 'Working days (Monday to Friday) without using BPS before Company Administrators see a To-Do asking whether the person is still with the company.', min: 1, max: 60, unit: 'working days' },
];

export function SecurityAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [form, setForm] = useState<Record<keyof Settings, string> | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const s = await adminCall<Settings>(`/api/admin/security?tenant_id=${tenantId}`);
      setForm({
        idle_timeout_minutes: String(s.idle_timeout_minutes), min_password_length: String(s.min_password_length),
        password_max_age_days: String(s.password_max_age_days), password_history_count: String(s.password_history_count),
        inactive_alert_days: String(s.inactive_alert_days ?? 3),
      });
    } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);
  useEffect(() => { void load(); }, [load]);

  const invalid = !form || FIELDS.some((f) => {
    const v = form[f.key];
    return v.trim() === '' || !Number.isInteger(Number(v)) || Number(v) < f.min || Number(v) > f.max;
  });

  async function save() {
    if (!form) return;
    setBusy(true);
    try {
      await adminPost('/api/admin/security', {
        tenant_id: tenantId,
        settings: Object.fromEntries(FIELDS.map((f) => [f.key, Number(form[f.key])])),
      });
      notify('Security settings saved.', 'success');
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-2 sm:p-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Security</h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            Sign-in rules for everyone in your company. These settings are saved now; they are not enforced at sign-in yet.
          </p>
        </div>
        <Button size="sm" onClick={save} disabled={busy || invalid}>Save</Button>
      </div>
      {banner}
      <Card><CardContent className="space-y-4 pt-6">
        {form && FIELDS.map((f) => (
          <div key={f.key} className="grid items-end gap-3 border-b pb-4 last:border-0 last:pb-0 sm:grid-cols-[1fr_10rem_6rem]">
            <div>
              <Label htmlFor={f.key} className="text-sm font-medium">{f.label}</Label>
              <p className="text-xs text-muted-foreground">{f.help}</p>
            </div>
            <Input id={f.key} type="number" min={f.min} max={f.max} value={form[f.key]} onChange={(e) => setForm({ ...form, [f.key]: e.target.value })} />
            <span className="pb-2 text-sm text-muted-foreground">{f.unit}</span>
          </div>
        ))}
      </CardContent></Card>
    </div>
  );
}
