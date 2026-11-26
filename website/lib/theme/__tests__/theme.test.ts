import { readFileSync } from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { applyToDocument, htmlMode, SYSTEM_MODE_SCRIPT, themeCss } from '@/lib/theme/apply';
import { CURATED_THEMES } from '@/lib/theme/catalog';
import { contrast, hslTriplet } from '@/lib/theme/color';
import { textContrast } from '@/lib/theme/derive';
import {
  APPEARANCE_COOKIE, DEFAULT_MODE, cookieValue, readAppearance, readCookie, resolveAppearance, toLocal,
} from '@/lib/theme/prefs';
import {
  BAKERY_ID, BAKERY_THEME, BUILTIN_THEMES, DEFAULT_THEME, HEARTH_ID, PRESET_THEMES, findTheme, isBuiltinId, readTheme, variantOf, type ThemeDef,
} from '@/lib/theme/themes';
import { BAKERY_TOKENS, BPS_TOKENS, deriveBps } from '@/lib/theme/tokens';

const root = path.resolve(__dirname, '../../..');
const globalsCss = readFileSync(path.join(root, 'app/globals.css'), 'utf8');

/** The `--name: value;` declarations inside one rule of globals.css (`:root` or `.dark`). */
function cssVars(selector: string): Record<string, string> {
  const start = globalsCss.indexOf(`${selector} {`);
  const body = globalsCss.slice(start, globalsCss.indexOf('\n  }', start));
  return Object.fromEntries(Array.from(body.matchAll(/(--[a-z0-9-]+):\s*([^;]+);/g)).map((m) => [m[1], m[2].trim()]));
}

describe('Bakery is pinned to the colours BPS has always used', () => {
  it('matches globals.css :root exactly for every token it sets', () => {
    const css = cssVars(':root');
    for (const k of BPS_TOKENS) expect(BAKERY_TOKENS.light[k], `light ${k}`).toBe(css[k]);
  });
  it('matches globals.css .dark exactly', () => {
    const css = cssVars('.dark');
    for (const k of BPS_TOKENS) expect(BAKERY_TOKENS.dark[k], `dark ${k}`).toBe(css[k]);
  });
  it('deriveBps returns the pinned tokens for Bakery', () => {
    expect(deriveBps(BAKERY_THEME, 'light').tokens).toEqual(BAKERY_TOKENS.light);
    expect(deriveBps(BAKERY_THEME, 'dark').tokens).toEqual(BAKERY_TOKENS.dark);
  });
});

describe('every preset theme is usable', () => {
  const triplet = /^\d{1,3}(\.\d)? \d{1,3}(\.\d)?% \d{1,3}(\.\d)?%$/;

  it('has unique ids, valid shape, and a source for curated themes', () => {
    const ids = PRESET_THEMES.map((t) => t.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const t of PRESET_THEMES) expect(readTheme(t), t.id).not.toBeNull();
    for (const t of CURATED_THEMES) expect(t.source, t.id).toMatch(/^https:\/\/github\.com\/livlign\/ccthemes/);
    expect(isBuiltinId('nord')).toBe(true);
    expect(findTheme(BAKERY_ID)?.label).toBe('Bakery');
  });

  for (const theme of PRESET_THEMES) {
    for (const mode of ['light', 'dark'] as const) {
      it(`${theme.id} (${mode}): complete tokens and readable text`, () => {
        const d = deriveBps(theme, mode);
        for (const k of BPS_TOKENS) expect(d.tokens[k], `${theme.id} ${k}`).toMatch(triplet);
        if (d.preview) expect(textContrast(d.preview), `${theme.id} ${mode} text contrast`).toBeGreaterThanOrEqual(4.5);
      });
    }
  }

  it('a single-variant theme always shows its one variant', () => {
    const nord = findTheme('nord')!;
    expect(variantOf(nord, 'light').mode).toBe('dark');
    expect(deriveBps(nord, 'light').mode).toBe('dark');
  });
  it('status colours keep their meaning (success is green, danger is red)', () => {
    for (const theme of PRESET_THEMES) {
      const d = deriveBps(theme, 'dark');
      const [sh] = d.tokens['--success'].split(' ').map(parseFloat), [dh] = d.tokens['--destructive'].split(' ').map(parseFloat);
      expect(sh >= 70 && sh <= 180, `${theme.id} success hue ${sh}`).toBe(true);
      expect(dh >= 330 || dh <= 25, `${theme.id} danger hue ${dh}`).toBe(true);
    }
  });
});

describe('colour helpers', () => {
  it('hslTriplet gives the shadcn triplet form', () => {
    expect(hslTriplet('#ffffff')).toBe('0 0% 100%');
    expect(hslTriplet('#000000')).toBe('0 0% 0%');
  });
  it('contrast ratio is symmetric and 21 for black on white', () => {
    expect(Math.round(contrast('#000000', '#ffffff'))).toBe(21);
    expect(contrast('#336699', '#ffffff')).toBeCloseTo(contrast('#ffffff', '#336699'));
  });
});

describe('page output', () => {
  it('htmlMode: explicit, single-variant and system', () => {
    expect(htmlMode(DEFAULT_THEME, 'light')).toBe('light');
    expect(htmlMode(DEFAULT_THEME, 'dark')).toBe('dark');
    expect(htmlMode(DEFAULT_THEME, 'system')).toBe('system');
    expect(htmlMode(findTheme('nord')!, 'system')).toBe('dark'); // only a dark variant
    expect(htmlMode(findTheme('nord')!, 'light')).toBe('dark');
  });
  it('system mode emits a prefers-color-scheme block; explicit modes do not', () => {
    expect(themeCss(DEFAULT_THEME, 'system')).toContain('prefers-color-scheme: dark');
    expect(themeCss(DEFAULT_THEME, 'light')).not.toContain('prefers-color-scheme: dark');
    expect(SYSTEM_MODE_SCRIPT).toContain("classList.toggle('dark'");
  });
  it('printing always uses the Bakery light colours', () => {
    const css = themeCss(findTheme('dracula')!, 'dark');
    const print = css.slice(css.indexOf('@media print'));
    expect(print).toContain(`--background:${BAKERY_TOKENS.light['--background']}`);
    expect(print).toContain('color-scheme:light');
  });
  it('applyToDocument sets the attribute, the dark class and one stylesheet', () => {
    const cls = new Set<string>(); const attrs: Record<string, string> = {}; let style: { id: string; textContent: string } | null = null;
    const doc = {
      documentElement: { setAttribute: (k: string, v: string) => { attrs[k] = v; }, classList: { toggle: (c: string, on: boolean) => (on ? cls.add(c) : cls.delete(c)) } },
      getElementById: () => style, createElement: () => ({ id: '', textContent: '' }),
      head: { appendChild: (e: { id: string; textContent: string }) => { style = e; } },
    } as unknown as Document;
    applyToDocument(doc, findTheme('dracula')!, 'light', false);
    expect(attrs['data-bps-theme']).toBe('dracula');
    expect(cls.has('dark')).toBe(true); // dracula is dark-only
    expect(style!.textContent).toContain('--primary:');
    applyToDocument(doc, DEFAULT_THEME, 'light', false);
    expect(cls.has('dark')).toBe(false);
  });
});

describe('preferences', () => {
  it('BPS defaults to light (it never followed the system)', () => {
    expect(DEFAULT_MODE).toBe('light');
    expect(readAppearance(null)).toEqual({ mode: 'light', themeId: HEARTH_ID, custom: [] });
  });
  it('readAppearance drops unknown modes/themes, built-in ids as own themes, and caps own themes', () => {
    const own = (i: number): ThemeDef => ({ v: 1, id: `user-${i}`, label: `Mine ${i}`, inputs: { light: { 'surface-0': '#ffffff', 'text-primary': '#000000' } } });
    const r = readAppearance({
      mode: 'sepia', themeId: 'nope',
      custom: [{ ...own(0), id: 'nord' }, ...Array.from({ length: 30 }, (_, i) => own(i + 1)), { v: 1, id: 'bad', label: 'x', inputs: { light: { 'surface-0': 'red' } } }],
    });
    expect(r.mode).toBe('light');
    expect(r.themeId).toBe(HEARTH_ID);
    expect(r.custom.length).toBe(20);
    expect(r.custom.some((t) => t.id === 'nord' || t.id === 'bad')).toBe(false);
  });
  it('cookie round-trips built-in and own themes and ignores garbage', () => {
    const builtin = { mode: 'dark' as const, theme: findTheme('dracula')! };
    expect(readCookie(cookieValue(builtin))).toEqual(builtin);
    const own: ThemeDef = { v: 1, id: 'user-1', label: 'Mine', inputs: { dark: { 'surface-0': '#101010', 'text-primary': '#f0f0f0', accent: '#ff8800' } } };
    const back = readCookie(cookieValue({ mode: 'system', theme: own }));
    expect(back?.theme.id).toBe('user-1');
    expect(back?.theme.inputs.dark?.accent).toBe('#ff8800');
    for (const junk of [undefined, '', 'x', '%7B', encodeURIComponent('{"mode":"dark","themeId":"nope"}'), 'a'.repeat(5000), encodeURIComponent('{"mode":"dark","theme":{"id":"<script>","label":"x","inputs":{}}}')]) {
      expect(readCookie(junk as string | undefined), String(junk).slice(0, 20)).toBeNull();
    }
    expect(APPEARANCE_COOKIE).toBe('bps_appearance');
  });
  it('the default choice needs no cookie', () => {
    expect(cookieValue({ mode: 'light', theme: DEFAULT_THEME })).toBeNull();
    expect(toLocal({ mode: 'dark', theme: DEFAULT_THEME })).toEqual({ mode: 'dark', themeId: HEARTH_ID });
  });
  it('resolveAppearance: try-on > device > account > last > default', () => {
    const last = { mode: 'dark' as const, theme: findTheme('nord')! };
    const dev = { mode: 'light' as const, theme: findTheme('github')! };
    const acct = { mode: 'system' as const, themeId: 'dracula', custom: [] };
    const prev = findTheme('sepia')!;
    expect(resolveAppearance({ preview: null, device: null, account: undefined, last: null })).toEqual({ mode: 'light', theme: DEFAULT_THEME });
    expect(resolveAppearance({ preview: null, device: null, account: undefined, last }).theme.id).toBe('nord');
    expect(resolveAppearance({ preview: null, device: null, account: acct, last }).theme.id).toBe('dracula');
    expect(resolveAppearance({ preview: null, device: dev, account: acct, last }).theme.id).toBe('github');
    const t = resolveAppearance({ preview: prev, device: dev, account: acct, last });
    expect(t.theme.id).toBe('sepia');
    expect(t.mode).toBe('light'); // try-on keeps the chosen mode
  });
});

describe('built-in themes', () => {
  it('are Ledger, Hearth (the default), Graphite, Bakery, BPS Classic, Clay, High contrast, Sepia', () => {
    expect(DEFAULT_THEME.id).toBe(HEARTH_ID);
    expect(BUILTIN_THEMES.map((t) => t.id)).toEqual(['ledger', 'hearth', 'graphite', 'bakery', 'bps-classic', 'clay', 'high-contrast', 'sepia']);
  });
});
