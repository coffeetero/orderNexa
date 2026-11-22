/**
 * Turning a chosen mode + theme into page output. Pure (no DOM), so the server layout and the browser use the same code:
 * the server renders the stylesheet and the `dark` class into the first HTML (no flash); the browser re-applies it live.
 *
 * Tokens are set on `:root[data-bps-theme]`, which outranks the defaults in globals.css. Printing always uses the Bakery light colours.
 */
import { BPS_TOKENS, BAKERY_TOKENS, deriveBps, type BpsTokenMap } from './tokens';
import { variantOf, type ThemeDef, type ThemeMode } from './themes';

export type ModeChoice = 'light' | 'dark' | 'system';
export const STYLE_ID = 'bps-theme';
export const ROOT_ATTR = 'data-bps-theme';
const SEL = `:root[${ROOT_ATTR}]`;

const block = (t: BpsTokenMap, scheme: ThemeMode) => BPS_TOKENS.map((k) => `${k}:${t[k]};`).join('') + `color-scheme:${scheme};`;

export const isModeChoice = (v: unknown): v is ModeChoice => v === 'light' || v === 'dark' || v === 'system';

/**
 * What `<html>` needs: 'light' / 'dark' when the mode is fixed (explicitly chosen, or the theme has a single variant), 'system' when the
 * light/dark variant follows the operating system.
 */
export function htmlMode(theme: ThemeDef, choice: ModeChoice): ModeChoice {
  if (choice !== 'system') return variantOf(theme, choice).mode;
  const light = variantOf(theme, 'light').mode, dark = variantOf(theme, 'dark').mode;
  return light === dark ? light : 'system';
}

/** The stylesheet for `theme` in `choice` mode (screen), plus the fixed Bakery light colours for print. */
export function themeCss(theme: ThemeDef, choice: ModeChoice): string {
  const mode = htmlMode(theme, choice);
  const light = deriveBps(theme, 'light'), dark = deriveBps(theme, 'dark');
  let screen: string;
  if (mode === 'system') {
    screen = `${SEL}{${block(light.tokens, 'light')}}@media (prefers-color-scheme: dark){${SEL}{${block(dark.tokens, 'dark')}}}`;
  } else {
    const d = mode === 'dark' ? dark : light;
    screen = `${SEL}{${block(d.tokens, d.mode)}}`;
  }
  return `@media screen{${screen}}@media print{${SEL}{${block(BAKERY_TOKENS.light, 'light')}}}`;
}

/** Inline script keeping the `dark` class in step with the operating system (only needed for 'system'). */
export const SYSTEM_MODE_SCRIPT =
  "(function(){try{var d=document.documentElement,m=window.matchMedia('(prefers-color-scheme: dark)');var u=function(){d.classList.toggle('dark',m.matches)};u();m.addEventListener('change',u)}catch(e){}})();";

/** Applies `theme` in `choice` mode to a live document (browser). Returns what is shown. */
export function applyToDocument(doc: Document, theme: ThemeDef, choice: ModeChoice, osDark: boolean): { mode: ThemeMode } {
  const html = htmlMode(theme, choice);
  const mode: ThemeMode = html === 'system' ? (osDark ? 'dark' : 'light') : html;
  const root = doc.documentElement;
  root.setAttribute(ROOT_ATTR, theme.id);
  root.classList.toggle('dark', mode === 'dark');
  let style = doc.getElementById(STYLE_ID) as HTMLStyleElement | null;
  if (!style) { style = doc.createElement('style'); style.id = STYLE_ID; doc.head.appendChild(style); }
  const css = themeCss(theme, choice);
  if (style.textContent !== css) style.textContent = css;
  return { mode };
}
