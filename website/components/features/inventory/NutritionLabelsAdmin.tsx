'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Printer } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { adminCall, adminDelete, adminPost, useBanner } from '@/components/features/admin/adminShared';
import { NutritionFactsLabel, type NutritionLabelData } from '@/components/features/inventory/NutritionFactsLabel';
import { cn } from '@/lib/utils';

type Status = 'NONE' | 'DRAFT' | 'APPROVED';
interface ItemRow { item_id: number; item_number: string; item_name: string; category: string | null; is_active: boolean; status: Status }
interface NutrientDef { code: string; label: string; unit: string; daily_value: number | null; is_mandatory: boolean; indent: number }
interface Profile {
  status: Status; approved_at: string | null; approved_by_name: string | null; updated_at: string; updated_by_name: string | null;
  source_note: string | null; serving_size_text: string | null; serving_size_g: number | null; servings_per_container: number | null;
  label_format: Form['label_format']; is_dual_column: boolean; nutrients: Record<string, number>; ingredient_statement: string | null;
  allergens: Record<Allergen, boolean>; fish_species: string | null; shellfish_species: string | null; tree_nut_types: string | null;
  may_contain_text: string | null; effective_date: string | null;
}
interface Detail {
  item: { item_id: number; item_number: string; item_name: string; item_weight: number | null; weight_uom: string | null };
  profile: Profile | null; label: NutritionLabelData | null; nutrients: NutrientDef[];
  can_write: boolean; can_approve: boolean; can_delete: boolean;
}

const ALLERGENS = [
  ['milk', 'Milk'], ['egg', 'Egg'], ['fish', 'Fish'], ['shellfish', 'Crustacean shellfish'], ['tree_nuts', 'Tree nuts'],
  ['peanuts', 'Peanuts'], ['wheat', 'Wheat'], ['soy', 'Soy'], ['sesame', 'Sesame'],
] as const;
type Allergen = (typeof ALLERGENS)[number][0];
const noAllergens = Object.fromEntries(ALLERGENS.map(([k]) => [k, false])) as Record<Allergen, boolean>;

interface Form {
  source_note: string; serving_size_text: string; serving_size_g: string; servings_per_container: string;
  label_format: 'STANDARD' | 'TABULAR' | 'LINEAR'; is_dual_column: boolean; nutrients: Record<string, string>;
  ingredient_statement: string; allergens: Record<Allergen, boolean>; fish_species: string; shellfish_species: string;
  tree_nut_types: string; may_contain_text: string; effective_date: string;
}
const s = (v: string | number | null | undefined) => (v === null || v === undefined ? '' : String(v));
const formFrom = (p: Profile | null): Form => ({
  source_note: s(p?.source_note), serving_size_text: s(p?.serving_size_text), serving_size_g: s(p?.serving_size_g),
  servings_per_container: s(p?.servings_per_container), label_format: p?.label_format ?? 'STANDARD', is_dual_column: p?.is_dual_column ?? false,
  nutrients: Object.fromEntries(Object.entries(p?.nutrients ?? {}).map(([k, v]) => [k, String(v)])),
  ingredient_statement: s(p?.ingredient_statement), allergens: { ...noAllergens, ...(p?.allergens ?? {}) },
  fish_species: s(p?.fish_species), shellfish_species: s(p?.shellfish_species), tree_nut_types: s(p?.tree_nut_types),
  may_contain_text: s(p?.may_contain_text), effective_date: s(p?.effective_date),
});
const localDate = (v: string | null) => (v ? new Date(v).toLocaleDateString() : '—');
const STATUS_LABEL: Record<Status, string> = { NONE: 'No label', DRAFT: 'Draft', APPROVED: 'Approved' };
const FILTERS: (Status | 'ALL')[] = ['ALL', 'NONE', 'DRAFT', 'APPROVED'];
const selectCls = 'h-9 w-full rounded-md border border-input bg-background px-2 text-sm';

function StatusPill({ status }: { status: Status }) {
  return (
    <span className={cn('rounded px-1.5 py-0.5 text-[11px] font-medium',
      status === 'APPROVED' ? 'bg-primary/15 text-primary' : status === 'DRAFT' ? 'bg-amber-500/15 text-amber-700 dark:text-amber-400' : 'text-muted-foreground')}>
      {STATUS_LABEL[status]}
    </span>
  );
}

export function NutritionLabelsAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [items, setItems] = useState<ItemRow[]>([]);
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState<Status | 'ALL'>('ALL');
  const [checked, setChecked] = useState<Set<number>>(new Set());
  const [detail, setDetail] = useState<Detail | null>(null);
  const [form, setForm] = useState<Form>(formFrom(null));
  const [baseline, setBaseline] = useState('');
  const [preview, setPreview] = useState<NutritionLabelData | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [copyFrom, setCopyFrom] = useState('');
  const [busy, setBusy] = useState(false);
  const seq = useRef(0);

  const loadItems = useCallback(async () => {
    try { setItems(await adminCall<ItemRow[]>(`/api/inventory/nutrition?tenant_id=${tenantId}`)); } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);
  useEffect(() => { void loadItems(); }, [loadItems]);

  const show = (d: Detail) => {
    const f = formFrom(d.profile);
    setDetail(d); setForm(f); setBaseline(JSON.stringify(f)); setPreview(d.label); setCopyFrom('');
  };
  const dirty = detail !== null && JSON.stringify(form) !== baseline;

  const open = async (id: number) => {
    if (dirty && !window.confirm('Discard your unsaved changes?')) return;
    try { show(await adminCall<Detail>(`/api/inventory/nutrition?tenant_id=${tenantId}&item_id=${id}`)); } catch (e) { notify((e as Error).message, 'error'); }
  };

  const payload = useMemo(() => ({ ...form, item_id: detail?.item.item_id }), [form, detail]);

  // Live preview: the database rounds and works out % DV for the unsaved values.
  useEffect(() => {
    if (!detail) return;
    const n = ++seq.current;
    const t = setTimeout(() => {
      adminPost<NutritionLabelData>('/api/inventory/nutrition/preview', { tenant_id: tenantId, profile: payload })
        .then((l) => { if (n === seq.current) { setPreview(l); setPreviewError(null); } })
        .catch((e: Error) => { if (n === seq.current) setPreviewError(e.message); });
    }, 300);
    return () => clearTimeout(t);
  }, [payload, detail, tenantId]);

  const act = async (fn: () => Promise<Detail>, msg: string) => {
    setBusy(true);
    try { show(await fn()); notify(msg, 'success'); await loadItems(); } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  };
  const save = () => act(() => adminPost<Detail>('/api/inventory/nutrition', { tenant_id: tenantId, profile: payload }), 'Saved as draft.');
  const approve = (yes: boolean) => act(() => adminPost<Detail>('/api/inventory/nutrition/approve', { tenant_id: tenantId, item_id: detail?.item.item_id, approve: yes }), yes ? 'Label approved.' : 'Label set back to draft.');
  const copy = () => {
    const src = items.find((i) => i.item_id === Number(copyFrom));
    if (!src || !detail) return;
    if ((detail.profile || dirty) && !window.confirm(`Replace this item's label with the one from ${src.item_number} ${src.item_name}?`)) return;
    void act(() => adminPost<Detail>('/api/inventory/nutrition/copy', { tenant_id: tenantId, from_item_id: src.item_id, to_item_id: detail.item.item_id }), `Copied from ${src.item_name} as a draft.`);
  };
  const remove = async () => {
    if (!detail?.profile || !window.confirm('Delete this item\'s nutrition label? This cannot be undone.')) return;
    setBusy(true);
    try {
      await adminDelete(`/api/inventory/nutrition?tenant_id=${tenantId}&item_id=${detail.item.item_id}`);
      show(await adminCall<Detail>(`/api/inventory/nutrition?tenant_id=${tenantId}&item_id=${detail.item.item_id}`));
      notify('Label deleted.', 'success'); await loadItems();
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  };
  const print = (ids: number[]) => window.open(`/inventory/labels/print?ids=${ids.join(',')}`, '_blank', 'noopener');

  const shown = useMemo(() => {
    const t = q.trim().toLowerCase();
    return items.filter((i) => (filter === 'ALL' || i.status === filter) && (!t || `${i.item_number} ${i.item_name} ${i.category ?? ''}`.toLowerCase().includes(t)));
  }, [items, q, filter]);
  const withLabel = shown.filter((i) => i.status !== 'NONE');
  const printable = Array.from(checked).filter((id) => items.some((i) => i.item_id === id && i.status !== 'NONE'));
  const sources = items.filter((i) => i.status !== 'NONE' && i.item_id !== detail?.item.item_id);
  const setN = (code: string, v: string) => setForm((f) => ({ ...f, nutrients: { ...f.nutrients, [code]: v } }));
  const setA = (k: Allergen, v: boolean) => setForm((f) => ({ ...f, allergens: { ...f.allergens, [k]: v } }));
  const ro = !detail?.can_write;

  return (
    <div className="mx-auto max-w-[1800px] space-y-4 p-2 sm:p-3">
      <p className="max-w-3xl text-sm text-muted-foreground">
        Enter each item&apos;s nutrition values per serving from a lab or nutrition tool. Rounding and % Daily Values follow FDA rules (21 CFR 101.9) and are worked out for you.
      </p>
      {banner}
      <div className="grid gap-4 lg:grid-cols-[22rem_minmax(0,1fr)]">
        <Card><CardContent className="space-y-2 p-0">
          <div className="space-y-2 border-b p-3">
            <h1 className="text-xl font-semibold">Nutrition Labels</h1>
            <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search items" aria-label="Search items" />
            <div className="flex gap-2">
              <select aria-label="Label status" className={selectCls} value={filter} onChange={(e) => setFilter(e.target.value as Status | 'ALL')}>
                {FILTERS.map((f) => <option key={f} value={f}>{f === 'ALL' ? 'All items' : STATUS_LABEL[f]}</option>)}
              </select>
              <Button size="sm" variant="outline" className="h-9 shrink-0 gap-1" disabled={printable.length === 0} onClick={() => print(printable)}>
                <Printer className="h-4 w-4" />Print{printable.length ? ` (${printable.length})` : ''}
              </Button>
            </div>
            {withLabel.length > 0 && (
              <label className="flex items-center gap-2 text-xs text-muted-foreground">
                <Checkbox checked={withLabel.every((i) => checked.has(i.item_id))}
                  onCheckedChange={(v) => setChecked(v === true ? new Set(withLabel.map((i) => i.item_id)) : new Set())} />
                Select all with a label ({withLabel.length})
              </label>
            )}
          </div>
          <ul className="max-h-[72vh] divide-y overflow-y-auto">
            {shown.map((i) => (
              <li key={i.item_id} className={cn('flex items-center gap-2 px-3 py-1.5 text-sm hover:bg-muted', detail?.item.item_id === i.item_id && 'bg-accent', !i.is_active && 'text-muted-foreground')}>
                <Checkbox disabled={i.status === 'NONE'} checked={checked.has(i.item_id)} aria-label={`Select ${i.item_name} to print`}
                  onCheckedChange={(v) => setChecked((c) => { const n = new Set(c); if (v === true) n.add(i.item_id); else n.delete(i.item_id); return n; })} />
                <button type="button" className="min-w-0 flex-1 text-left" onClick={() => void open(i.item_id)}>
                  <span className="block truncate"><span className="text-muted-foreground">{i.item_number}</span> {i.item_name}</span>
                </button>
                <StatusPill status={i.status} />
              </li>
            ))}
            {shown.length === 0 && <li className="px-3 py-4 text-sm text-muted-foreground">No items.</li>}
          </ul>
        </CardContent></Card>

        {!detail ? (
          <Card><CardContent className="flex min-h-[40vh] items-center justify-center p-6 text-center text-sm text-muted-foreground">Select an item to enter or review its label.</CardContent></Card>
        ) : (
          <div className="min-w-0 space-y-4">
            <Card><CardContent className="flex flex-wrap items-center gap-2 pt-6">
              <div className="mr-auto min-w-0">
                <h2 className="truncate text-lg font-medium">{detail.item.item_number} {detail.item.item_name}</h2>
                <p className="text-xs text-muted-foreground">
                  <StatusPill status={detail.profile?.status ?? 'NONE'} />{' '}
                  {detail.profile?.status === 'APPROVED' && `by ${detail.profile.approved_by_name ?? '—'} on ${localDate(detail.profile.approved_at)}`}
                  {detail.profile && detail.profile.status !== 'APPROVED' && `saved ${localDate(detail.profile.updated_at)}${detail.profile.updated_by_name ? ` by ${detail.profile.updated_by_name}` : ''}`}
                  {dirty && <span className="ml-2 text-amber-700 dark:text-amber-400">Unsaved changes</span>}
                </p>
              </div>
              {detail.can_write && <Button size="sm" onClick={save} disabled={busy || !dirty}>Save Draft</Button>}
              {detail.can_approve && detail.profile && (detail.profile.status === 'APPROVED'
                ? <Button size="sm" variant="outline" onClick={() => void approve(false)} disabled={busy}>Back to Draft</Button>
                : <Button size="sm" variant="outline" onClick={() => void approve(true)} disabled={busy || dirty} title={dirty ? 'Save first' : undefined}>Approve</Button>)}
              <Button size="sm" variant="outline" className="gap-1" disabled={!detail.profile} onClick={() => print([detail.item.item_id])}><Printer className="h-4 w-4" />Print</Button>
              {detail.can_delete && detail.profile && <Button size="sm" variant="ghost" className="text-destructive" onClick={() => void remove()} disabled={busy}>Delete</Button>}
            </CardContent></Card>

            <div className="grid items-start gap-4 2xl:grid-cols-[minmax(0,1fr)_minmax(0,27rem)]">
              <div className="space-y-4">
                <Card><CardContent className="space-y-3 pt-6">
                  <h3 className="text-base font-medium">Serving</h3>
                  <div className="grid gap-3 sm:grid-cols-3">
                    <div><Label htmlFor="nl-hh" className="text-xs">Household measure</Label><Input id="nl-hh" disabled={ro} value={form.serving_size_text} placeholder="1 roll" onChange={(e) => setForm({ ...form, serving_size_text: e.target.value })} /></div>
                    <div><Label htmlFor="nl-g" className="text-xs">Serving size (g)</Label><Input id="nl-g" disabled={ro} type="number" min={0} step="any" value={form.serving_size_g} onChange={(e) => setForm({ ...form, serving_size_g: e.target.value })} /></div>
                    <div><Label htmlFor="nl-spc" className="text-xs">Servings per container</Label><Input id="nl-spc" disabled={ro} type="number" min={0} step="any" value={form.servings_per_container} onChange={(e) => setForm({ ...form, servings_per_container: e.target.value })} /></div>
                    <div><Label htmlFor="nl-fmt" className="text-xs">Label format</Label>
                      <select id="nl-fmt" disabled={ro} className={selectCls} value={form.label_format} onChange={(e) => { const v = e.target.value as Form['label_format']; setForm({ ...form, label_format: v, is_dual_column: v === 'STANDARD' && form.is_dual_column }); }}>
                        <option value="STANDARD">Standard (vertical)</option><option value="TABULAR">Tabular (wide packages)</option><option value="LINEAR">Linear (small packages)</option>
                      </select></div>
                    <label className="flex items-end gap-2 pb-2 text-sm"><Checkbox disabled={ro || form.label_format !== 'STANDARD'} checked={form.is_dual_column} onCheckedChange={(v) => setForm({ ...form, is_dual_column: v === true })} />Dual column (per serving and per container)</label>
                    <div><Label htmlFor="nl-eff" className="text-xs">Effective from</Label><Input id="nl-eff" disabled={ro} type="date" value={form.effective_date} onChange={(e) => setForm({ ...form, effective_date: e.target.value })} /></div>
                    <div className="sm:col-span-3"><Label htmlFor="nl-src" className="text-xs">Source of values</Label><Input id="nl-src" disabled={ro} value={form.source_note} placeholder="Lab report number or tool" onChange={(e) => setForm({ ...form, source_note: e.target.value })} /></div>
                  </div>
                  {detail.item.item_weight !== null && <p className="text-xs text-muted-foreground">Item weight: {detail.item.item_weight} {detail.item.weight_uom ?? ''}</p>}
                </CardContent></Card>

                <Card><CardContent className="space-y-3 pt-6">
                  <h3 className="text-base font-medium">Amounts per serving <span className="text-xs font-normal text-muted-foreground">unrounded, as reported · * required</span></h3>
                  <div className="gap-x-8 sm:columns-2">
                    {detail.nutrients.map((n) => (
                      <div key={n.code} className="mb-1.5 grid break-inside-avoid grid-cols-[1fr_6.5rem] items-center gap-2">
                        <Label htmlFor={`nl-${n.code}`} className={cn('text-sm', n.indent === 0 ? 'font-medium' : 'font-normal', n.indent === 1 && 'pl-3', n.indent === 2 && 'pl-6')}>
                          {n.label}{n.is_mandatory && <span className="text-muted-foreground"> *</span>}
                        </Label>
                        <div className="relative">
                          <Input id={`nl-${n.code}`} disabled={ro} type="number" min={0} step="any" className="h-8 pr-10 text-right" value={form.nutrients[n.code] ?? ''} onChange={(e) => setN(n.code, e.target.value)} />
                          <span className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">{n.unit}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </CardContent></Card>

                <Card><CardContent className="space-y-3 pt-6">
                  <h3 className="text-base font-medium">Ingredients and allergens</h3>
                  <div><Label htmlFor="nl-ing" className="text-xs">Ingredient statement (descending order by weight; show sub-ingredients in parentheses)</Label>
                    <Textarea id="nl-ing" disabled={ro} rows={4} value={form.ingredient_statement} onChange={(e) => setForm({ ...form, ingredient_statement: e.target.value })} /></div>
                  <div>
                    <Label className="text-xs">Contains (major food allergens)</Label>
                    <div className="mt-1 grid grid-cols-2 gap-2 sm:grid-cols-3 2xl:grid-cols-5">
                      {ALLERGENS.map(([k, label]) => (
                        <label key={k} className="flex items-center gap-2 text-sm"><Checkbox disabled={ro} checked={form.allergens[k]} onCheckedChange={(v) => setA(k, v === true)} />{label}</label>
                      ))}
                    </div>
                  </div>
                  <div className="grid gap-3 sm:grid-cols-3">
                    {form.allergens.tree_nuts && <div><Label htmlFor="nl-nuts" className="text-xs">Which tree nuts</Label><Input id="nl-nuts" disabled={ro} value={form.tree_nut_types} placeholder="Almonds, Pecans" onChange={(e) => setForm({ ...form, tree_nut_types: e.target.value })} /></div>}
                    {form.allergens.fish && <div><Label htmlFor="nl-fish" className="text-xs">Fish species</Label><Input id="nl-fish" disabled={ro} value={form.fish_species} onChange={(e) => setForm({ ...form, fish_species: e.target.value })} /></div>}
                    {form.allergens.shellfish && <div><Label htmlFor="nl-shell" className="text-xs">Shellfish species</Label><Input id="nl-shell" disabled={ro} value={form.shellfish_species} onChange={(e) => setForm({ ...form, shellfish_species: e.target.value })} /></div>}
                  </div>
                  <div><Label htmlFor="nl-may" className="text-xs">Advisory statement (optional, e.g. &quot;Made in a facility that also processes peanuts.&quot;)</Label>
                    <Input id="nl-may" disabled={ro} value={form.may_contain_text} onChange={(e) => setForm({ ...form, may_contain_text: e.target.value })} /></div>
                </CardContent></Card>

                {detail.can_write && (
                  <Card><CardContent className="flex flex-wrap items-end gap-2 pt-6">
                    <div className="min-w-[16rem] flex-1"><Label htmlFor="nl-copy" className="text-xs">Copy label from another item</Label>
                      <select id="nl-copy" className={selectCls} value={copyFrom} onChange={(e) => setCopyFrom(e.target.value)}>
                        <option value="">Pick an item with a label…</option>
                        {sources.map((i) => <option key={i.item_id} value={i.item_id}>{i.item_number} {i.item_name} ({STATUS_LABEL[i.status]})</option>)}
                      </select></div>
                    <Button size="sm" variant="outline" className="h-9" disabled={!copyFrom || busy} onClick={copy}>Copy</Button>
                  </CardContent></Card>
                )}
              </div>

              <Card className="order-first min-w-0 2xl:sticky 2xl:top-2 2xl:order-none"><CardContent className="space-y-3 pt-6">
                <h3 className="text-base font-medium">Preview</h3>
                {previewError && <p role="alert" className="text-sm text-destructive">{previewError}</p>}
                {preview && (
                  <>
                    <div className="max-w-full overflow-x-auto rounded border bg-white p-3"><NutritionFactsLabel label={preview} /></div>
                    {preview.issues.length > 0 && (
                      <div className="max-w-[26rem] text-xs">
                        <p className="font-medium">Before approval:</p>
                        <ul className="list-disc pl-4 text-muted-foreground">{preview.issues.map((m) => <li key={m}>{m}</li>)}</ul>
                      </div>
                    )}
                  </>
                )}
              </CardContent></Card>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
