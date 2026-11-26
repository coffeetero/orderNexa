'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowDown, ArrowUp, Plus, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { adminPost } from '@/components/features/admin/adminShared';
import { cn } from '@/lib/utils';
import { IngredientsDialog } from './IngredientsDialog';
import { Panel, SummaryList } from './RecipeFigures';
import {
  fmtPct, fmtQty, RECIPE_TYPES, selectCls, STEP_TYPES, tdCls, thCls, UNITS,
  type Calc, type Ingredient, type Options, type RecipeDetail, type RecipeJson, type RecipeType, type Unit,
} from './recipes-ui';

interface LineForm { key: number; source: string; quantity: string; unit: Unit; note: string }
interface StepForm { key: number; step_type: string; instruction: string; duration_min: string; temperature_f: string }
interface Form {
  recipe_name: string; recipe_type: RecipeType; dough_code: string; item_id: string; piece_weight: string; piece_unit: Unit;
  loss_pct: string; ddt_f: string; friction_f: string; display_unit: Unit; notes: string; is_active: boolean;
  lines: LineForm[]; steps: StepForm[];
}

let seq = 1;
const s = (v: string | number | null | undefined) => (v === null || v === undefined ? '' : String(v));
const num = (v: string) => (v.trim() === '' ? null : Number(v));
const newLine = (): LineForm => ({ key: seq++, source: '', quantity: '', unit: 'g', note: '' });
const newStep = (): StepForm => ({ key: seq++, step_type: 'MIX', instruction: '', duration_min: '', temperature_f: '' });

function formFrom(r: RecipeJson | null): Form {
  return {
    recipe_name: s(r?.recipe_name), recipe_type: r?.recipe_type ?? 'DOUGH', dough_code: s(r?.dough_code), item_id: s(r?.item_id),
    piece_weight: s(r?.piece_weight), piece_unit: r?.piece_unit ?? 'g', loss_pct: s(r?.loss_pct ?? 0), ddt_f: s(r?.ddt_f),
    friction_f: s(r?.friction_f), display_unit: r?.display_unit ?? 'g', notes: s(r?.notes), is_active: r?.is_active ?? true,
    lines: r?.lines.length
      ? r.lines.map((l) => ({ key: seq++, source: l.ingredient_id ? `i:${l.ingredient_id}` : `r:${l.sub_recipe_id}`, quantity: s(l.quantity), unit: l.unit, note: s(l.note) }))
      : [newLine(), newLine(), newLine()],
    steps: r?.steps.map((st) => ({ key: seq++, step_type: st.step_type, instruction: st.instruction, duration_min: s(st.duration_min), temperature_f: s(st.temperature_f) })) ?? [],
  };
}
const complete = (l: LineForm) => l.source !== '' && Number(l.quantity) > 0;

/** The recipe as the database expects it; only complete lines and written steps are sent. */
function toJson(f: Form, base: RecipeDetail['recipe'] | null): RecipeJson {
  return {
    recipe_id: base?.recipe_id ?? null, version_no: base?.version_no,
    recipe_name: f.recipe_name, recipe_type: f.recipe_type, dough_code: f.dough_code || null, item_id: num(f.item_id),
    piece_weight: num(f.piece_weight), piece_unit: f.piece_unit, loss_pct: num(f.loss_pct) ?? 0, ddt_f: num(f.ddt_f),
    friction_f: num(f.friction_f), display_unit: f.display_unit, notes: f.notes || null, is_active: f.is_active,
    lines: f.lines.filter(complete).map((l) => ({
      ingredient_id: l.source.startsWith('i:') ? Number(l.source.slice(2)) : null,
      sub_recipe_id: l.source.startsWith('r:') ? Number(l.source.slice(2)) : null,
      quantity: Number(l.quantity), unit: l.unit, note: l.note || null,
    })),
    steps: f.steps.filter((st) => st.instruction.trim() !== '').map((st) => ({
      step_type: st.step_type, instruction: st.instruction, duration_min: num(st.duration_min), temperature_f: num(st.temperature_f),
    })),
  };
}

function move<T>(list: T[], i: number, d: -1 | 1): T[] {
  const j = i + d;
  if (j < 0 || j >= list.length) return list;
  const out = [...list];
  [out[i], out[j]] = [out[j], out[i]];
  return out;
}

/**
 * Create / edit a recipe. Baker's %, totals and cost update as you type (inv_recipe_preview); Save stores a new version
 * with the optional change note (inv_recipe_save).
 */
export function RecipeEditor({ tenantId, detail, copyOf, options, canEdit, canDelete, onSaved, onCancel, onOptionsChanged, onDirty }: {
  tenantId: number; detail: RecipeDetail | null; copyOf: RecipeJson | null; options: Options; canEdit: boolean; canDelete: boolean;
  onSaved: (d: RecipeDetail) => void; onCancel: () => void; onOptionsChanged: () => void; onDirty: (d: boolean) => void;
}) {
  const [form, setForm] = useState<Form>(() => formFrom(detail?.recipe ?? copyOf));
  const [baseline] = useState(() => JSON.stringify(formFrom(detail?.recipe ?? copyOf)).replace(/"key":\d+,?/g, ''));
  const [note, setNote] = useState('');
  const [calc, setCalc] = useState<Calc | null>(detail?.calc ?? null);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [newIng, setNewIng] = useState<{ lineKey: number; name: string } | null>(null);
  const reqSeq = useRef(0);

  const json = useMemo(() => toJson(form, detail?.recipe ?? null), [form, detail]);
  const dirty = JSON.stringify(form).replace(/"key":\d+,?/g, '') !== baseline;
  useEffect(() => { onDirty(dirty); }, [dirty, onDirty]);

  // Live figures from the database for the unsaved recipe.
  useEffect(() => {
    const n = ++reqSeq.current;
    const t = setTimeout(() => {
      adminPost<Calc>('/api/inventory/recipes', { tenant_id: tenantId, preview: json, scale: { out_unit: json.display_unit } })
        .then((c) => { if (n === reqSeq.current) { setCalc(c); setPreviewError(null); } })
        .catch((e: Error) => { if (n === reqSeq.current) setPreviewError(e.message); });
    }, 300);
    return () => clearTimeout(t);
  }, [json, tenantId]);

  // Baker's % per form line: the preview lists only complete lines, in order.
  const pctByKey = useMemo(() => {
    const m = new Map<number, Calc['lines'][number]>();
    if (!calc) return m;
    form.lines.filter(complete).forEach((l, i) => { const c = calc.lines[i]; if (c) m.set(l.key, c); });
    return m;
  }, [calc, form.lines]);

  const setLine = (key: number, patch: Partial<LineForm>) => setForm((f) => ({ ...f, lines: f.lines.map((l) => (l.key === key ? { ...l, ...patch } : l)) }));
  const setStep = (key: number, patch: Partial<StepForm>) => setForm((f) => ({ ...f, steps: f.steps.map((st) => (st.key === key ? { ...st, ...patch } : st)) }));
  const pickSource = (key: number, v: string) => {
    if (v === 'new') { setNewIng({ lineKey: key, name: '' }); return; }
    setLine(key, { source: v });
  };
  const ingredientAdded = (i: Ingredient) => {
    if (newIng) setLine(newIng.lineKey, { source: `i:${i.ingredient_id}` });
    onOptionsChanged();
  };

  const save = async () => {
    setBusy(true); setError(null);
    try {
      const d = await adminPost<RecipeDetail>('/api/inventory/recipes', { tenant_id: tenantId, recipe: json, change_note: note });
      onDirty(false);
      onSaved(d);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  const cancel = () => {
    if (dirty && !window.confirm('Leave without saving your changes?')) return;
    onDirty(false);
    onCancel();
  };

  const selfId = detail?.recipe.recipe_id;
  const recipes = options.recipes.filter((r) => r.recipe_id !== selfId);
  const f = form;

  return (
    <div className="space-y-3">
      <Panel title={detail ? `Edit ${detail.recipe.recipe_name}` : 'New recipe'} sub={detail ? `Version ${detail.recipe.version_no} · saving makes version ${detail.recipe.version_no + 1}` : undefined}>
        <div className="grid gap-3 p-3 sm:grid-cols-2 xl:grid-cols-4">
          <div className="sm:col-span-2"><Label htmlFor="rc-name" className="text-xs">Recipe name *</Label>
            <Input id="rc-name" autoFocus value={f.recipe_name} onChange={(e) => setForm({ ...f, recipe_name: e.target.value })} /></div>
          <div><Label htmlFor="rc-type" className="text-xs">Type</Label>
            <select id="rc-type" className={selectCls} value={f.recipe_type} onChange={(e) => setForm({ ...f, recipe_type: e.target.value as RecipeType })}>
              {RECIPE_TYPES.map((t) => <option key={t.key} value={t.key}>{t.label}</option>)}
            </select></div>
          <div><Label htmlFor="rc-code" className="text-xs">Dough code (as on items)</Label>
            <Input id="rc-code" value={f.dough_code} placeholder="e.g. CIAPATA" onChange={(e) => setForm({ ...f, dough_code: e.target.value.toUpperCase() })} /></div>
          <div className="sm:col-span-2"><Label htmlFor="rc-item" className="text-xs">Finished item (optional)</Label>
            <select id="rc-item" className={selectCls} value={f.item_id} onChange={(e) => setForm({ ...f, item_id: e.target.value })}>
              <option value="">None</option>
              {options.items.map((i) => <option key={i.item_id} value={i.item_id}>{i.item_number} {i.item_name}</option>)}
            </select></div>
          <div className="grid grid-cols-[minmax(0,1fr)_5rem] gap-2">
            <div><Label htmlFor="rc-piece" className="text-xs">Weight per piece</Label>
              <Input id="rc-piece" type="number" min={0} step="any" className="text-right" value={f.piece_weight} onChange={(e) => setForm({ ...f, piece_weight: e.target.value })} /></div>
            <div><Label htmlFor="rc-punit" className="text-xs">Unit</Label>
              <select id="rc-punit" className={selectCls} value={f.piece_unit} onChange={(e) => setForm({ ...f, piece_unit: e.target.value as Unit })}>
                {UNITS.map((u) => <option key={u}>{u}</option>)}
              </select></div>
          </div>
          <div><Label htmlFor="rc-loss" className="text-xs">Dough loss %</Label>
            <Input id="rc-loss" type="number" min={0} max={49} step="any" className="text-right" value={f.loss_pct} onChange={(e) => setForm({ ...f, loss_pct: e.target.value })} /></div>
          <div><Label htmlFor="rc-ddt" className="text-xs">Desired dough temp °F</Label>
            <Input id="rc-ddt" type="number" step="any" className="text-right" value={f.ddt_f} onChange={(e) => setForm({ ...f, ddt_f: e.target.value })} /></div>
          <div><Label htmlFor="rc-fric" className="text-xs">Mixer friction °F</Label>
            <Input id="rc-fric" type="number" step="any" className="text-right" value={f.friction_f} onChange={(e) => setForm({ ...f, friction_f: e.target.value })} /></div>
          <div><Label htmlFor="rc-unit" className="text-xs">Show in</Label>
            <select id="rc-unit" className={selectCls} value={f.display_unit} onChange={(e) => setForm({ ...f, display_unit: e.target.value as Unit })}>
              {UNITS.map((u) => <option key={u}>{u}</option>)}
            </select></div>
          <label className="flex items-end gap-2 pb-2 text-sm"><Checkbox checked={f.is_active} onCheckedChange={(v) => setForm({ ...f, is_active: v === true })} />Active (untick to archive)</label>
        </div>
      </Panel>

      <div className="grid items-start gap-3 min-[1700px]:grid-cols-[minmax(0,1fr)_19rem]">
        <Panel title="Formula" sub="quantities for one base batch; mark flours and liquids under Ingredients"
          action={<Button size="sm" variant="outline" className="h-7" onClick={() => setNewIng({ lineKey: -1, name: '' })}>New ingredient</Button>}>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr>
                <th className={cn(thCls, 'min-w-[12rem]')}>Ingredient or recipe</th><th className={cn(thCls, 'text-right')}>Quantity</th>
                <th className={thCls}>Unit</th><th className={cn(thCls, 'text-right')}>Baker&apos;s %</th><th className={thCls}>Note</th><th className={thCls}><span className="sr-only">Actions</span></th>
              </tr></thead>
              <tbody>
                {f.lines.map((l, i) => {
                  const c = pctByKey.get(l.key);
                  return (
                    <tr key={l.key}>
                      <td className={cn(tdCls, 'py-1')}>
                        <select aria-label={`Line ${i + 1} ingredient`} className={cn(selectCls, 'h-8')} value={l.source} onChange={(e) => pickSource(l.key, e.target.value)}>
                          <option value="">Pick…</option>
                          <optgroup label="Ingredients">
                            {options.ingredients.filter((x) => x.is_active || l.source === `i:${x.ingredient_id}`).map((x) => (
                              <option key={x.ingredient_id} value={`i:${x.ingredient_id}`}>{x.ingredient_name}{x.ingredient_role !== 'OTHER' ? ` (${x.ingredient_role.toLowerCase()})` : ''}</option>
                            ))}
                          </optgroup>
                          <optgroup label="Recipes (pre-ferments, fillings)">
                            {recipes.filter((x) => x.is_active || l.source === `r:${x.recipe_id}`).map((x) => (
                              <option key={x.recipe_id} value={`r:${x.recipe_id}`}>{x.recipe_name}</option>
                            ))}
                          </optgroup>
                          {canEdit && <option value="new">+ New ingredient…</option>}
                        </select>
                      </td>
                      <td className={cn(tdCls, 'py-1')}>
                        <Input aria-label={`Line ${i + 1} quantity`} type="number" min={0} step="any" className="h-8 w-24 text-right" value={l.quantity}
                          onChange={(e) => setLine(l.key, { quantity: e.target.value })} />
                      </td>
                      <td className={cn(tdCls, 'py-1')}>
                        <select aria-label={`Line ${i + 1} unit`} className={cn(selectCls, 'h-8 w-20')} value={l.unit} onChange={(e) => setLine(l.key, { unit: e.target.value as Unit })}>
                          {UNITS.map((u) => <option key={u}>{u}</option>)}
                        </select>
                      </td>
                      <td className={cn(tdCls, 'py-1 text-right tabular-nums')}>{c ? fmtPct(c.bakers_pct, 2) : ''}</td>
                      <td className={cn(tdCls, 'py-1')}>
                        <Input aria-label={`Line ${i + 1} note`} className="h-8 min-w-[6rem]" value={l.note} onChange={(e) => setLine(l.key, { note: e.target.value })} />
                      </td>
                      <td className={cn(tdCls, 'py-1')}>
                        <div className="flex">
                          <Button size="icon" variant="ghost" className="h-8 w-8" aria-label="Move up" disabled={i === 0} onClick={() => setForm({ ...f, lines: move(f.lines, i, -1) })}><ArrowUp className="h-4 w-4" /></Button>
                          <Button size="icon" variant="ghost" className="h-8 w-8" aria-label="Move down" disabled={i === f.lines.length - 1} onClick={() => setForm({ ...f, lines: move(f.lines, i, 1) })}><ArrowDown className="h-4 w-4" /></Button>
                          <Button size="icon" variant="ghost" className="h-8 w-8 text-destructive" aria-label="Remove line" onClick={() => setForm({ ...f, lines: f.lines.filter((x) => x.key !== l.key) })}><Trash2 className="h-4 w-4" /></Button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
              {calc && (
                <tfoot><tr className="bg-muted/30 font-semibold">
                  <td className={tdCls}>Total dough</td><td className={cn(tdCls, 'text-right')}>{fmtQty(calc.totals.total_qty, calc.out_unit)}</td><td className={tdCls} />
                  <td className={cn(tdCls, 'text-right')}>{fmtPct(calc.totals.total_pct, 2)}</td><td className={tdCls} colSpan={2} />
                </tr></tfoot>
              )}
            </table>
          </div>
          <div className="px-3 py-2"><Button size="sm" variant="outline" className="gap-1" onClick={() => setForm({ ...f, lines: [...f.lines, newLine()] })}><Plus className="h-4 w-4" />Add line</Button></div>
        </Panel>

        <Panel title="Live figures" sub="one base batch">
          {previewError && <p role="alert" className="px-3 pt-2 text-sm text-destructive">{previewError}</p>}
          {calc && <SummaryList calc={calc} />}
          {calc && calc.issues.filter((m) => !m.includes('no price')).map((m) => <p key={m} className="px-3 pb-2 text-xs text-warning">{m}</p>)}
        </Panel>
      </div>

      <Panel title="Method" sub="times in minutes, temperatures in °F">
        <div className="divide-y">
          {f.steps.map((st, i) => (
            <div key={st.key} className="grid gap-2 px-3 py-2 sm:grid-cols-[1.5rem_8rem_minmax(0,1fr)_6rem_6rem_auto] sm:items-start">
              <span className="pt-2 text-sm font-semibold text-muted-foreground">{i + 1}</span>
              <select aria-label={`Step ${i + 1} type`} className={selectCls} value={st.step_type} onChange={(e) => setStep(st.key, { step_type: e.target.value })}>
                {STEP_TYPES.map((t) => <option key={t} value={t}>{t.charAt(0) + t.slice(1).toLowerCase()}</option>)}
              </select>
              <Textarea aria-label={`Step ${i + 1} instruction`} rows={2} className="min-h-9" value={st.instruction} placeholder="What to do"
                onChange={(e) => setStep(st.key, { instruction: e.target.value })} />
              <Input aria-label={`Step ${i + 1} minutes`} type="number" min={0} placeholder="min" className="text-right" value={st.duration_min} onChange={(e) => setStep(st.key, { duration_min: e.target.value })} />
              <Input aria-label={`Step ${i + 1} temperature °F`} type="number" placeholder="°F" className="text-right" value={st.temperature_f} onChange={(e) => setStep(st.key, { temperature_f: e.target.value })} />
              <div className="flex">
                <Button size="icon" variant="ghost" className="h-9 w-9" aria-label="Move step up" disabled={i === 0} onClick={() => setForm({ ...f, steps: move(f.steps, i, -1) })}><ArrowUp className="h-4 w-4" /></Button>
                <Button size="icon" variant="ghost" className="h-9 w-9" aria-label="Move step down" disabled={i === f.steps.length - 1} onClick={() => setForm({ ...f, steps: move(f.steps, i, 1) })}><ArrowDown className="h-4 w-4" /></Button>
                <Button size="icon" variant="ghost" className="h-9 w-9 text-destructive" aria-label="Remove step" onClick={() => setForm({ ...f, steps: f.steps.filter((x) => x.key !== st.key) })}><Trash2 className="h-4 w-4" /></Button>
              </div>
            </div>
          ))}
        </div>
        <div className="px-3 py-2"><Button size="sm" variant="outline" className="gap-1" onClick={() => setForm({ ...f, steps: [...f.steps, newStep()] })}><Plus className="h-4 w-4" />Add step</Button></div>
      </Panel>

      <Panel title="Notes">
        <div className="p-3"><Textarea aria-label="Recipe notes" rows={3} value={f.notes} placeholder="Handling tips, sourcing, why this formula" onChange={(e) => setForm({ ...f, notes: e.target.value })} /></div>
      </Panel>

      <div className="sticky bottom-0 z-10 flex flex-wrap items-end gap-2 rounded-lg border bg-card p-3 shadow-sm">
        <div className="min-w-[16rem] flex-1"><Label htmlFor="rc-note" className="text-xs">What changed? (kept with the version)</Label>
          <Input id="rc-note" value={note} placeholder={detail ? 'e.g. Salt 2.0% to 2.2%' : 'Created'} onChange={(e) => setNote(e.target.value)} /></div>
        {error && <p role="alert" className="basis-full text-sm text-destructive sm:order-first">{error}</p>}
        <Button variant="outline" onClick={cancel} disabled={busy}>Cancel</Button>
        <Button onClick={() => void save()} disabled={busy || !f.recipe_name.trim() || json.lines.length === 0}>Save recipe</Button>
      </div>

      <IngredientsDialog tenantId={tenantId} open={newIng !== null} onOpenChange={(o) => { if (!o) setNewIng(null); }}
        canEdit={canEdit} canDelete={canDelete} startNew={newIng ? newIng.name : null}
        onSaved={(i) => { if (newIng && newIng.lineKey >= 0) ingredientAdded(i); else onOptionsChanged(); }} />
    </div>
  );
}
