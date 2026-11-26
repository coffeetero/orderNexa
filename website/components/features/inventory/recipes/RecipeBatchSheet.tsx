'use client';

import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { Printer } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { adminCall, adminPost } from '@/components/features/admin/adminShared';
import { fmtMinutes, fmtNum, fmtPct, fmtQty, typeLabel, type Calc, type CalcLine, type RecipeDetail, type Step, type Unit } from './recipes-ui';

// Printing shows only the sheet (moved to the end of <body>); print colours are fixed black on white.
const PRINT_CSS = `
@media print {
  @page { margin: 0.4in; }
  body > *:not(#batch-print) { display: none !important; }
  #batch-print { display: block !important; }
  html, body { background: #fff !important; height: auto !important; overflow: visible !important; }
}
#batch-print { display: none; }
.bs { font: 12px/1.35 Inter, Helvetica, Arial, sans-serif; color: #000; background: #fff; font-variant-numeric: tabular-nums; }
.bs h1 { font-size: 18px; margin: 0; }
.bs h2 { font-size: 13px; margin: 14px 0 4px; border-bottom: 1.5px solid #000; padding-bottom: 2px; }
.bs table { width: 100%; border-collapse: collapse; }
.bs th { text-align: left; font-size: 10px; text-transform: uppercase; letter-spacing: .05em; border-bottom: 1px solid #000; padding: 3px 6px; }
.bs td { border-bottom: 1px solid #bbb; padding: 4px 6px; vertical-align: top; }
.bs .r { text-align: right; }
.bs .box { width: 18px; } .bs .box span { display: inline-block; width: 11px; height: 11px; border: 1px solid #000; }
.bs .big { font-weight: 700; font-size: 13px; }
.bs .meta { display: flex; flex-wrap: wrap; gap: 4px 18px; margin-top: 4px; }
.bs .fill { display: flex; gap: 18px; margin-top: 8px; } .bs .fill span { flex: 1; border-bottom: 1px solid #000; padding-top: 12px; font-size: 10px; }
.bs .sec { break-inside: avoid; page-break-inside: avoid; }
.bs .muted { color: #444; }
`;

interface ScaleIn { mode: string; value: number; unit: string; out_unit: string | null; room_f: number | null; flour_f: number | null; preferment_f: number | null }

function Ingredients({ lines, unit }: { lines: CalcLine[]; unit: Unit }) {
  return (
    <table>
      <thead><tr><th className="box" /><th>Ingredient</th><th className="r">Amount</th><th className="r">Baker&apos;s %</th></tr></thead>
      <tbody>
        {lines.map((l) => (
          <tr key={l.line_no}>
            <td className="box"><span /></td>
            <td>{l.name}{l.note ? <span className="muted"> · {l.note}</span> : null}</td>
            <td className="r big">{fmtQty(l.scaled_qty, unit)}</td>
            <td className="r">{fmtPct(l.bakers_pct, 2)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
function Steps({ steps }: { steps: Step[] }) {
  if (steps.length === 0) return null;
  return (
    <table>
      <thead><tr><th style={{ width: 22 }}>#</th><th style={{ width: 70 }}>Step</th><th>Instruction</th><th className="r" style={{ width: 70 }}>Time</th><th className="r" style={{ width: 60 }}>°F</th><th style={{ width: 90 }}>Actual</th></tr></thead>
      <tbody>
        {steps.map((s, i) => (
          <tr key={i}><td>{i + 1}</td><td>{s.step_type}</td><td style={{ whiteSpace: 'pre-line' }}>{s.instruction}</td>
            <td className="r">{fmtMinutes(s.duration_min)}</td><td className="r">{s.temperature_f !== null ? fmtNum(s.temperature_f, 1) : ''}</td><td /></tr>
        ))}
      </tbody>
    </table>
  );
}

/** Printable batch sheet scaled as on the Recipes screen: pre-ferments first, the final dough as a check list, the method with an "Actual" column. */
export function RecipeBatchSheet({ tenantId, recipeId, scale }: { tenantId: number; recipeId: number | null; scale: ScaleIn }) {
  const [detail, setDetail] = useState<RecipeDetail | null>(null);
  const [calc, setCalc] = useState<Calc | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [mounted, setMounted] = useState(false);
  const scaleKey = JSON.stringify(scale);

  useEffect(() => {
    setMounted(true);
    if (recipeId === null) { setError('No recipe chosen. Open a recipe on Recipes and choose Batch sheet.'); return; }
    const s = JSON.parse(scaleKey) as ScaleIn;
    adminCall<RecipeDetail>(`/api/inventory/recipes?tenant_id=${tenantId}&id=${recipeId}`)
      .then((d) => {
        setDetail(d);
        return adminPost<Calc>('/api/inventory/recipes', { tenant_id: tenantId, preview: d.recipe, scale: { ...s, out_unit: s.out_unit ?? d.recipe.display_unit } });
      })
      .then(setCalc)
      .catch((e: Error) => setError(e.message));
  }, [tenantId, recipeId, scaleKey]);

  const sheet = detail && calc ? (
    <div className="bs">
      <div className="sec">
        <h1>{detail.recipe.recipe_name}</h1>
        <div className="meta">
          <span>{typeLabel(detail.recipe.recipe_type)}{detail.recipe.dough_code ? ` · ${detail.recipe.dough_code}` : ''} · version {detail.recipe.version_no}</span>
          <span>Factor <b>{fmtNum(calc.factor, 3)}</b></span>
          <span>Dough <b>{fmtQty(calc.totals.total_qty, calc.out_unit)}</b></span>
          <span>Flour <b>{fmtQty(calc.totals.flour_qty, calc.out_unit)}</b></span>
          {calc.totals.hydration_pct !== null && <span>Hydration <b>{fmtPct(calc.totals.hydration_pct)}</b></span>}
          {calc.totals.pieces !== null && <span>Pieces <b>{fmtNum(calc.totals.pieces, 0)}</b> × {fmtQty(calc.totals.piece_weight_qty, calc.out_unit)}</span>}
          {calc.water.water_f !== null && <span>Water temp <b>{calc.water.water_f} °F</b> (DDT {calc.water.ddt_f} °F)</span>}
          {calc.allergens.length > 0 && <span>Contains <b>{calc.allergens.map((a) => a.label).join(', ')}</b></span>}
        </div>
        <div className="fill"><span>Date</span><span>Baker</span><span>Batch no.</span><span>Dough temp</span></div>
      </div>
      {calc.make_first.map((m) => (
        <div key={m.recipe_id} className="sec">
          <h2>First: {m.recipe_name} · {fmtQty(m.scaled_qty, calc.out_unit)}</h2>
          <Ingredients lines={m.lines} unit={calc.out_unit} />
          <Steps steps={m.steps} />
        </div>
      ))}
      <div className="sec">
        <h2>{calc.make_first.length ? 'Final dough' : 'Ingredients'}</h2>
        <Ingredients lines={calc.lines} unit={calc.out_unit} />
      </div>
      {detail.recipe.steps.length > 0 && <div className="sec"><h2>Method</h2><Steps steps={detail.recipe.steps} /></div>}
      {detail.recipe.notes && <div className="sec"><h2>Notes</h2><p style={{ whiteSpace: 'pre-line', margin: 0 }}>{detail.recipe.notes}</p></div>}
    </div>
  ) : null;

  return (
    <div className="space-y-3 p-2 sm:p-3">
      <style>{PRINT_CSS}</style>
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="mr-auto text-lg font-semibold">Batch Sheet</h1>
        <Button className="gap-1" disabled={!sheet} onClick={() => window.print()}><Printer className="h-4 w-4" />Print</Button>
      </div>
      <p className="text-sm text-muted-foreground">Scaled as set on the Recipes screen. Use Print, then Save as PDF for a PDF.</p>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      {!error && !sheet && <p className="text-sm text-muted-foreground">Loading…</p>}
      {sheet && <div className="max-w-[60rem] overflow-x-auto rounded-lg border bg-card p-1"><div className="rounded-md bg-background p-4">{sheet}</div></div>}
      {mounted && sheet && createPortal(<div id="batch-print">{sheet}</div>, document.body)}
    </div>
  );
}
