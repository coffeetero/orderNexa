/**
 * Finding theme colours in a file (Phase 19 import). The file is READ AS TEXT: JSON is parsed with JSON.parse; JavaScript / TypeScript is scanned
 * by a small tokenizer for the seed object literals (`inputs: { light: { accent: '#…', … }, dark: { … } }`) and their hex values by key name.
 * Nothing is ever evaluated, imported or run: a theme's hooks, fetches or other code are simply not looked at.
 */
import { isDarkColor, isHex, mix } from './color';
import { SEED_KEYS, cleanLabel, readSeeds, type ThemeSeeds } from './themes';

/** A theme found in a file: its name and the seeds of each mode it has (no id yet). */
export interface FoundTheme { label: string; inputs: { light?: ThemeSeeds; dark?: ThemeSeeds } }
export const MAX_FILE = 256 * 1024;
const MAX_THEMES = 10;

// ------------------------------------------------------------------ Claude Code terminal themes: { name, base, overrides }
/**
 * A Claude Code terminal theme colours the semantic UI only (accent, text, status) and has no page background, so the surfaces are chosen
 * here: from `userMessageBackground` when the theme has one (it is a shade off the canvas), else from the accent. `base` says light or dark.
 * Curated themes (catalog.ts) set their surfaces by hand instead; this is for pasted links.
 */
const hex = (v: unknown): string | null => (isHex(v) ? v.toLowerCase() : null);
export function fromTerminalTheme(o: Record<string, unknown>): FoundTheme | null {
  const ov = o.overrides;
  if (!ov || typeof ov !== 'object' || Array.isArray(ov)) return null;
  const c = ov as Record<string, unknown>;
  const text = hex(c.text), accent = hex(c.claude) ?? hex(c.permission) ?? hex(c.suggestion);
  if (!text || !accent) return null;
  const base = typeof o.base === 'string' ? o.base : 'dark';
  const dark = !base.startsWith('light');
  const umb = hex(c.userMessageBackground);
  const neutral = dark ? '#16171d' : '#f7f7f8';
  const s0 = umb ? mix(umb, dark ? '#000000' : '#ffffff', dark ? 0.4 : 0.6) : mix(neutral, accent, 0.05);
  const seeds = readSeeds({
    accent, danger: hex(c.error), success: hex(c.success), warning: hex(c.warning), pro: hex(c.planMode) ?? hex(c.permission),
    'surface-0': s0, 'surface-2': umb ?? mix(s0, text, 0.06), 'text-primary': text,
  });
  const name = typeof o.name === 'string' ? o.name : '';
  return seeds ? { label: name, inputs: dark ? { dark: seeds } : { light: seeds } } : null;
}

// ------------------------------------------------------------------ JSON
function fromObject(o: unknown, depth = 0, out: FoundTheme[] = [], label = ''): FoundTheme[] {
  if (!o || typeof o !== 'object' || depth > 6 || out.length >= MAX_THEMES) return out;
  if (Array.isArray(o)) { for (const x of o.slice(0, 50)) fromObject(x, depth + 1, out, label); return out; }
  const r = o as Record<string, unknown>;
  const terminal = fromTerminalTheme(r);
  if (terminal) { out.push(terminal); return out; }
  const name = typeof r.label === 'string' ? r.label : typeof r.name === 'string' ? r.name : typeof r.id === 'string' ? r.id : label;
  const holder = r.inputs && typeof r.inputs === 'object' ? (r.inputs as Record<string, unknown>) : r;
  const light = readSeeds(holder.light), dark = readSeeds(holder.dark);
  if (light || dark) { out.push({ label: name, inputs: { ...(light ? { light } : {}), ...(dark ? { dark } : {}) } }); return out; }
  const flat = readSeeds(r);
  if (flat) { out.push({ label: name, inputs: isDarkColor(flat['surface-0']) ? { dark: flat } : { light: flat } }); return out; }
  for (const v of Object.values(r).slice(0, 200)) fromObject(v, depth + 1, out, name);
  return out;
}

// ------------------------------------------------------------------ JS / TS text
/** Index of the brace closing the one at `open`, skipping strings, template literals and comments (-1 when unbalanced). */
export function matchBrace(s: string, open: number): number {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const c = s[i];
    if (c === '"' || c === "'" || c === '`') { const q = c; i++; while (i < s.length && s[i] !== q) { if (s[i] === '\\') i++; i++; } continue; }
    if (c === '/' && s[i + 1] === '/') { const e = s.indexOf('\n', i); if (e < 0) return -1; i = e; continue; }
    if (c === '/' && s[i + 1] === '*') { const e = s.indexOf('*/', i + 2); if (e < 0) return -1; i = e + 1; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return i; }
  }
  return -1;
}
const KEY = (k: string) => new RegExp(`(?:^|[\\s,{])(["'\`]?)${k}\\1\\s*:\\s*\\{`, 'g');
/** The `{…}` blocks following `key:` in `s` (start of the brace, end). */
function blocks(s: string, key: string): { at: number; start: number; end: number }[] {
  const out: { at: number; start: number; end: number }[] = []; const re = KEY(key); let m: RegExpExecArray | null;
  while ((m = re.exec(s)) && out.length < 50) {
    const start = m.index + m[0].length - 1; const end = matchBrace(s, start);
    if (end > start) { out.push({ at: m.index, start, end }); re.lastIndex = end; }
  }
  return out;
}
const SEED_RE = new RegExp(`(["'\`]?)(${SEED_KEYS.map((k) => k.replace(/-/g, '\\-')).join('|')})\\1\\s*:\\s*(["'\`])(#[0-9a-fA-F]{6})\\3`, 'g');
/** The seeds written literally in a block of text (first value of each key wins). */
export function seedsInText(s: string): ThemeSeeds | null {
  const o: Record<string, string> = {}; let m: RegExpExecArray | null; SEED_RE.lastIndex = 0;
  while ((m = SEED_RE.exec(s))) if (!(m[2]! in o)) o[m[2]!] = m[4]!;
  return readSeeds(o);
}
const LABEL_RE = /(["'`]?)(label|name|title)\1\s*:\s*(["'`])([^"'`\n\\]{1,80})\3/g;
function labelNear(s: string, at: number): string {
  // the closest label/name before the inputs (within 1500 characters), else the first after it
  const before = s.slice(Math.max(0, at - 1500), at); let m: RegExpExecArray | null; let last = '';
  LABEL_RE.lastIndex = 0; while ((m = LABEL_RE.exec(before))) last = m[4]!;
  if (last) return last;
  LABEL_RE.lastIndex = 0; m = LABEL_RE.exec(s.slice(at, at + 3000));
  return m ? m[4]! : '';
}
function modesIn(s: string): FoundTheme['inputs'] | null {
  const pick = (mode: 'light' | 'dark') => { for (const b of blocks(s, mode)) { const seeds = seedsInText(s.slice(b.start, b.end + 1)); if (seeds) return seeds; } return null; };
  const light = pick('light'), dark = pick('dark');
  return light || dark ? { ...(light ? { light } : {}), ...(dark ? { dark } : {}) } : null;
}
function fromText(s: string): FoundTheme[] {
  const out: FoundTheme[] = [];
  for (const b of blocks(s, 'inputs')) {
    if (out.length >= MAX_THEMES) break;
    const inputs = modesIn(s.slice(b.start, b.end + 1));
    if (inputs) out.push({ label: labelNear(s, b.at), inputs });
  }
  if (out.length) return out;
  const inputs = modesIn(s);
  if (inputs) return [{ label: labelNear(s, 0), inputs }];
  const flat = seedsInText(s);
  return flat ? [{ label: labelNear(s, 0), inputs: isDarkColor(flat['surface-0']) ? { dark: flat } : { light: flat } }] : [];
}

/** Themes found in one file's text. JSON files (or text that parses as JSON) are read as data; anything else is scanned as text. */
export function extractThemes(text: string, fileName = ''): FoundTheme[] {
  if (text.length > MAX_FILE) return [];
  let found: FoundTheme[] = [];
  const t = text.trim();
  if (/\.json$/i.test(fileName) || t.startsWith('{') || t.startsWith('[')) {
    try { found = fromObject(JSON.parse(t)); } catch { found = []; }
  }
  if (!found.length && !/\.json$/i.test(fileName)) found = fromText(text);
  const base = fileName.split('/').pop()?.replace(/\.[^.]+$/, '') ?? '';
  return found.slice(0, MAX_THEMES).map((f) => ({ ...f, label: cleanLabel(f.label) || cleanLabel(base) || 'Imported theme' }));
}
