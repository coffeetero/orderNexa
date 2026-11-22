/**
 * BPS token layer: maps the derivation's intermediate tokens (derive.ts) onto BPS's shadcn/Tailwind tokens and pins the Bakery theme to the
 * exact colours BPS has always used (globals.css), so the default looks identical. Values are HSL triplets ("24 55% 32%") because Tailwind
 * wraps them as `hsl(var(--x))`.
 *
 * Mapping (intermediate → BPS):
 *   --bg → --background            --text → --foreground, --card-foreground, --popover-foreground
 *   --surface → --card, --popover  --panel-left → --muted      --surface-3 → --secondary
 *   --text-3 → --muted-foreground  --accent → --primary (+ --accent-fg → --primary-foreground)
 *   --accent-soft → --accent (shadcn "accent" = hover / selected highlight)   --border → --border   --border-input → --input   --focus → --ring
 *   --danger → --destructive       --positive → --success    --warning → --warning    --info → --info   (each with -foreground and -soft)
 * Never themed: --radius, --chart-1..5, fonts.
 */
import { hslTriplet, onColor } from './color';
import { deriveSeeds, type Fix, type TokenMap } from './derive';
import { BAKERY_ID, variantOf, type ThemeDef, type ThemeMode } from './themes';

export const BPS_TOKENS = [
  '--background', '--foreground', '--card', '--card-foreground', '--popover', '--popover-foreground',
  '--primary', '--primary-foreground', '--secondary', '--secondary-foreground', '--muted', '--muted-foreground',
  '--accent', '--accent-foreground', '--destructive', '--destructive-foreground', '--border', '--input', '--ring',
  '--success', '--success-foreground', '--success-soft', '--warning', '--warning-foreground', '--warning-soft', '--info', '--info-foreground', '--info-soft',
] as const;
export type BpsToken = (typeof BPS_TOKENS)[number];
export type BpsTokenMap = Record<BpsToken, string>;

/** Exactly today's globals.css values, plus the new status tokens (chosen to match the Tailwind emerald / amber / sky shades BPS used). */
export const BAKERY_TOKENS: Record<ThemeMode, BpsTokenMap> = {
  light: {
    '--background': '38 33% 97%', '--foreground': '24 20% 12%', '--card': '36 30% 95%', '--card-foreground': '24 20% 12%',
    '--popover': '36 30% 97%', '--popover-foreground': '24 20% 12%', '--primary': '24 55% 32%', '--primary-foreground': '36 30% 97%',
    '--secondary': '36 25% 88%', '--secondary-foreground': '24 20% 20%', '--muted': '36 20% 92%', '--muted-foreground': '24 15% 48%',
    '--accent': '38 58% 64%', '--accent-foreground': '24 20% 12%', '--destructive': '0 72% 51%', '--destructive-foreground': '36 30% 97%',
    '--border': '36 20% 84%', '--input': '36 20% 84%', '--ring': '24 55% 32%',
    '--success': '161 94% 30%', '--success-foreground': '36 30% 97%', '--success-soft': '160 50% 92%',
    '--warning': '32 95% 44%', '--warning-foreground': '24 20% 12%', '--warning-soft': '40 90% 92%',
    '--info': '200 98% 39%', '--info-foreground': '36 30% 97%', '--info-soft': '200 80% 92%',
  },
  dark: {
    '--background': '24 18% 10%', '--foreground': '36 25% 92%', '--card': '24 16% 14%', '--card-foreground': '36 25% 92%',
    '--popover': '24 16% 12%', '--popover-foreground': '36 25% 92%', '--primary': '38 52% 58%', '--primary-foreground': '24 18% 10%',
    '--secondary': '24 15% 20%', '--secondary-foreground': '36 25% 85%', '--muted': '24 14% 18%', '--muted-foreground': '36 15% 58%',
    '--accent': '38 48% 48%', '--accent-foreground': '24 18% 10%', '--destructive': '0 63% 55%', '--destructive-foreground': '36 25% 92%',
    '--border': '24 14% 22%', '--input': '24 14% 22%', '--ring': '38 52% 58%',
    '--success': '158 64% 52%', '--success-foreground': '24 18% 10%', '--success-soft': '160 40% 15%',
    '--warning': '43 96% 56%', '--warning-foreground': '24 18% 10%', '--warning-soft': '40 50% 15%',
    '--info': '199 95% 60%', '--info-foreground': '24 18% 10%', '--info-soft': '200 50% 17%',
  },
};

/** Maps the derivation's intermediate tokens onto BPS tokens. */
export function toBpsTokens(t: TokenMap): BpsTokenMap {
  const h = hslTriplet;
  return {
    '--background': h(t['--bg']), '--foreground': h(t['--text']),
    '--card': h(t['--surface']), '--card-foreground': h(t['--text']),
    '--popover': h(t['--surface']), '--popover-foreground': h(t['--text']),
    '--primary': h(t['--accent']), '--primary-foreground': h(t['--accent-fg']),
    '--secondary': h(t['--surface-3']), '--secondary-foreground': h(t['--text']),
    '--muted': h(t['--panel-left']), '--muted-foreground': h(t['--text-3']),
    '--accent': h(t['--accent-soft']), '--accent-foreground': h(t['--accent-soft-fg']),
    '--destructive': h(t['--danger']), '--destructive-foreground': h(t['--danger-fg']),
    '--border': h(t['--border']), '--input': h(t['--border-input']), '--ring': h(t['--focus']),
    '--success': h(t['--positive']), '--success-foreground': h(onColor(t['--positive'])), '--success-soft': h(t['--positive-soft']),
    '--warning': h(t['--warning']), '--warning-foreground': h(onColor(t['--warning'])), '--warning-soft': h(t['--warning-soft']),
    '--info': h(t['--info']), '--info-foreground': h(onColor(t['--info'])), '--info-soft': h(t['--info-soft']),
  };
}

export interface DerivedBps { tokens: BpsTokenMap; /** the variant shown */ mode: ThemeMode; fixes: Fix[]; /** intermediate colours (hex), for swatches */ preview: TokenMap | null }

/** The BPS tokens of `theme` for the wanted mode (a single-variant theme gives its one variant, reported in `mode`). */
export function deriveBps(theme: ThemeDef, want: ThemeMode): DerivedBps {
  const { seeds, mode } = variantOf(theme, want);
  if (theme.id === BAKERY_ID) {
    // Pinned tokens; the intermediate set (for swatches) still comes from the seeds.
    return { tokens: { ...BAKERY_TOKENS[mode] }, mode, fixes: [], preview: deriveSeeds(seeds, mode === 'dark').tokens };
  }
  const { tokens, fixes } = deriveSeeds(seeds, mode === 'dark');
  return { tokens: toBpsTokens(tokens), mode, fixes, preview: tokens };
}
