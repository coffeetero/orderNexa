'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ArrowLeft, Copy, History, MoreHorizontal, Pencil, Plus, Printer, Search, Trash2, Wheat } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { adminCall, adminDelete, adminPost } from '@/components/features/admin/adminShared';
import { useNavGuard } from '@/components/layout/nav-context';
import { useDeepLinkId } from '@/lib/use-deep-link';
import { cn } from '@/lib/utils';
import { IngredientsDialog } from './IngredientsDialog';
import { RecipeEditor } from './RecipeEditor';
import {
  AllergenList, FormulaTable, MakeFirstTable, Panel, StatementBlock, StepList, SummaryList,
} from './RecipeFigures';
import {
  fmtMinutes, fmtPct, fmtQty, scaleJson, SCALE_MODES, selectCls, TypePill, UNITS,
  type Calc, type Options, type RecipeDetail, type RecipeJson, type RecipeRow, type RecipeType, type Scale, type ScaleMode, type Unit,
} from './recipes-ui';

type Filter = 'ALL' | RecipeType | 'ARCHIVED';
const FILTERS: { key: Filter; label: string }[] = [
  { key: 'ALL', label: 'All' }, { key: 'DOUGH', label: 'Doughs' }, { key: 'PREFERMENT', label: 'Pre-ferments' }, { key: 'OTHER', label: 'Other' }, { key: 'ARCHIVED', label: 'Archived' },
];
const DEFAULT_VALUE: Record<ScaleMode, string> = { BATCHES: '1', DOUGH: '', FLOUR: '', PIECES: '' };

export function RecipesBook({ tenantId, canEdit, canDelete }: { tenantId: number; canEdit: boolean; canDelete: boolean }) {
  const [rows, setRows] = useState<RecipeRow[] | null>(null);
  const [options, setOptions] = useState<Options | null>(null);
  const [filter, setFilter] = useState<Filter>('ALL');
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<RecipeDetail | null>(null);
  const [mode, setMode] = useState<'view' | 'edit' | 'new'>('view');
  const [copyOf, setCopyOf] = useState<RecipeJson | null>(null);
  const [dirty, setDirty] = useState(false);
  const [scale, setScale] = useState<Scale>({ mode: 'BATCHES', value: '1', unit: 'kg', out_unit: 'g', room_f: '72', flour_f: '70', preferment_f: '70' });
  const [calc, setCalc] = useState<Calc | null>(null);
  const [scaleError, setScaleError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [ingOpen, setIngOpen] = useState(false);
  const reqSeq = useRef(0);
  const mainRef = useRef<HTMLElement>(null);
  useNavGuard(mode !== 'view' && dirty);

  const loadList = useCallback(() => {
    adminCall<RecipeRow[]>(`/api/inventory/recipes?tenant_id=${tenantId}`).then(setRows).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  const loadOptions = useCallback(() => {
    adminCall<Options>(`/api/inventory/recipes?tenant_id=${tenantId}&options=1`).then(setOptions).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  const show = useCallback((d: RecipeDetail) => {
    setDetail(d); setSelectedId(d.recipe.recipe_id); setCalc(d.calc); setScaleError(null);
    setScale((s) => ({ ...s, mode: 'BATCHES', value: '1', out_unit: d.recipe.display_unit }));
  }, []);
  const loadDetail = useCallback((id: number) => {
    adminCall<RecipeDetail>(`/api/inventory/recipes?tenant_id=${tenantId}&id=${id}`).then(show)
      .catch((e: Error) => { setError(e.message); setDetail(null); });
  }, [tenantId, show]);
  useEffect(() => { loadList(); loadOptions(); }, [loadList, loadOptions]);
  useEffect(() => { mainRef.current?.scrollTo({ top: 0 }); }, [mode, selectedId]);
  useDeepLinkId('recipe', rows !== null, (id) => { setMode('view'); loadDetail(id); });

  // Scaled figures from the database whenever the scale bar changes.
  const scaleKey = JSON.stringify(scaleJson(scale));
  useEffect(() => {
    if (!detail || mode !== 'view') return;
    const s = scaleJson(scale);
    if (s.value === null || !(s.value > 0)) { setScaleError('Enter how much to make.'); return; }
    const n = ++reqSeq.current;
    const t = setTimeout(() => {
      adminPost<Calc>('/api/inventory/recipes', { tenant_id: tenantId, preview: detail.recipe, scale: s })
        .then((c) => { if (n === reqSeq.current) { setCalc(c); setScaleError(null); } })
        .catch((e: Error) => { if (n === reqSeq.current) setScaleError(e.message); });
    }, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scaleKey, detail, mode, tenantId]);

  const leaveEdit = () => mode === 'view' || !dirty || window.confirm('Leave without saving your changes?');
  const select = (id: number) => {
    if (!leaveEdit()) return;
    setMode('view'); setDirty(false); setNotice(null); setError(null);
    if (detail?.recipe.recipe_id !== id) setDetail(null);
    setSelectedId(id);
    loadDetail(id);
  };

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (rows ?? []).filter((r) =>
      (filter === 'ARCHIVED' ? !r.is_active : r.is_active && (filter === 'ALL' || r.recipe_type === filter))
      && (!q || `${r.recipe_name} ${r.dough_code ?? ''}`.toLowerCase().includes(q)));
  }, [rows, filter, search]);

  const afterSave = (d: RecipeDetail) => {
    setMode('view'); setCopyOf(null); setNotice(`Saved version ${d.recipe.version_no}.`);
    show(d); loadList(); loadOptions();
  };
  const remove = async () => {
    if (!detail || !window.confirm(`Delete ${detail.recipe.recipe_name} with all its versions? This cannot be undone. To keep it but hide it, archive it instead (Edit, untick Active).`)) return;
    setError(null);
    try {
      await adminDelete(`/api/inventory/recipes/${detail.recipe.recipe_id}?tenant_id=${tenantId}`);
      setDetail(null); setSelectedId(null); setNotice('Recipe deleted.'); loadList(); loadOptions();
    } catch (e) { setError((e as Error).message); }
  };
  const duplicate = () => {
    if (!detail) return;
    const r = detail.recipe;
    setCopyOf({ ...r, recipe_id: null, version_no: undefined, recipe_name: `${r.recipe_name} (copy)`, dough_code: null, is_active: true });
    setMode('new'); setNotice(null);
  };
  const printSheet = () => {
    if (!detail) return;
    const s = scaleJson(scale);
    const p = new URLSearchParams({ id: String(detail.recipe.recipe_id), mode: s.mode, value: String(s.value ?? 1), unit: s.unit, out: s.out_unit });
    if (s.room_f !== null) p.set('room', String(s.room_f));
    if (s.flour_f !== null) p.set('flour', String(s.flour_f));
    if (s.preferment_f !== null) p.set('pf', String(s.preferment_f));
    window.open(`/inventory/recipes/print?${p.toString()}`, '_blank', 'noopener');
  };
  const setMode2 = (m: ScaleMode) => setScale((s) => ({ ...s, mode: m, value: DEFAULT_VALUE[m] }));

  const showDetailPane = mode !== 'view' || selectedId !== null;
  const c = calc ?? detail?.calc ?? null;

  return (
    <div className="flex min-h-[32rem] gap-3 p-2 sm:p-3 lg:h-[calc(100dvh-7.5rem)]">
      {/* List pane */}
      <aside className={cn('flex w-full flex-col rounded-lg border bg-card shadow-sm lg:w-[17rem] lg:shrink-0 xl:w-[19rem]', showDetailPane && 'hidden lg:flex')}>
        <div className="space-y-2 border-b p-3">
          <div className="flex items-center gap-1">
            <h1 className="mr-auto text-lg font-semibold">Recipes</h1>
            <Button size="sm" variant="outline" className="gap-1" onClick={() => setIngOpen(true)}><Wheat className="h-4 w-4" />Ingredients</Button>
            {canEdit && (
              <Button size="sm" className="gap-1" onClick={() => { if (!leaveEdit()) return; setCopyOf(null); setMode('new'); setDetail(null); setSelectedId(null); setNotice(null); }}>
                <Plus className="h-4 w-4" />New
              </Button>
            )}
          </div>
          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input type="search" placeholder="Search recipe or dough code" aria-label="Search recipes" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-8" />
          </div>
          <div className="flex flex-wrap gap-1">
            {FILTERS.map((x) => (
              <button key={x.key} type="button" onClick={() => setFilter(x.key)} aria-pressed={filter === x.key}
                className={cn('rounded-full px-2.5 py-0.5 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  filter === x.key ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground')}>
                {x.label}
              </button>
            ))}
          </div>
        </div>
        <ul className="flex-1 overflow-y-auto">
          {rows === null ? <li className="p-3 text-sm text-muted-foreground">Loading…</li>
            : shown.length === 0 ? (
              <li className="p-3 text-sm text-muted-foreground">
                {rows.length === 0 ? 'No recipes yet. Add your ingredients first (flour, water, salt, yeast), then a recipe.' : 'No recipe matches.'}
              </li>
            ) : shown.map((r) => (
              <li key={r.recipe_id}>
                <button type="button" onClick={() => select(r.recipe_id)}
                  className={cn('flex w-full items-center gap-2 border-b px-3 py-2 text-left hover:bg-muted/40 focus-visible:bg-muted/60 focus-visible:outline-none',
                    selectedId === r.recipe_id && 'bg-primary/10 shadow-[inset_3px_0_0_hsl(var(--primary))]')}>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium">{r.recipe_name}</span>
                    <span className="block truncate text-xs text-muted-foreground">
                      {[r.dough_code, fmtQty(r.total_qty, r.display_unit), r.hydration_pct !== null ? `${fmtPct(r.hydration_pct, 0)} hydration` : null].filter(Boolean).join(' · ')}
                    </span>
                  </span>
                  <TypePill type={r.recipe_type} active={r.is_active} />
                </button>
              </li>
            ))}
        </ul>
        <div className="border-t px-3 py-1.5 text-xs text-muted-foreground">{shown.length} of {rows?.length ?? 0} recipes</div>
      </aside>

      {/* Detail pane */}
      <main ref={mainRef} className={cn('min-w-0 flex-1 overflow-y-auto', !showDetailPane && 'hidden lg:block')}>
        <button type="button" className="mb-2 flex items-center gap-1 text-sm text-primary lg:hidden"
          onClick={() => { if (!leaveEdit()) return; setMode('view'); setSelectedId(null); setDetail(null); }}>
          <ArrowLeft className="h-4 w-4" /> Recipes
        </button>
        {error && <p role="alert" className="mb-2 rounded-md border border-destructive/40 px-3 py-2 text-sm text-destructive">{error}</p>}
        {notice && mode === 'view' && <p role="status" className="mb-2 text-sm text-muted-foreground">{notice}</p>}

        {mode !== 'view' && options ? (
          <RecipeEditor key={mode === 'new' ? `new-${copyOf?.recipe_name ?? ''}` : `edit-${detail?.recipe.recipe_id}-${detail?.recipe.version_no}`}
            tenantId={tenantId} detail={mode === 'edit' ? detail : null} copyOf={mode === 'new' ? copyOf : null} options={options}
            canEdit={canEdit} canDelete={canDelete} onSaved={afterSave} onOptionsChanged={loadOptions} onDirty={setDirty}
            onCancel={() => { setMode('view'); setCopyOf(null); }} />
        ) : detail && c ? (
          <div className="space-y-3">
            {/* Header */}
            <section className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border bg-card px-3 py-2.5 shadow-sm">
              <div className="mr-auto min-w-0">
                <h2 className="truncate text-lg font-semibold">{detail.recipe.recipe_name}</h2>
                <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
                  <TypePill type={detail.recipe.recipe_type} active={detail.recipe.is_active} />
                  {detail.recipe.dough_code && <span>Dough code {detail.recipe.dough_code}</span>}
                  {detail.item && <span>Makes {detail.item.item_number} {detail.item.item_name}</span>}
                  <span>Version {detail.recipe.version_no} · saved {detail.saved_on}{detail.saved_by_name ? ` by ${detail.saved_by_name}` : ''}</span>
                </p>
              </div>
              <DropdownMenu>
                <DropdownMenuTrigger asChild><Button size="sm" variant="outline" className="gap-1"><History className="h-4 w-4" />History</Button></DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="max-h-80 w-80 overflow-y-auto">
                  <DropdownMenuLabel>Versions</DropdownMenuLabel>
                  <DropdownMenuSeparator />
                  {detail.versions.map((v) => (
                    <DropdownMenuItem key={v.version_no} className="flex-col items-start gap-0" onSelect={(e) => e.preventDefault()}>
                      <span className="text-sm font-medium">Version {v.version_no} · {v.saved_on}</span>
                      <span className="text-xs text-muted-foreground">{v.change_note ?? 'No note'}{v.saved_by_name ? ` · ${v.saved_by_name}` : ''}</span>
                    </DropdownMenuItem>
                  ))}
                </DropdownMenuContent>
              </DropdownMenu>
              {(canEdit || canDelete) && (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild><Button size="sm" variant="outline" aria-label="More actions"><MoreHorizontal className="h-4 w-4" /></Button></DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    {canEdit && <DropdownMenuItem onSelect={duplicate}><Copy className="mr-2 h-4 w-4" />Duplicate as new recipe</DropdownMenuItem>}
                    {canDelete && <DropdownMenuItem className="text-destructive" onSelect={() => void remove()}><Trash2 className="mr-2 h-4 w-4" />Delete recipe…</DropdownMenuItem>}
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
              <Button size="sm" variant="outline" className="gap-1" onClick={printSheet}><Printer className="h-4 w-4" />Batch sheet</Button>
              {canEdit && <Button size="sm" className="gap-1" onClick={() => { setNotice(null); setMode('edit'); }}><Pencil className="h-4 w-4" />Edit</Button>}
            </section>

            {/* Scale bar */}
            <section className="flex flex-wrap items-end gap-3 rounded-lg border bg-card px-3 py-2.5 shadow-sm">
              <div className="min-w-0 max-w-full">
                <span className="mb-1 block text-xs font-medium text-muted-foreground">Scale by</span>
                <div role="group" aria-label="Scale by" className="inline-flex h-9 max-w-full overflow-x-auto rounded-md border border-input">
                  {SCALE_MODES.map((m) => (
                    <button key={m.key} type="button" aria-pressed={scale.mode === m.key} onClick={() => setMode2(m.key)}
                      className={cn('shrink-0 whitespace-nowrap border-l border-input px-3 text-sm font-medium first:border-l-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
                        scale.mode === m.key ? 'bg-accent text-accent-foreground' : 'bg-background text-muted-foreground hover:text-foreground')}>
                      {m.label}
                    </button>
                  ))}
                </div>
              </div>
              <div className="w-28">
                <Label htmlFor="sc-val" className="text-xs text-muted-foreground">{SCALE_MODES.find((m) => m.key === scale.mode)?.label}</Label>
                <Input id="sc-val" type="number" min={0} step="any" className="h-9 text-right" value={scale.value}
                  placeholder={scale.mode === 'DOUGH' || scale.mode === 'FLOUR' ? 'weight' : scale.mode === 'PIECES' ? 'pieces' : '1'}
                  onChange={(e) => setScale({ ...scale, value: e.target.value })} />
              </div>
              {(scale.mode === 'DOUGH' || scale.mode === 'FLOUR') && (
                <div className="w-20"><Label htmlFor="sc-unit" className="text-xs text-muted-foreground">in</Label>
                  <select id="sc-unit" className={selectCls} value={scale.unit} onChange={(e) => setScale({ ...scale, unit: e.target.value as Unit })}>
                    {UNITS.map((u) => <option key={u}>{u}</option>)}
                  </select></div>
              )}
              <div className="w-20"><Label htmlFor="sc-out" className="text-xs text-muted-foreground">Show in</Label>
                <select id="sc-out" className={selectCls} value={scale.out_unit} onChange={(e) => setScale({ ...scale, out_unit: e.target.value as Unit })}>
                  {UNITS.map((u) => <option key={u}>{u}</option>)}
                </select></div>
              <p className="min-w-[14rem] flex-1 pb-2 text-sm text-muted-foreground">
                {scaleError ? <span className="text-destructive">{scaleError}</span> : (
                  <>Factor <b className="text-foreground">{c.factor.toLocaleString('en-US', { maximumFractionDigits: 3 })}</b> · dough <b className="text-foreground">{fmtQty(c.totals.total_qty, c.out_unit)}</b>
                    {c.totals.pieces !== null && <> · <b className="text-foreground">{c.totals.pieces.toLocaleString('en-US')}</b> pieces</>}</>
                )}
              </p>
            </section>

            <div className="grid items-start gap-3 min-[1700px]:grid-cols-[minmax(0,1fr)_19rem]">
              <div className="min-w-0 space-y-3">
                <Panel title="Formula" sub="baker's % of total flour, counting the flour in pre-ferments">
                  <FormulaTable calc={c} onOpenRecipe={select} />
                </Panel>
                {c.make_first.map((m) => (
                  <Panel key={m.recipe_id} title={`Make first: ${m.recipe_name}`} sub={`${fmtQty(m.scaled_qty, c.out_unit)} for this batch${m.hydration_pct !== null ? ` · ${fmtPct(m.hydration_pct)} hydration` : ''}`}
                    action={<button type="button" className="text-sm font-medium text-primary hover:underline" onClick={() => select(m.recipe_id)}>Open recipe</button>}>
                    <MakeFirstTable m={m} unit={c.out_unit} />
                  </Panel>
                ))}
                <Panel title="Method" sub={[c.total_minutes ? `${fmtMinutes(c.total_minutes)} in all` : null, detail.recipe.ddt_f !== null ? `DDT ${detail.recipe.ddt_f} °F` : null].filter(Boolean).join(' · ') || undefined}>
                  <StepList steps={detail.recipe.steps} />
                </Panel>
                {detail.recipe.notes && <Panel title="Notes"><p className="whitespace-pre-line px-3 py-2.5 text-sm">{detail.recipe.notes}</p></Panel>}
              </div>

              <div className="grid min-w-0 items-start gap-3 md:grid-cols-2 min-[1700px]:grid-cols-1">
                <Panel title="Summary" sub={c.factor === 1 ? 'one batch' : `factor ${c.factor.toLocaleString('en-US', { maximumFractionDigits: 3 })}`}>
                  <SummaryList calc={c} />
                  {c.issues.filter((m) => !m.includes('no price')).map((m) => <p key={m} className="px-3 pb-2 text-xs text-warning">{m}</p>)}
                </Panel>
                {detail.recipe.ddt_f !== null && (
                  <Panel title="Water temperature" sub={`for DDT ${detail.recipe.ddt_f} °F`}>
                    <div className="grid grid-cols-3 gap-2 px-3 pt-2.5">
                      <TempInput id="wt-room" label="Room °F" value={scale.room_f} onChange={(v) => setScale({ ...scale, room_f: v })} />
                      <TempInput id="wt-flour" label="Flour °F" value={scale.flour_f} onChange={(v) => setScale({ ...scale, flour_f: v })} />
                      {c.water.has_preferment && <TempInput id="wt-pf" label="Pre-ferment °F" value={scale.preferment_f} onChange={(v) => setScale({ ...scale, preferment_f: v })} />}
                    </div>
                    <p className="px-3 py-2.5 text-sm text-muted-foreground">
                      {c.water.friction_f === null ? 'Set the mixer friction on the recipe to work this out.'
                        : c.water.water_f === null ? 'Enter the temperatures.'
                          : <>Water <b className="text-base text-foreground">{c.water.water_f} °F</b> <span className="text-xs">(DDT × {c.water.multiplier} − room − flour{c.water.has_preferment ? ' − pre-ferment' : ''} − friction {c.water.friction_f})</span></>}
                    </p>
                  </Panel>
                )}
                <Panel title="Allergens" sub="from ingredients"><AllergenList calc={c} /></Panel>
                {(detail.used_by_items.length > 0 || detail.recipe.dough_code) && (
                  <Panel title="Used by items" sub={detail.recipe.dough_code ? `dough code ${detail.recipe.dough_code}` : undefined}>
                    {detail.used_by_items.length === 0 ? <p className="px-3 py-2.5 text-sm text-muted-foreground">No item has this dough code.</p> : (
                      <ul className="max-h-60 overflow-y-auto text-sm">
                        {detail.used_by_items.map((i) => (
                          <li key={i.item_id} className={cn('flex gap-2 border-t px-3 py-1.5 first:border-t-0', !i.is_active && 'text-muted-foreground')}>
                            <span className="min-w-0 flex-1 truncate"><span className="text-muted-foreground">{i.item_number}</span> {i.item_name}</span>
                            <span className="text-xs text-muted-foreground">{i.is_active ? i.unit_of_sale : 'Inactive'}</span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </Panel>
                )}
                {detail.used_in.length > 0 && (
                  <Panel title="Used in recipes">
                    <ul className="text-sm">
                      {detail.used_in.map((r) => (
                        <li key={r.recipe_id} className="border-t px-3 py-1.5 first:border-t-0">
                          <button type="button" className="font-medium text-primary hover:underline" onClick={() => select(r.recipe_id)}>{r.recipe_name}</button>
                        </li>
                      ))}
                    </ul>
                  </Panel>
                )}
                <StatementBlock text={c.ingredient_statement} />
              </div>
            </div>
          </div>
        ) : selectedId !== null ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : (
          <div className="flex h-full min-h-[20rem] items-center justify-center rounded-lg border bg-card text-sm text-muted-foreground">Pick a recipe, or add a new one.</div>
        )}
      </main>

      <IngredientsDialog tenantId={tenantId} open={ingOpen} onOpenChange={(o) => { setIngOpen(o); if (!o) { loadOptions(); if (detail && mode === 'view') loadDetail(detail.recipe.recipe_id); } }}
        canEdit={canEdit} canDelete={canDelete} />
    </div>
  );
}

function TempInput({ id, label, value, onChange }: { id: string; label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div><Label htmlFor={id} className="text-xs text-muted-foreground">{label}</Label>
      <Input id={id} type="number" step="any" className="h-8 text-right" value={value} onChange={(e) => onChange(e.target.value)} /></div>
  );
}
