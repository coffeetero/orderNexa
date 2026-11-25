/**
 * Theme derivation (ported from myQ): the 11 seeds of one theme variant → an intermediate token set, which tokens.ts maps onto BPS's
 * shadcn tokens. Pure.
 *
 * Intermediate tokens (Claude Code seed → token):
 *   surface-0      → --bg, --panel-body (page background)            surface-1 → --panel-left (left panel / sidebar)
 *   surface-2      → --surface, --panel-raised (cards, dialogs, slide-out panels); --surface-2 (sunken) = surface-2 ⅔ toward surface-0 … see below
 *   text-primary   → --text (+ borders, hover, dividers, shadows are mixed from text over the surfaces)
 *   text-secondary → --text-2        text-muted → --text-3          --text-disabled = text ½ toward surface-2
 *   accent         → --accent, -hover, -active, -fg (on-accent), -soft, -soft-fg, -border, --surface-selected, --focus
 *   success        → --positive (+ soft, border)  → money in          danger → --negative, --danger (+ hover, fg, soft, border) → money out
 *   warning        → --warning (+ soft, border)    pro → --info (+ soft, border)
 * Missing seeds: surface-1 = surface-0 shifted 2.5–3 % lightness; surface-2 = surface-0 70 % toward white (light) or +5 % lightness (dark);
 * text-secondary / text-muted = text 25 % / 40 % toward surface-0; roles fall back to the Bakery theme's colours.
 *
 * Checks, in this order (each change is listed in `fixes`, shown as "Adjusted N colours for readability"):
 *   1. Money hue: success must look green (hue 75°–175°, saturation ≥ 25 %), danger red (hue ≥ 335° or ≤ 25°, saturation ≥ 35 %). Otherwise the
 *      hue is replaced (green 145°, red 4°), saturation raised to at least 45 % / 55 %, lightness kept within 25–75 %.
 *   2. WCAG AA: text, secondary and muted text, accent (links), money, warning and info colours reach 4.5:1 on every surface they sit on (page,
 *      left panel, cards, sunken areas, and their own soft background); on-accent / on-danger text 4.5:1 on the fill; input borders and the
 *      focus ring 3:1 (UI parts). A failing colour keeps its hue and moves in lightness (away from the surfaces) until it passes.
 */
import { AA_TEXT, AA_UI, contrast, ensureContrast, fromHsl, mix, onColor, rgba, shiftLightness, toHsl } from './color';
import { BAKERY_THEME, type ThemeMode, type ThemeSeeds } from './themes';

/** Intermediate tokens produced by the derivation. Fonts, spacing and charts are never themed. */
export const THEME_TOKENS = [
  '--bg', '--surface', '--surface-2', '--surface-3', '--surface-hover', '--surface-selected',
  '--panel-body', '--panel-left', '--panel-raised',
  '--border', '--border-strong', '--border-input', '--divider',
  '--text', '--text-2', '--text-3', '--text-disabled', '--text-inverse',
  '--accent', '--accent-hover', '--accent-active', '--accent-fg', '--accent-soft', '--accent-soft-fg', '--accent-border',
  '--positive', '--positive-soft', '--positive-border', '--negative', '--negative-soft', '--negative-border', '--warning', '--warning-soft', '--warning-border',
  '--danger', '--danger-hover', '--danger-fg', '--danger-soft', '--danger-border', '--info', '--info-soft', '--info-border',
  '--focus', '--scrim', '--shadow-1', '--shadow-2', '--shadow-3',
] as const;
export type ThemeToken = (typeof THEME_TOKENS)[number];
export type TokenMap = Record<ThemeToken, string>;

// ------------------------------------------------------------------ money hue check
export type MoneyKind = 'positive' | 'negative';
/** Is the hue clearly green-ish (positive) or red-ish (negative)? */
export function moneyHueOk(hex: string, kind: MoneyKind): boolean {
  const [h, s] = toHsl(hex);
  return kind === 'positive' ? h >= 75 && h <= 175 && s >= 0.25 : (h >= 335 || h <= 25) && s >= 0.35;
}
/** The money colour with its hue corrected when it is not clearly green / red (lightness kept within 25–75 %). */
export function fixMoneyHue(hex: string, kind: MoneyKind): { color: string; changed: boolean } {
  if (moneyHueOk(hex, kind)) return { color: hex.toLowerCase(), changed: false };
  const [, s, l] = toHsl(hex);
  return kind === 'positive'
    ? { color: fromHsl(145, Math.max(s, 0.45), Math.min(0.75, Math.max(0.25, l))), changed: true }
    : { color: fromHsl(4, Math.max(s, 0.55), Math.min(0.75, Math.max(0.25, l))), changed: true };
}

// ------------------------------------------------------------------ derivation
export interface Fix { token: ThemeToken; from: string; to: string; reason: 'contrast' | 'money-hue' }
export interface DerivedTheme { tokens: TokenMap; /** the variant shown */ mode: ThemeMode; fixes: Fix[] }
const W = '#ffffff', B = '#000000';

export function deriveSeeds(seeds: ThemeSeeds, dark: boolean): { tokens: TokenMap; fixes: Fix[] } {
  const fallback = BAKERY_THEME.inputs[dark ? 'dark' : 'light']!;
  const fixes: Fix[] = [];
  const fix = (token: ThemeToken, fg: string, bgs: string[], min: number): string => {
    const r = ensureContrast(fg, bgs, min);
    if (r.changed) fixes.push({ token, from: fg.toLowerCase(), to: r.color, reason: 'contrast' });
    return r.color;
  };
  const s0 = seeds['surface-0'];
  const s1 = seeds['surface-1'] ?? shiftLightness(s0, dark ? 0.03 : -0.025);
  const s2 = seeds['surface-2'] ?? (dark ? shiftLightness(s0, 0.05) : mix(s0, W, 0.7));
  const sunken = mix(s2, s0, 0.65);
  const surface3 = mix(s0, seeds['text-primary'], dark ? 0.08 : 0.05);
  const surfaces = [s0, s1, s2, sunken];
  const t0 = seeds['text-primary'];

  const text = fix('--text', t0, [...surfaces, surface3], AA_TEXT);
  const text2 = fix('--text-2', seeds['text-secondary'] ?? mix(text, s0, 0.25), [...surfaces, surface3], AA_TEXT);
  const text3 = fix('--text-3', seeds['text-muted'] ?? mix(text, s0, 0.4), surfaces, AA_TEXT);

  const accent = fix('--accent', seeds.accent ?? fallback.accent!, surfaces, AA_TEXT);
  const accentSoft = (dark ? mix(s0, accent, 0.16) : mix(s2, accent, 0.1));
  const accentFg = fix('--accent-fg', onColor(accent, W, dark ? mix(accent, B, 0.85) : '#111111'), [accent], AA_TEXT);

  const role = (token: '--positive' | '--negative' | '--warning' | '--info', seed: string, money?: MoneyKind) => {
    let c = seed.toLowerCase();
    if (money) { const m = fixMoneyHue(c, money); if (m.changed) { fixes.push({ token, from: c, to: m.color, reason: 'money-hue' }); c = m.color; } }
    const soft = dark ? mix(s0, c, 0.14) : mix(s2, c, 0.1);
    const color = fix(token, c, [...surfaces, soft], AA_TEXT);
    return { color, soft, border: mix(s2, color, dark ? 0.45 : 0.35) };
  };
  const pos = role('--positive', seeds.success ?? fallback.success!, 'positive');
  const neg = role('--negative', seeds.danger ?? fallback.danger!, 'negative');
  const warn = role('--warning', seeds.warning ?? fallback.warning!);
  const info = role('--info', seeds.pro ?? fallback.pro!);
  const dangerFg = fix('--danger-fg', onColor(neg.color, W, dark ? mix(neg.color, B, 0.85) : '#111111'), [neg.color], AA_TEXT);

  const shadowInk = mix(t0, B, 0.3);
  const tokens: TokenMap = {
    '--bg': s0, '--surface': s2, '--surface-2': sunken, '--surface-3': surface3,
    '--surface-hover': mix(s2, text, dark ? 0.06 : 0.04), '--surface-selected': mix(s2, accent, dark ? 0.22 : 0.12),
    '--panel-body': s0, '--panel-left': s1, '--panel-raised': s2,
    '--border': mix(s2, text, dark ? 0.14 : 0.12), '--border-strong': mix(s2, text, dark ? 0.26 : 0.24),
    '--border-input': fix('--border-input', mix(s2, text, 0.55), [s2], AA_UI), '--divider': mix(s2, text, dark ? 0.08 : 0.07),
    '--text': text, '--text-2': text2, '--text-3': text3, '--text-disabled': mix(text, s2, 0.5), '--text-inverse': dark ? s0 : s2,
    '--accent': accent, '--accent-hover': shiftLightness(accent, dark ? 0.06 : -0.06), '--accent-active': shiftLightness(accent, dark ? 0.12 : -0.11),
    '--accent-fg': accentFg, '--accent-soft': accentSoft,
    '--accent-soft-fg': fix('--accent-soft-fg', shiftLightness(accent, dark ? 0.1 : -0.06), [accentSoft], AA_TEXT), '--accent-border': mix(s2, accent, dark ? 0.45 : 0.4),
    '--positive': pos.color, '--positive-soft': pos.soft, '--positive-border': pos.border,
    '--negative': neg.color, '--negative-soft': neg.soft, '--negative-border': neg.border,
    '--warning': warn.color, '--warning-soft': warn.soft, '--warning-border': warn.border,
    '--danger': neg.color, '--danger-hover': shiftLightness(neg.color, dark ? 0.06 : -0.07), '--danger-fg': dangerFg, '--danger-soft': neg.soft, '--danger-border': neg.border,
    '--info': info.color, '--info-soft': info.soft, '--info-border': info.border,
    '--focus': fix('--focus', accent, [s0, s2], AA_UI),
    '--scrim': dark ? 'rgba(0,0,0,.6)' : rgba(mix(t0, B, 0.4), 0.5),
    '--shadow-1': dark ? '0 1px 2px rgba(0,0,0,.4)' : `0 1px 2px ${rgba(shadowInk, 0.06)},0 1px 1px ${rgba(shadowInk, 0.04)}`,
    '--shadow-2': dark ? '0 4px 14px rgba(0,0,0,.45)' : `0 4px 12px ${rgba(shadowInk, 0.08)},0 1px 3px ${rgba(shadowInk, 0.06)}`,
    '--shadow-3': dark ? '0 20px 50px rgba(0,0,0,.6)' : `0 18px 48px ${rgba(shadowInk, 0.22)},0 4px 12px ${rgba(shadowInk, 0.1)}`,
  };
  return { tokens, fixes };
}

/** "Adjusted 3 colours for readability" (null when nothing was adjusted). */
export function fixesMessage(fixes: Fix[]): string | null {
  const n = new Set(fixes.map((f) => f.token)).size;
  return n ? `Adjusted ${n} colour${n === 1 ? '' : 's'} for readability` : null;
}
/** All 11 seeds of a variant (for the colour editor): missing ones filled with what the derivation would use. */
export function completeSeeds(seeds: ThemeSeeds, dark: boolean): Required<ThemeSeeds> {
  const fb = BAKERY_THEME.inputs[dark ? 'dark' : 'light']!;
  const t = deriveSeeds(seeds, dark).tokens;
  return {
    accent: seeds.accent ?? fb.accent!, danger: seeds.danger ?? fb.danger!, success: seeds.success ?? fb.success!, warning: seeds.warning ?? fb.warning!, pro: seeds.pro ?? fb.pro!,
    'surface-0': seeds['surface-0'], 'surface-1': seeds['surface-1'] ?? t['--panel-left'], 'surface-2': seeds['surface-2'] ?? t['--panel-raised'],
    'text-primary': seeds['text-primary'], 'text-secondary': seeds['text-secondary'] ?? mix(seeds['text-primary'], seeds['surface-0'], 0.25), 'text-muted': seeds['text-muted'] ?? mix(seeds['text-primary'], seeds['surface-0'], 0.4),
  };
}
/** The worst text contrast of a token map (for tests and the editor). */
export const textContrast = (t: TokenMap): number => Math.min(...[t['--bg'], t['--panel-left'], t['--surface'], t['--surface-2']].map((s) => contrast(t['--text'], s)));
