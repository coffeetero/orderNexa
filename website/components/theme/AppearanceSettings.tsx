'use client';

import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { Download, Palette, Pencil, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { chooseAppearance, saveAccountAppearance, useAppearanceState } from '@/components/theme/AppearanceProvider';
import type { ModeChoice } from '@/lib/theme/apply';
import { completeSeeds, fixesMessage, type TokenMap } from '@/lib/theme/derive';
import { fetchPublicText, importFromGithub, type FetchText, type ImportedTheme } from '@/lib/theme/github';
import { DEFAULT_APPEARANCE, deviceAppearance, themePreview, type AppearancePrefs } from '@/lib/theme/prefs';
import {
  BUILTIN_THEMES, CUSTOM_LIMIT, DEFAULT_THEME, LABEL_MAX, SEED_KEYS, SEED_LABEL, cleanLabel, copyTheme, findTheme, isBuiltinId,
  newThemeId, type SeedKey, type ThemeDef, type ThemeMode,
} from '@/lib/theme/themes';
import { deriveBps } from '@/lib/theme/tokens';
import { CURATED_THEMES } from '@/lib/theme/catalog';
import { cn } from '@/lib/utils';

export const TRY_SECONDS = 30;
const MODE_OPTIONS: { value: ModeChoice; label: string }[] = [
  { value: 'light', label: 'Light' }, { value: 'dark', label: 'Dark' }, { value: 'system', label: 'Follow system' },
];
const MODE_NAME: Record<ThemeMode, string> = { light: 'Light', dark: 'Dark' };

type Tone = 'success' | 'danger' | 'info';
const toneClass: Record<Tone, string> = {
  success: 'border-success/40 bg-success-soft text-success',
  danger: 'border-destructive/40 bg-destructive/10 text-destructive',
  info: 'border-info/40 bg-info-soft text-info',
};
function Message({ tone, children, onDismiss }: { tone: Tone; children: React.ReactNode; onDismiss?: () => void }) {
  return (
    <div role="status" className={cn('flex items-start justify-between gap-3 rounded-md border px-3 py-2 text-sm', toneClass[tone])}>
      <span>{children}</span>
      {onDismiss && <button type="button" onClick={onDismiss} className="shrink-0 text-xs underline" aria-label="Dismiss message">Dismiss</button>}
    </div>
  );
}

/** A tiny picture of the app in a theme: sidebar, page, a raised card with the accent and status colours. */
export function ThemeSwatch({ tokens }: { tokens: TokenMap }) {
  const v = (k: keyof TokenMap) => tokens[k];
  return (
    <span aria-hidden="true" className="flex h-14 w-full gap-1 overflow-hidden rounded-md border p-1" style={{ background: v('--bg'), borderColor: v('--border') } as CSSProperties}>
      <span className="w-1/4 rounded-sm border" style={{ background: v('--panel-left'), borderColor: v('--border') }} />
      <span className="flex flex-1 flex-col justify-center gap-1 rounded-sm border px-1.5" style={{ background: v('--panel-raised'), borderColor: v('--border') }}>
        <span className="h-1 rounded-full" style={{ background: v('--text'), width: '80%' }} />
        <span className="h-1 rounded-full" style={{ background: v('--text-3'), width: '50%' }} />
        <span className="flex items-center gap-1">
          <span className="h-2 w-6 rounded-sm" style={{ background: v('--accent') }} />
          <span className="h-2 w-2 rounded-full" style={{ background: v('--positive') }} />
          <span className="h-2 w-2 rounded-full" style={{ background: v('--negative') }} />
        </span>
      </span>
    </span>
  );
}

/** The raw colours of each mode a theme has (import preview). */
function SeedStrip({ theme }: { theme: Pick<ThemeDef, 'inputs'> }) {
  return (
    <div className="space-y-1">
      {(['light', 'dark'] as ThemeMode[]).map((m) => {
        const s = theme.inputs[m];
        return (
          <div key={m} className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <span className="w-10">{MODE_NAME[m]}</span>
            {s ? SEED_KEYS.map((k) => (s[k] ? <span key={k} title={`${SEED_LABEL[k]} ${s[k]}`} className="h-3.5 w-3.5 rounded-sm border" style={{ background: s[k] }} /> : null)) : <span className="italic">none (the other variant is used)</span>}
          </div>
        );
      })}
    </div>
  );
}

/**
 * Admin › Appearance: Light / Dark / Follow system, a gallery of themes (built-in, curated and your own), live try-on (Keep / Revert, auto-revert
 * after TRY_SECONDS), import from a GitHub link, and a colour editor for your own themes. Saved with your account (all devices) or on this device only.
 */
export function AppearanceSettings({ fetchText = fetchPublicText }: { fetchText?: FetchText }) {
  const state = useAppearanceState();
  const { account, device, preview, current } = state;
  const acct: AppearancePrefs = account ?? DEFAULT_APPEARANCE;
  const want: ThemeMode = state.mode;
  const themes = useMemo(() => [...BUILTIN_THEMES, ...CURATED_THEMES, ...acct.custom], [acct.custom]);
  const [msg, setMsg] = useState<{ tone: Tone; text: string } | null>(null);
  const [trial, setTrial] = useState<{ theme: ThemeDef; left: number } | null>(null);
  const [editing, setEditing] = useState<{ draft: ThemeDef; isNew: boolean; mode: ThemeMode } | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const canSave = !!account; // own themes and account-wide choices need the loaded account preferences
  const local = !!device || !account;

  useEffect(() => () => themePreview.set(null), []); // the try-on never outlives this page
  const revert = () => { themePreview.set(null); setTrial(null); };
  useEffect(() => {
    if (!trial) return;
    if (trial.left <= 0) { revert(); setMsg({ tone: 'info', text: 'Reverted to your theme.' }); return; }
    const t = setTimeout(() => setTrial((x) => (x ? { ...x, left: x.left - 1 } : x)), 1000);
    return () => clearTimeout(t);
  }, [trial]);

  const saveAccount = async (a: AppearancePrefs): Promise<boolean> => {
    setBusy(true);
    const r = await saveAccountAppearance(a);
    setBusy(false);
    if (!r.ok) { setMsg({ tone: 'danger', text: r.error }); return false; }
    return true;
  };
  const choose = (next: { mode: ModeChoice; theme: ThemeDef }) => chooseAppearance(next, state);

  const tryOn = (t: ThemeDef) => {
    setMsg(null); setEditing(null);
    if (t.id === current.theme.id) { revert(); return; }
    themePreview.set(t); setTrial({ theme: t, left: TRY_SECONDS });
  };
  const keep = async () => {
    if (!trial) return;
    const ok = await choose({ mode: current.mode, theme: trial.theme });
    const label = trial.theme.label;
    revert();
    if (ok) setMsg({ tone: 'success', text: `${label} is now your theme${local ? ' on this device' : ''}.` });
  };
  const setDeviceOnly = (on: boolean) => { deviceAppearance.write(on ? current : null); setMsg(null); };

  const saveCustom = (list: ThemeDef[], themeId = acct.themeId) => saveAccount({ ...acct, custom: list, themeId: findTheme(themeId, list) ? themeId : DEFAULT_THEME.id });
  const startEdit = (t: ThemeDef, isNew: boolean) => {
    revert(); setMsg(null);
    const draft = isNew ? copyTheme(t, isBuiltinId(t.id) ? `${t.label} copy`.slice(0, LABEL_MAX) : `${t.label} copy`.slice(0, LABEL_MAX)) : (JSON.parse(JSON.stringify(t)) as ThemeDef);
    setEditing({ draft, isNew, mode: draft.inputs[want] ? want : draft.inputs.light ? 'light' : 'dark' });
    themePreview.set(draft);
  };
  const updateDraft = (draft: ThemeDef) => { setEditing((e) => (e ? { ...e, draft } : e)); themePreview.set(draft); };
  const cancelEdit = () => { setEditing(null); themePreview.set(null); };
  const saveEdit = async () => {
    if (!editing) return;
    const label = cleanLabel(editing.draft.label);
    if (!label) { setMsg({ tone: 'danger', text: 'Give your theme a name.' }); return; }
    const draft = { ...editing.draft, label };
    if (editing.isNew && acct.custom.length >= CUSTOM_LIMIT) { setMsg({ tone: 'danger', text: `You can keep up to ${CUSTOM_LIMIT} themes of your own.` }); return; }
    const list = editing.isNew ? [...acct.custom, draft] : acct.custom.map((x) => (x.id === draft.id ? draft : x));
    if (await saveCustom(list, draft.id)) {
      if (device) deviceAppearance.write({ mode: device.mode, theme: draft });
      setEditing(null); themePreview.set(null); setMsg({ tone: 'success', text: `Saved “${label}”.` });
    }
  };
  const remove = async (t: ThemeDef) => {
    setConfirmDelete(null);
    if (await saveCustom(acct.custom.filter((x) => x.id !== t.id))) {
      if (device?.theme.id === t.id) deviceAppearance.write({ mode: device.mode, theme: DEFAULT_THEME });
      setMsg({ tone: 'success', text: `Deleted “${t.label}”.` });
    }
  };
  const saveImported = async (t: ImportedTheme, label: string): Promise<boolean> => {
    if (acct.custom.length >= CUSTOM_LIMIT) { setMsg({ tone: 'danger', text: `You can keep up to ${CUSTOM_LIMIT} themes of your own.` }); return false; }
    const def: ThemeDef = { v: 1, id: newThemeId(), label: cleanLabel(label) || t.label, inputs: t.inputs, source: t.source };
    const ok = await saveCustom([...acct.custom, def]);
    if (ok) setMsg({ tone: 'success', text: `Saved “${def.label}”. Click it in the gallery to try it on.` });
    return ok;
  };

  const shown = preview ?? current.theme;
  const shownFix = fixesMessage(deriveBps(shown, want).fixes);

  const group = (title: string, description: string, list: ThemeDef[]) => list.length === 0 ? null : (
    <section aria-label={title} className="space-y-2">
      <div>
        <h3 className="text-sm font-semibold">{title}</h3>
        <p className="text-xs text-muted-foreground">{description}</p>
      </div>
      <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4" aria-label={title}>
        {list.map((t) => {
          const d = deriveBps(t, want); const selected = t.id === current.theme.id; const own = !isBuiltinId(t.id);
          return (
            <li key={t.id} data-testid={`theme-${t.id}`}
              className={cn('flex flex-col gap-2 rounded-lg border p-3', selected && 'border-primary ring-1 ring-primary', preview?.id === t.id && 'border-dashed border-primary')}>
              <button type="button" aria-label={`Try ${t.label}`} aria-pressed={selected} onClick={() => tryOn(t)}
                className="flex flex-col gap-2 rounded-md text-left outline-none focus-visible:ring-2 focus-visible:ring-ring">
                {d.preview && <ThemeSwatch tokens={d.preview} />}
                <span className="text-sm font-medium">{t.label}</span>
                <span className="text-xs text-muted-foreground">
                  {selected ? 'Your theme' : own ? 'Yours' : isBuiltinId(t.id) && CURATED_THEMES.some((c) => c.id === t.id) ? 'Curated' : 'Built-in'}
                  {d.mode !== want ? ` · ${MODE_NAME[d.mode]} only` : ''}
                </span>
              </button>
              <div className="flex flex-wrap items-center gap-1">
                {confirmDelete === t.id ? (
                  <>
                    <span className="text-xs">Delete “{t.label}”?</span>
                    <Button size="sm" variant="destructive" onClick={() => void remove(t)}>Delete</Button>
                    <Button size="sm" variant="ghost" onClick={() => setConfirmDelete(null)}>Cancel</Button>
                  </>
                ) : (
                  <>
                    <Button size="sm" variant="ghost" disabled={!canSave} onClick={() => startEdit(t, !own)} aria-label={own ? `Edit colours of ${t.label}` : `Edit a copy of ${t.label}`}>
                      <Pencil className="mr-1 h-3.5 w-3.5" />{own ? 'Edit' : 'Copy & edit'}
                    </Button>
                    {own && (
                      <Button size="sm" variant="ghost" disabled={!canSave} onClick={() => setConfirmDelete(t.id)} aria-label={`Delete ${t.label}`}>
                        <Trash2 className="mr-1 h-3.5 w-3.5" />Delete
                      </Button>
                    )}
                  </>
                )}
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );

  return (
    <div className="mx-auto max-w-5xl space-y-4 py-4">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Appearance</h1>
        <p className="text-sm text-muted-foreground">Light, dark or following your system, and the colours of the whole app: built-in and curated themes, your own, or a Claude Code theme imported from GitHub.</p>
      </div>

      {trial && (
        <div role="region" aria-label="Theme try-on" className="sticky top-0 z-20 flex flex-wrap items-center gap-3 rounded-md border border-primary bg-card px-3 py-2 text-sm shadow-sm">
          <span role="status">Trying <strong>{trial.theme.label}</strong>.{shownFix ? ` ${shownFix}.` : ''}</span>
          <span className="text-muted-foreground" data-testid="try-countdown">Reverts in {trial.left} s</span>
          <span className="ml-auto flex gap-2">
            <Button size="sm" onClick={() => void keep()} disabled={busy}>Keep this theme</Button>
            <Button size="sm" variant="secondary" onClick={revert}>Revert</Button>
          </span>
        </div>
      )}
      {msg && <Message tone={msg.tone} onDismiss={() => setMsg(null)}>{msg.text}</Message>}
      {!account && <Message tone="info">Your account preferences could not be loaded, so your choices are kept on this device only.</Message>}

      <Card className="border-border/60">
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-base"><Palette className="h-4 w-4" />Light and dark</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <RadioGroup value={current.mode} onValueChange={(m) => { setMsg(null); void choose({ mode: m as ModeChoice, theme: current.theme }); }} className="flex flex-wrap gap-5" aria-label="Mode">
            {MODE_OPTIONS.map((o) => (
              <div key={o.value} className="flex items-center gap-2">
                <RadioGroupItem value={o.value} id={`mode-${o.value}`} />
                <Label htmlFor={`mode-${o.value}`}>{o.label}</Label>
              </div>
            ))}
          </RadioGroup>
          <p className="text-xs text-muted-foreground">Each theme has a light and a dark variant; this picks which one you see. A theme with only one variant always shows that one.</p>
          <div className="flex items-start gap-2">
            <Checkbox id="device-only" checked={!!device} onCheckedChange={(c) => setDeviceOnly(c === true)} disabled={!account && !device} />
            <div>
              <Label htmlFor="device-only">This device only</Label>
              <p className="text-xs text-muted-foreground">Use a different mode and theme on this device; your account&apos;s choice stays as it is for your other devices.</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card className="border-border/60">
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Themes</CardTitle>
          <CardDescription>Click a theme to try it on the whole app.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          {group('Built-in', 'Made for BPS. Bakery is the default.', BUILTIN_THEMES)}
          {group('Curated', 'Popular palettes, picked for BPS from the Claude Code theme gallery (ccthemes by livlign, MIT).', CURATED_THEMES)}
          {group('Yours', 'Themes you made or imported. They follow your account.', acct.custom)}
        </CardContent>
      </Card>

      {editing && <ThemeEditor draft={editing.draft} mode={editing.mode} busy={busy} onMode={(mode) => setEditing((e) => (e ? { ...e, mode } : e))} onChange={updateDraft} onSave={() => void saveEdit()} onCancel={cancelEdit} />}

      <GithubImport fetchText={fetchText} disabled={!canSave} onSave={saveImported} want={want} />
      {themes.length === 0 && null}
    </div>
  );
}

function ThemeEditor({ draft, mode, busy, onMode, onChange, onSave, onCancel }: { draft: ThemeDef; mode: ThemeMode; busy: boolean; onMode: (m: ThemeMode) => void; onChange: (t: ThemeDef) => void; onSave: () => void; onCancel: () => void }) {
  const seeds = draft.inputs[mode];
  const full = seeds ? completeSeeds(seeds, mode === 'dark') : null;
  const fix = fixesMessage(deriveBps(draft, mode).fixes);
  const set = (k: SeedKey, v: string) => { if (!full) return; onChange({ ...draft, inputs: { ...draft.inputs, [mode]: { ...full, [k]: v.toLowerCase() } } }); };
  const addMode = () => onChange({ ...draft, inputs: { ...draft.inputs, [mode]: completeSeeds(DEFAULT_THEME.inputs[mode]!, mode === 'dark') } });
  const dropMode = () => { const other: ThemeMode = mode === 'dark' ? 'light' : 'dark'; if (!draft.inputs[other]) return; const inputs = { ...draft.inputs }; delete inputs[mode]; onChange({ ...draft, inputs }); };
  return (
    <Card className="border-border/60">
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Edit colours</CardTitle>
        <CardDescription>Changes show on the whole app as you make them. Save to keep them.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="max-w-sm space-y-1.5">
          <Label htmlFor="theme-name">Theme name</Label>
          <Input id="theme-name" value={draft.label} maxLength={LABEL_MAX} onChange={(e) => onChange({ ...draft, label: e.currentTarget.value })} />
        </div>
        <div className="flex gap-1" role="tablist" aria-label="Variant">
          {(['light', 'dark'] as ThemeMode[]).map((m) => (
            <button key={m} type="button" role="tab" aria-selected={mode === m} onClick={() => onMode(m)}
              className={cn('rounded-md border px-3 py-1 text-sm', mode === m ? 'border-primary bg-accent text-accent-foreground' : 'text-muted-foreground')}>{MODE_NAME[m]}</button>
          ))}
        </div>
        {!full ? (
          <Message tone="info">This theme has no {mode} variant; the {mode === 'dark' ? 'light' : 'dark'} one is shown instead. <Button size="sm" variant="secondary" className="ml-2" onClick={addMode}>Add a {mode} variant</Button></Message>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {SEED_KEYS.map((k) => (
                <label key={k} className="flex items-center gap-2 text-sm">
                  <input type="color" value={full[k]} aria-label={`${SEED_LABEL[k]} (${mode})`} onChange={(e) => set(k, e.currentTarget.value)} className="h-8 w-10 cursor-pointer rounded border bg-transparent p-0" />
                  <span><span className="block">{SEED_LABEL[k]}</span><code className="text-xs text-muted-foreground">{full[k]}</code></span>
                </label>
              ))}
            </div>
            {fix && <p className="text-xs text-warning">{fix}: some colours are shown lighter or darker than picked so text stays readable.</p>}
            {draft.inputs[mode === 'dark' ? 'light' : 'dark'] && <Button size="sm" variant="ghost" onClick={dropMode}>Remove the {mode} variant</Button>}
          </>
        )}
        <div className="flex gap-2">
          <Button onClick={onSave} disabled={busy}>Save theme</Button>
          <Button variant="secondary" onClick={onCancel}>Cancel</Button>
        </div>
      </CardContent>
    </Card>
  );
}

function GithubImport({ fetchText, disabled, onSave, want }: { fetchText: FetchText; disabled: boolean; onSave: (t: ImportedTheme, label: string) => Promise<boolean>; want: ThemeMode }) {
  const [url, setUrl] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [found, setFound] = useState<{ theme: ImportedTheme; label: string; saved: boolean }[]>([]);
  const seq = useRef(0);
  const look = async () => {
    const n = ++seq.current; setBusy(true); setError(''); setFound([]);
    const r = await importFromGithub(url, fetchText);
    if (n !== seq.current) return;
    setBusy(false);
    if (!r.ok) setError(r.error); else setFound(r.themes.map((theme) => ({ theme, label: theme.label, saved: false })));
  };
  return (
    <Card className="border-border/60">
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base"><Download className="h-4 w-4" />Import from GitHub</CardTitle>
        <CardDescription>Paste a link to a public repository, folder or file with a Claude Code theme. Only its colours are read; any code in it is never run. Terminal themes have no page background, so one is chosen for you; edit it afterwards.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <form className="flex max-w-2xl items-end gap-2" onSubmit={(e) => { e.preventDefault(); if (url.trim()) void look(); }}>
          <div className="flex-1 space-y-1.5">
            <Label htmlFor="github-link">GitHub link</Label>
            <Input id="github-link" placeholder="https://github.com/owner/repo" value={url} onChange={(e) => setUrl(e.currentTarget.value)} inputMode="url" autoComplete="off" spellCheck={false} />
          </div>
          <Button type="submit" variant="secondary" disabled={busy || !url.trim()}>{busy ? 'Looking…' : 'Look up'}</Button>
        </form>
        {error && <Message tone="danger">{error}</Message>}
        {found.map((f, i) => {
          const def: ThemeDef = { v: 1, id: `import-preview-${i}`, label: f.label, inputs: f.theme.inputs };
          const d = deriveBps(def, want);
          return (
            <div key={i} data-testid="found-theme" className="flex flex-wrap items-start gap-3 rounded-md border p-3">
              <div className="w-40">{d.preview && <ThemeSwatch tokens={d.preview} />}</div>
              <div className="min-w-0 flex-1 space-y-2">
                <div className="max-w-xs space-y-1.5">
                  <Label htmlFor={`found-name-${i}`}>Name</Label>
                  <Input id={`found-name-${i}`} value={f.label} maxLength={LABEL_MAX} onChange={(e) => { const label = e.currentTarget.value; setFound((xs) => xs.map((x, j) => (j === i ? { ...x, label } : x))); }} />
                </div>
                <p className="text-xs text-muted-foreground">Found in <code>{f.theme.file}</code></p>
                <SeedStrip theme={f.theme} />
                {f.saved ? <Message tone="success">Saved.</Message>
                  : <Button size="sm" disabled={disabled} onClick={async () => { if (await onSave(f.theme, f.label)) setFound((xs) => xs.map((x, j) => (j === i ? { ...x, saved: true } : x))); }}>Save theme</Button>}
              </div>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}
