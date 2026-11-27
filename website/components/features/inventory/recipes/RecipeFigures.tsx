'use client';

import { Copy } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import {
  fmtMinutes, fmtMoney, fmtNum, fmtPct, fmtQty, Pill, tdCls, thCls, type Calc, type CalcLine, type Step,
} from './recipes-ui';

/** A titled panel: one border, title row with an optional sub-line and action. */
export function Panel({ title, sub, action, children, className }: { title: string; sub?: React.ReactNode; action?: React.ReactNode; children: React.ReactNode; className?: string }) {
  return (
    <section className={cn('min-w-0 rounded-lg border bg-card shadow-sm', className)}>
      <div className="flex min-h-10 flex-wrap items-center gap-x-3 gap-y-1 border-b px-3 py-1.5">
        <h2 className="text-sm font-semibold">{title}</h2>
        {sub && <span className="text-xs text-muted-foreground">{sub}</span>}
        {action && <span className="ml-auto">{action}</span>}
      </div>
      {children}
    </section>
  );
}

const roleTag = (l: CalcLine) => (l.kind === 'RECIPE' ? 'Recipe' : l.role === 'FLOUR' ? 'Flour' : l.role === 'LIQUID' ? 'Liquid' : null);

/** The formula: one row per line with baker's %, base batch, scaled amount and cost; total and overall-formula rows. */
export function FormulaTable({ calc, onOpenRecipe, showCost = true }: { calc: Calc; onOpenRecipe?: (id: number) => void; showCost?: boolean }) {
  const t = calc.totals;
  const u = calc.out_unit;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr>
            <th className={thCls}>Ingredient</th>
            <th className={cn(thCls, 'text-right')}>Baker&apos;s %</th>
            <th className={cn(thCls, 'text-right')}>Base batch</th>
            <th className={cn(thCls, 'text-right')}>Scaled</th>
            {showCost && <th className={cn(thCls, 'text-right')}>Cost</th>}
          </tr>
        </thead>
        <tbody>
          {calc.lines.map((l) => (
            <tr key={l.line_no} className="hover:bg-muted/40">
              <td className={cn(tdCls, 'whitespace-normal')}>
                {l.kind === 'RECIPE' && onOpenRecipe
                  ? <button type="button" className="font-medium text-primary hover:underline" onClick={() => onOpenRecipe(l.sub_recipe_id as number)}>{l.name}</button>
                  : l.name}
                {roleTag(l) && <span className="ml-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{roleTag(l)}</span>}
                {l.note && <span className="ml-2 text-xs text-muted-foreground">{l.note}</span>}
              </td>
              <td className={cn(tdCls, 'text-right')}>{fmtPct(l.bakers_pct, 2)}</td>
              <td className={cn(tdCls, 'text-right text-muted-foreground')}>{fmtQty(l.quantity, l.unit)}</td>
              <td className={cn(tdCls, 'text-right font-semibold')}>{fmtQty(l.scaled_qty, u)}</td>
              {showCost && <td className={cn(tdCls, 'text-right')}>{fmtMoney(l.scaled_cost)}</td>}
            </tr>
          ))}
          {calc.lines.length === 0 && <tr><td colSpan={showCost ? 5 : 4} className={cn(tdCls, 'text-muted-foreground')}>No ingredients yet.</td></tr>}
        </tbody>
        <tfoot>
          <tr className="bg-muted/30 font-semibold">
            <td className={tdCls}>Total dough</td>
            <td className={cn(tdCls, 'text-right')}>{fmtPct(t.total_pct, 2)}</td>
            <td className={cn(tdCls, 'text-right')}>{fmtQty(t.total_g, 'g')}</td>
            <td className={cn(tdCls, 'text-right')}>{fmtQty(t.total_qty, u)}</td>
            {showCost && <td className={cn(tdCls, 'text-right')}>{fmtMoney(calc.cost.batch)}{!calc.cost.complete && <span className="text-warning"> *</span>}</td>}
          </tr>
          {t.flour_g > 0 && (
            <tr className="text-xs text-muted-foreground">
              <td className={cn(tdCls, 'whitespace-normal')} colSpan={2}>
                Overall formula: flour 100% · water {fmtPct(t.hydration_pct)}{t.prefermented_flour_pct !== null && <> · pre-fermented flour {fmtPct(t.prefermented_flour_pct)}</>}
              </td>
              <td className={cn(tdCls, 'text-right')}>flour {fmtQty(t.flour_g, 'g')}</td>
              <td className={cn(tdCls, 'text-right')}>flour {fmtQty(t.flour_qty, u)}</td>
              {showCost && <td className={tdCls} />}
            </tr>
          )}
        </tfoot>
      </table>
    </div>
  );
}

/** Summary figures: dough, flour, hydration, yield (part 'dough'), cost (part 'cost'), or both. */
export function SummaryList({ calc, part = 'all' }: { calc: Calc; part?: 'all' | 'dough' | 'cost' }) {
  const t = calc.totals;
  const u = calc.out_unit;
  const rows: [string, string][] = [
    ['Total dough', fmtQty(t.total_qty, u)],
    ['Total flour', fmtQty(t.flour_qty, u)],
    ['Hydration', fmtPct(t.hydration_pct)],
  ];
  if (t.prefermented_flour_pct !== null) rows.push(['Pre-fermented flour', fmtPct(t.prefermented_flour_pct)]);
  rows.push(['Dough loss', fmtPct(t.loss_pct)]);
  if (t.piece_weight_g !== null) rows.push([`Pieces of ${fmtQty(t.piece_weight_qty, u)}`, fmtNum(t.pieces, 0)]);
  const cost: [string, string][] = [
    ['Cost per batch', fmtMoney(calc.cost.batch)],
    ['Cost per kg dough', fmtMoney(calc.cost.per_kg)],
    ['Cost per lb dough', fmtMoney(calc.cost.per_lb)],
  ];
  if (calc.cost.per_piece !== null) cost.push(['Cost per piece', fmtMoney(calc.cost.per_piece)]);
  return (
    <dl className="grid grid-cols-[1fr_auto] gap-x-3 gap-y-1 px-3 py-2.5 text-sm">
      {part !== 'cost' && rows.map(([k, v]) => <Row key={k} k={k} v={v} />)}
      {part === 'all' && <div className="col-span-2 my-1 border-t" />}
      {part !== 'dough' && cost.map(([k, v]) => <Row key={k} k={k} v={v} />)}
      {part !== 'dough' && !calc.cost.complete && (
        <p className="col-span-2 text-xs text-warning">* {calc.cost.missing_count} ingredient{calc.cost.missing_count === 1 ? ' has' : 's have'} no price; cost is incomplete.</p>
      )}
    </dl>
  );
}
function Row({ k, v }: { k: string; v: string }) {
  return <><dt className="text-muted-foreground">{k}</dt><dd className="text-right font-semibold tabular-nums">{v}</dd></>;
}

/** Cost of each line for this batch, with the batch total. */
export function CostTable({ calc }: { calc: Calc }) {
  const u = calc.out_unit;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead><tr><th className={thCls}>Ingredient</th><th className={cn(thCls, 'text-right')}>Scaled</th><th className={cn(thCls, 'text-right')}>Cost</th></tr></thead>
        <tbody>
          {calc.lines.map((l) => (
            <tr key={l.line_no} className="hover:bg-muted/40">
              <td className={tdCls}>{l.name}</td>
              <td className={cn(tdCls, 'text-right')}>{fmtQty(l.scaled_qty, u)}</td>
              <td className={cn(tdCls, 'text-right')}>{l.scaled_cost === null ? <span className="text-warning">No price</span> : fmtMoney(l.scaled_cost)}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="bg-muted/30 font-semibold">
            <td className={tdCls}>Batch</td>
            <td className={cn(tdCls, 'text-right')}>{fmtQty(calc.totals.total_qty, u)}</td>
            <td className={cn(tdCls, 'text-right')}>{fmtMoney(calc.cost.batch)}{!calc.cost.complete && <span className="text-warning"> *</span>}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}

export function AllergenList({ calc }: { calc: Calc }) {
  return (
    <div className="flex flex-wrap gap-1.5 px-3 py-2.5">
      {calc.allergens.length === 0
        ? <span className="text-sm text-muted-foreground">None from the ingredients.</span>
        : calc.allergens.map((a) => <Pill key={a.code} dot="bg-warning">{a.label}</Pill>)}
    </div>
  );
}

/** Each sub-recipe to make first, scaled to this batch. */
export function MakeFirstTable({ m, unit }: { m: Calc['make_first'][number]; unit: Calc['out_unit'] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead><tr><th className={thCls}>Ingredient</th><th className={cn(thCls, 'text-right')}>%</th><th className={cn(thCls, 'text-right')}>Scaled</th></tr></thead>
        <tbody>
          {m.lines.map((l) => (
            <tr key={l.line_no} className="hover:bg-muted/40">
              <td className={tdCls}>{l.name}</td>
              <td className={cn(tdCls, 'text-right')}>{fmtPct(l.bakers_pct, 2)}</td>
              <td className={cn(tdCls, 'text-right font-semibold')}>{fmtQty(l.scaled_qty, unit)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function StepList({ steps }: { steps: Step[] }) {
  if (steps.length === 0) return <p className="px-3 py-2.5 text-sm text-muted-foreground">No method steps yet.</p>;
  return (
    <ol>
      {steps.map((s, i) => (
        <li key={i} className="grid grid-cols-[1.5rem_5.5rem_minmax(0,1fr)_5rem_4.5rem] items-baseline gap-2 border-t px-3 py-1.5 text-sm first:border-t-0 max-sm:grid-cols-[1.5rem_minmax(0,1fr)_4.5rem]">
          <span className="font-semibold text-muted-foreground">{i + 1}</span>
          <span className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground max-sm:col-span-2">{s.step_type}</span>
          <span className="whitespace-pre-line max-sm:col-span-2 max-sm:col-start-2">{s.instruction}</span>
          <span className="text-right tabular-nums">{fmtMinutes(s.duration_min)}</span>
          <span className="text-right tabular-nums">{s.temperature_f !== null ? `${fmtNum(s.temperature_f, 1)} °F` : ''}</span>
        </li>
      ))}
    </ol>
  );
}

export function StatementBlock({ text }: { text: string | null }) {
  const copy = () => { if (text) void navigator.clipboard?.writeText(text).catch(() => undefined); };
  return (
    <Panel title="Ingredient statement" sub="by weight, for Nutrition Labels"
      action={<Button size="sm" variant="outline" className="h-7 gap-1" disabled={!text} onClick={copy}><Copy className="h-3.5 w-3.5" />Copy</Button>}>
      <p className="px-3 py-2.5 text-sm text-muted-foreground">{text ?? '–'}</p>
    </Panel>
  );
}
