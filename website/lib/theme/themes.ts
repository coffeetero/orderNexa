/**
 * Themes (ported from myQ's Appearance work). A theme is DATA ONLY: the colour input shape of Claude Code themes (`makeColors` input):
 * `{ v: 1, id, label, inputs: { light?: Seeds, dark?: Seeds } }`, each mode 11 six-digit hex seeds. BPS never runs theme code (an imported
 * file is read as text; see github.ts) and keeps nothing but these colours.
 *
 * Themes come IN ADDITION to Light / Dark / Follow system: that choice picks the variant; a theme with only one variant always shows that one.
 */
import { isHex } from './color';
import { CURATED_THEMES } from './catalog';

export const SEED_KEYS = ['accent', 'danger', 'success', 'warning', 'pro', 'surface-0', 'surface-1', 'surface-2', 'text-primary', 'text-secondary', 'text-muted'] as const;
export type SeedKey = (typeof SEED_KEYS)[number];
/** `surface-0` and `text-primary` are required; the rest are derived when missing. */
export type ThemeSeeds = Partial<Record<SeedKey, string>> & { 'surface-0': string; 'text-primary': string };
export type ThemeMode = 'light' | 'dark';
export interface ThemeDef { v: 1; id: string; label: string; inputs: { light?: ThemeSeeds; dark?: ThemeSeeds }; /** where it came from (an imported GitHub URL), shown only */ source?: string }

export const SEED_LABEL: Record<SeedKey, string> = {
  accent: 'Accent (buttons, links)', danger: 'Danger (errors)', success: 'Success', warning: 'Warning', pro: 'Secondary (info)',
  'surface-0': 'Page background', 'surface-1': 'Sidebar and tables', 'surface-2': 'Cards and panels', 'text-primary': 'Text', 'text-secondary': 'Secondary text', 'text-muted': 'Muted text',
};
export const LABEL_MAX = 60;
export const CUSTOM_LIMIT = 20;

/*
 * Built-in themes. Palette inspirations (colours re-picked by hand, names neutral):
 * - Bakery: BPS's own colours (globals.css), the default; its tokens are pinned to today's exact values (tokens.ts BAKERY_TOKENS).
 * - Clay: inspired by Anthropic's Claude look (warm ivory paper, clay/terracotta accent).
 * - High contrast: accessibility (black on white / white on black, saturated roles; well past WCAG AAA for body text).
 * - Sepia: warm paper, inspired by e-reader sepia modes.
 */
export const BAKERY_ID = 'bakery';
export const BUILTIN_THEMES: ThemeDef[] = [
  { v: 1, id: BAKERY_ID, label: 'Bakery', inputs: {
    light: { accent: '#7e4925', danger: '#dc2828', success: '#059467', warning: '#db7706', pro: '#0284c5', 'surface-0': '#faf8f5', 'surface-1': '#efebe7', 'surface-2': '#f6f3ee', 'text-primary': '#251d18', 'text-secondary': '#3d3129', 'text-muted': '#8d7768' },
    dark: { accent: '#cca35c', danger: '#d54444', success: '#36d399', warning: '#fbbd23', pro: '#38bdfa', 'surface-0': '#1e1915', 'surface-1': '#342d27', 'surface-2': '#29231e', 'text-primary': '#f0ece6', 'text-secondary': '#e2dbcf', 'text-muted': '#a49784' },
  } },
  { v: 1, id: 'clay', label: 'Clay', inputs: {
    light: { accent: '#ac4f2d', danger: '#b3392f', success: '#2c764a', warning: '#8b5f0e', pro: '#6d4f94', 'surface-0': '#f5f4ee', 'surface-1': '#eeebe1', 'surface-2': '#fffdf8', 'text-primary': '#29261b', 'text-secondary': '#4f4b3f', 'text-muted': '#655f52' },
    dark: { accent: '#da7a5b', danger: '#f3978b', success: '#6cc58e', warning: '#e6b45a', pro: '#bda7e3', 'surface-0': '#1f1e1b', 'surface-1': '#262522', 'surface-2': '#2d2c28', 'text-primary': '#f0eee6', 'text-secondary': '#c9c5b8', 'text-muted': '#a8a294' },
  } },
  { v: 1, id: 'high-contrast', label: 'High contrast', inputs: {
    light: { accent: '#0040c0', danger: '#b00000', success: '#006b21', warning: '#7a4a00', pro: '#5a2a9a', 'surface-0': '#ffffff', 'surface-1': '#f0f0f0', 'surface-2': '#ffffff', 'text-primary': '#000000', 'text-secondary': '#1a1a1a', 'text-muted': '#333333' },
    dark: { accent: '#7fb2ff', danger: '#ff8a8a', success: '#5ee08a', warning: '#ffd166', pro: '#c9a8ff', 'surface-0': '#000000', 'surface-1': '#0d0d0d', 'surface-2': '#141414', 'text-primary': '#ffffff', 'text-secondary': '#f0f0f0', 'text-muted': '#d6d6d6' },
  } },
  { v: 1, id: 'sepia', label: 'Sepia', inputs: {
    light: { accent: '#83532a', danger: '#a3321f', success: '#4b6a27', warning: '#835800', pro: '#6a4a7a', 'surface-0': '#f4ecd8', 'surface-1': '#ece1c7', 'surface-2': '#fbf6ea', 'text-primary': '#3b2f20', 'text-secondary': '#594934', 'text-muted': '#6a5943' },
    dark: { accent: '#d4a46a', danger: '#ea9787', success: '#a6c27a', warning: '#e0b45c', pro: '#c3a3d6', 'surface-0': '#221c14', 'surface-1': '#2a2219', 'surface-2': '#31291e', 'text-primary': '#eadfc8', 'text-secondary': '#cfc1a5', 'text-muted': '#b0a286' },
  } },
];
/** Ready-made themes: the built-in ones plus the curated catalog (catalog.ts). Neither can be edited or deleted; copy one to change it. */
export const PRESET_THEMES: ThemeDef[] = [...BUILTIN_THEMES, ...CURATED_THEMES];
export const isBuiltinId = (id: string): boolean => PRESET_THEMES.some((t) => t.id === id);
export const isCuratedId = (id: string): boolean => CURATED_THEMES.some((t) => t.id === id);
export const findTheme = (id: string, custom: ThemeDef[] = []): ThemeDef | undefined => PRESET_THEMES.find((t) => t.id === id) ?? custom.find((t) => t.id === id);
export const DEFAULT_THEME = BUILTIN_THEMES[0]!;

/** The variant shown for a wanted mode: that mode, else the theme's only one. */
export function variantOf(theme: ThemeDef, want: ThemeMode): { seeds: ThemeSeeds; mode: ThemeMode } {
  const s = theme.inputs[want];
  if (s) return { seeds: s, mode: want };
  const other: ThemeMode = want === 'dark' ? 'light' : 'dark';
  return { seeds: theme.inputs[other] ?? DEFAULT_THEME.inputs[want]!, mode: theme.inputs[other] ? other : want };
}

// ------------------------------------------------------------------ validation (saved and imported themes are untrusted data)
const isStr = (v: unknown, max: number): v is string => typeof v === 'string' && v.length <= max;
/** Seeds of one mode: only the 11 known keys with #rrggbb values (lower-cased); null without both required seeds. */
export function readSeeds(v: unknown): ThemeSeeds | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const o = v as Record<string, unknown>; const out: Partial<Record<SeedKey, string>> = {};
  for (const k of SEED_KEYS) if (isHex(o[k])) out[k] = (o[k] as string).toLowerCase();
  return out['surface-0'] && out['text-primary'] ? (out as ThemeSeeds) : null;
}
export const cleanLabel = (s: string): string => s.replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, LABEL_MAX);
export const SAFE_ID = /^[A-Za-z0-9_.:-]{1,80}$/;
export function readTheme(v: unknown): ThemeDef | null {
  if (!v || typeof v !== 'object') return null;
  const o = v as Record<string, unknown>;
  const inputs = (o.inputs && typeof o.inputs === 'object' ? o.inputs : {}) as Record<string, unknown>;
  const light = readSeeds(inputs.light), dark = readSeeds(inputs.dark);
  if (!light && !dark) return null;
  const id = isStr(o.id, 80) && SAFE_ID.test(o.id) ? o.id : null;
  const label = isStr(o.label, 200) ? cleanLabel(o.label) : '';
  if (!id || !label) return null;
  const out: ThemeDef = { v: 1, id, label, inputs: {} };
  if (light) out.inputs.light = light;
  if (dark) out.inputs.dark = dark;
  if (isStr(o.source, 400) && /^https:\/\/(github\.com|raw\.githubusercontent\.com|api\.github\.com)\//.test(o.source)) out.source = o.source;
  return out;
}
let seq = 0;
export const newThemeId = (): string => 'user-' + (globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${++seq}`);
/** A user copy of a theme (both modes), to edit by hand. */
export const copyTheme = (t: ThemeDef, label = 'My theme'): ThemeDef => ({ v: 1, id: newThemeId(), label, inputs: JSON.parse(JSON.stringify(t.inputs)) as ThemeDef['inputs'] });
