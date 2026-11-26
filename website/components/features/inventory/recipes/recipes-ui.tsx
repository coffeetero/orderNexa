'use client';

import { cn } from '@/lib/utils';

export type Unit = 'g' | 'kg' | 'oz' | 'lb';
export type RecipeType = 'DOUGH' | 'PREFERMENT' | 'OTHER';
export type Role = 'FLOUR' | 'LIQUID' | 'OTHER';
export type ScaleMode = 'BATCHES' | 'DOUGH' | 'FLOUR' | 'PIECES';

export const UNITS: Unit[] = ['g', 'kg', 'lb', 'oz'];
export const RECIPE_TYPES: { key: RecipeType; label: string }[] = [
  { key: 'DOUGH', label: 'Dough' }, { key: 'PREFERMENT', label: 'Pre-ferment' }, { key: 'OTHER', label: 'Other' },
];
export const ROLES: { key: Role; label: string }[] = [
  { key: 'FLOUR', label: 'Flour' }, { key: 'LIQUID', label: 'Liquid' }, { key: 'OTHER', label: 'Other' },
];
export const STEP_TYPES = ['PREP', 'MIX', 'BULK', 'DIVIDE', 'SHAPE', 'PROOF', 'BAKE', 'COOL', 'FINISH', 'OTHER'] as const;
export const ALLERGENS = [
  ['milk', 'Milk'], ['egg', 'Egg'], ['fish', 'Fish'], ['shellfish', 'Crustacean shellfish'], ['tree_nuts', 'Tree nuts'],
  ['peanuts', 'Peanuts'], ['wheat', 'Wheat'], ['soy', 'Soy'], ['sesame', 'Sesame'],
] as const;
export const SCALE_MODES: { key: ScaleMode; label: string }[] = [
  { key: 'BATCHES', label: 'Batches' }, { key: 'DOUGH', label: 'Dough weight' }, { key: 'FLOUR', label: 'Flour weight' }, { key: 'PIECES', label: 'Pieces' },
];

/** The recipe as saved / edited (inv_recipe_json). */
export interface RecipeJson {
  recipe_id?: number | null; recipe_name: string; recipe_type: RecipeType; dough_code: string | null; item_id: number | null;
  piece_weight: number | null; piece_unit: Unit; loss_pct: number; ddt_f: number | null; friction_f: number | null;
  display_unit: Unit; notes: string | null; version_no?: number; is_active: boolean;
  lines: { ingredient_id: number | null; sub_recipe_id: number | null; quantity: number; unit: Unit; note: string | null }[];
  steps: Step[];
}
export interface Step { step_type: string; instruction: string; duration_min: number | null; temperature_f: number | null }

export interface CalcLine {
  line_no: number; kind: 'INGREDIENT' | 'RECIPE'; ingredient_id: number | null; sub_recipe_id: number | null; name: string;
  role: Role | null; recipe_type: RecipeType | null; quantity: number; unit: Unit; note: string | null; grams: number;
  bakers_pct: number | null; scaled_qty: number; cost: number | null; scaled_cost: number | null;
}
export interface MakeFirst { recipe_id: number; recipe_name: string; recipe_type: RecipeType; scaled_qty: number; hydration_pct: number | null; lines: CalcLine[]; steps: Step[] }
/** Every figure the screen shows (inv_recipe_calc). */
export interface Calc {
  mode: ScaleMode; factor: number; out_unit: Unit; lines: CalcLine[];
  totals: {
    total_g: number; total_qty: number; flour_g: number; flour_qty: number; liquid_g: number; liquid_qty: number;
    total_pct: number | null; hydration_pct: number | null; prefermented_flour_pct: number | null; loss_pct: number;
    after_loss_qty: number; piece_weight_g: number | null; piece_weight_qty: number | null; pieces: number | null; base_pieces: number | null;
  };
  cost: { batch: number; base_batch: number; per_kg: number | null; per_lb: number | null; per_piece: number | null; missing_count: number; complete: boolean };
  allergens: { code: string; label: string }[]; ingredient_statement: string | null;
  water: { ddt_f: number | null; friction_f: number | null; multiplier: number; has_preferment: boolean; room_f: number | null;
           flour_f: number | null; preferment_f: number | null; water_f: number | null };
  make_first: MakeFirst[]; steps: Step[]; total_minutes: number | null; issues: string[];
}
export interface RecipeDetail {
  recipe: RecipeJson & { recipe_id: number; version_no: number }; calc: Calc;
  item: { item_id: number; item_number: string; item_name: string } | null;
  saved_on: string; saved_by_name: string | null;
  versions: { version_no: number; change_note: string | null; saved_on: string; saved_by_name: string | null }[];
  used_by_items: { item_id: number; item_number: string; item_name: string; unit_of_sale: string; is_active: boolean }[];
  used_in: { recipe_id: number; recipe_name: string }[];
  can_write: boolean; can_delete: boolean;
}
export interface RecipeRow {
  recipe_id: number; recipe_name: string; recipe_type: RecipeType; dough_code: string | null; is_active: boolean; version_no: number;
  total_qty: number; display_unit: Unit; hydration_pct: number | null; line_count: number;
}
export interface Ingredient {
  ingredient_id: number; ingredient_name: string; ingredient_role: Role; cost_amount: number | null; cost_unit: 'kg' | 'lb';
  allergens: string[]; notes: string | null; is_active: boolean; recipe_count: number;
}
export interface Options {
  ingredients: { ingredient_id: number; ingredient_name: string; ingredient_role: Role; is_active: boolean }[];
  recipes: { recipe_id: number; recipe_name: string; recipe_type: RecipeType; is_active: boolean }[];
  items: { item_id: number; item_number: string | null; item_name: string }[];
}
export interface Scale { mode: ScaleMode; value: string; unit: Unit; out_unit: Unit; room_f: string; flour_f: string; preferment_f: string }

/** The scale as the database expects it (inv_recipe_calc p_scale). */
export function scaleJson(s: Scale) {
  const n = (v: string) => (v.trim() === '' ? null : Number(v));
  return { mode: s.mode, value: n(s.value), unit: s.unit, out_unit: s.out_unit, room_f: n(s.room_f), flour_f: n(s.flour_f), preferment_f: n(s.preferment_f) };
}

/** Number formatting only; every figure comes from the database. */
export function fmtNum(v: number | null | undefined, max = 2, min = 0): string {
  if (v === null || v === undefined) return '–';
  return Number(v).toLocaleString('en-US', { minimumFractionDigits: min, maximumFractionDigits: max });
}
export function fmtQty(v: number | null | undefined, unit: Unit): string {
  if (v === null || v === undefined) return '–';
  const d = unit === 'g' ? 1 : unit === 'oz' ? 2 : 3;
  return `${fmtNum(v, d, unit === 'g' ? 0 : unit === 'oz' ? 1 : 2)} ${unit}`;
}
export const fmtPct = (v: number | null | undefined, d = 1) => (v === null || v === undefined ? '–' : `${fmtNum(v, d, d)}%`);
export function fmtMoney(v: number | null | undefined): string {
  if (v === null || v === undefined) return '–';
  const n = Number(v);
  return `${n < 0 ? '-' : ''}$${Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
export function fmtMinutes(m: number | null | undefined): string {
  if (m === null || m === undefined) return '';
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  return m % 60 ? `${h} h ${m % 60} min` : `${h} h`;
}

const TYPE_DOT: Record<RecipeType, string> = { DOUGH: 'bg-primary', PREFERMENT: 'bg-info', OTHER: 'bg-muted-foreground' };
export const typeLabel = (t: RecipeType) => RECIPE_TYPES.find((x) => x.key === t)?.label ?? t;

/** Status-style pill: dot + word. */
export function Pill({ dot, children, className }: { dot: string; children: React.ReactNode; className?: string }) {
  return (
    <span className={cn('inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border px-2 text-xs font-medium text-muted-foreground', className)}>
      <span className={cn('h-1.5 w-1.5 rounded-full', dot)} />{children}
    </span>
  );
}
export function TypePill({ type, active = true }: { type: RecipeType; active?: boolean }) {
  return active ? <Pill dot={TYPE_DOT[type]}>{typeLabel(type)}</Pill> : <Pill dot="bg-border">Archived</Pill>;
}

export const selectCls = 'h-9 w-full rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50';
export const thCls = 'h-8 whitespace-nowrap bg-muted/50 px-3 text-left text-xs font-medium text-muted-foreground';
export const tdCls = 'whitespace-nowrap border-t px-3 py-1.5';
