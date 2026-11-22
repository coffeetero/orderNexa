/**
 * Colour math for themes (Phase 19): hex parsing, mixing, HSL, and the WCAG 2.x contrast ratio with an automatic readability fix.
 * Pure: no DOM, no storage. Every colour here is a six-digit "#rrggbb" string (lower case on output).
 */
export type Rgb = [number, number, number];
export const HEX6 = /^#[0-9a-fA-F]{6}$/;
export const isHex = (v: unknown): v is string => typeof v === 'string' && HEX6.test(v);

export function parseHex(hex: string): Rgb {
  if (!isHex(hex)) throw new Error('Not a #rrggbb colour: ' + hex);
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
const clamp = (v: number, lo = 0, hi = 255) => Math.min(hi, Math.max(lo, v));
export const toHex = ([r, g, b]: Rgb): string => '#' + [r, g, b].map((v) => Math.round(clamp(v)).toString(16).padStart(2, '0')).join('');
/** `a` mixed with `b`: t = 0 gives a, t = 1 gives b (sRGB, like CSS color-mix in srgb). */
export function mix(a: string, b: string, t: number): string {
  const x = parseHex(a), y = parseHex(b);
  return toHex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]);
}
/** "rgba(r,g,b,a)" of a hex colour (shadows, scrim). */
export const rgba = (hex: string, a: number): string => { const [r, g, b] = parseHex(hex); return `rgba(${r},${g},${b},${a})`; };

// ------------------------------------------------------------------ HSL (h in degrees 0..360, s and l 0..1)
export function toHsl(hex: string): [number, number, number] {
  const [r, g, b] = parseHex(hex).map((v) => v / 255) as Rgb;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h *= 60;
  return [h, s, l];
}
export function fromHsl(h: number, s: number, l: number): string {
  h = ((h % 360) + 360) % 360; s = clamp(s, 0, 1); l = clamp(l, 0, 1);
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return toHex([(r + m) * 255, (g + m) * 255, (b + m) * 255]);
}
/** The same hue and saturation with lightness moved by `dl` (-1..1). */
export const shiftLightness = (hex: string, dl: number): string => { const [h, s, l] = toHsl(hex); return fromHsl(h, s, l + dl); };

// ------------------------------------------------------------------ WCAG 2.x
/** Relative luminance (WCAG 2.x definition, sRGB). */
export function luminance(hex: string): number {
  const [r, g, b] = parseHex(hex).map((v) => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; }) as Rgb;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
/** Contrast ratio 1..21. */
export function contrast(a: string, b: string): number {
  const la = luminance(a), lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}
/** WCAG AA: 4.5:1 for normal text, 3:1 for large text and UI parts (borders of inputs, focus rings, icons). */
export const AA_TEXT = 4.5;
export const AA_UI = 3;
export const isDarkColor = (hex: string): boolean => luminance(hex) < 0.18;

/**
 * Readability fix: `fg` against every colour of `bgs` must reach `min`. When it does not, its HSL lightness moves in small steps away from the
 * backgrounds (darker on light surfaces, lighter on dark ones), keeping its hue, until all pass. If even black/white cannot pass on one side,
 * the other direction is tried; the best found is returned. `changed` says whether the colour was adjusted.
 */
export function ensureContrast(fg: string, bgs: string[], min: number): { color: string; changed: boolean } {
  const worst = (c: string) => Math.min(...bgs.map((b) => contrast(c, b)));
  if (worst(fg) >= min) return { color: fg.toLowerCase(), changed: false };
  const avgLum = bgs.reduce((s, b) => s + luminance(b), 0) / bgs.length;
  const firstDir = avgLum > 0.18 ? -1 : 1;
  let best = fg, bestScore = worst(fg);
  for (const dir of [firstDir, -firstDir]) {
    const [h, s, l0] = toHsl(fg);
    for (let i = 1; i <= 100; i++) {
      const l = l0 + dir * i * 0.01;
      if (l < 0 || l > 1) break;
      const c = fromHsl(h, s, l); const score = worst(c);
      if (score > bestScore) { best = c; bestScore = score; }
      if (score >= min) return { color: c, changed: true };
    }
  }
  return { color: best, changed: best.toLowerCase() !== fg.toLowerCase() };
}
/** Black-ish or white-ish, whichever reads better on `bg` (text on a filled button). */
export function onColor(bg: string, light = '#ffffff', dark = '#111111'): string {
  return contrast(light, bg) >= contrast(dark, bg) ? light : dark;
}

/** "H S% L%" (the triplet shadcn/Tailwind tokens use inside `hsl(var(--x))`), e.g. "24 55% 32%". */
export function hslTriplet(hex: string): string {
  const [h, s, l] = toHsl(hex);
  const r = (v: number) => Math.round(v * 10) / 10;
  return `${r(h)} ${r(s * 100)}% ${r(l * 100)}%`;
}
