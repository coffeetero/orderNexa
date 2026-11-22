/**
 * Import a theme from a GitHub link (Phase 19). The browser fetches PUBLIC files only, from two hosts: raw.githubusercontent.com (file text) and
 * api.github.com (the file list of a repository or folder). No sign-in, no cookies (credentials: 'omit'), no referrer. Files are read as text and
 * searched for colour seeds (extract.ts); nothing is evaluated.
 *
 * Accepted links:
 *   https://github.com/<owner>/<repo>                       the whole repository (default branch)
 *   https://github.com/<owner>/<repo>/tree/<ref>/<folder>   a folder
 *   https://github.com/<owner>/<repo>/blob/<ref>/<file>     one file
 *   https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<file>
 * For a repository or folder, up to MAX_CANDIDATES .json / .js / .mjs / .cjs / .ts / .tsx files (≤ 256 KB, names with "theme" or "color" first)
 * are read until themes are found.
 */
import { extractThemes, MAX_FILE, type FoundTheme } from './extract';

export type GithubPlan =
  | { kind: 'file'; url: string; path: string; owner: string; repo: string }
  | { kind: 'tree'; owner: string; repo: string; ref: string; path: string };
const NAME = /^[A-Za-z0-9_.-]{1,100}$/;
const REF = /^[A-Za-z0-9_./-]{1,200}$/;
const safePath = (p: string) => p.split('/').every((seg) => seg && seg !== '..' && seg !== '.' && /^[A-Za-z0-9_.@+-]{1,200}$/.test(seg));
export const ALLOWED_HOSTS = ['raw.githubusercontent.com', 'api.github.com'];

/** What to fetch for a pasted link (null when it is not a public GitHub repository, folder or file link). */
export function planFromUrl(input: string): GithubPlan | null {
  let u: URL;
  try { u = new URL(input.trim()); } catch { return null; }
  if (u.protocol !== 'https:' || u.username || u.password || u.port) return null;
  const parts = u.pathname.split('/').filter(Boolean).map((p) => { try { return decodeURIComponent(p); } catch { return '\u0000'; } });
  if (u.hostname === 'raw.githubusercontent.com') {
    const [owner, repo, ref, ...rest] = parts;
    if (!owner || !repo || !ref || !rest.length || !NAME.test(owner) || !NAME.test(repo) || !REF.test(ref) || !safePath(rest.join('/'))) return null;
    return { kind: 'file', owner, repo, path: rest.join('/'), url: rawUrl(owner, repo, ref, rest.join('/')) };
  }
  if (u.hostname !== 'github.com' && u.hostname !== 'www.github.com') return null;
  const [owner, repo0, kind, ref, ...rest] = parts;
  const repo = repo0?.replace(/\.git$/, '');
  if (!owner || !repo || !NAME.test(owner) || !NAME.test(repo)) return null;
  if (!kind) return { kind: 'tree', owner, repo, ref: 'HEAD', path: '' };
  if (!ref || !REF.test(ref) || (rest.length && !safePath(rest.join('/')))) return null;
  if (kind === 'tree') return { kind: 'tree', owner, repo, ref, path: rest.join('/') };
  if (kind === 'blob' && rest.length) return { kind: 'file', owner, repo, path: rest.join('/'), url: rawUrl(owner, repo, ref, rest.join('/')) };
  return null;
}
const enc = (p: string) => p.split('/').map(encodeURIComponent).join('/');
export const rawUrl = (owner: string, repo: string, ref: string, path: string) => `https://raw.githubusercontent.com/${owner}/${repo}/${enc(ref)}/${enc(path)}`;
export const treeUrl = (owner: string, repo: string, ref: string) => `https://api.github.com/repos/${owner}/${repo}/git/trees/${enc(ref)}?recursive=1`;

export type FetchText = (url: string) => Promise<string>;
/** fetch() limited to the two allowed hosts, anonymous, text only, at most MAX_FILE (plus room for a file list). */
export const fetchPublicText: FetchText = async (url) => {
  const host = new URL(url).hostname;
  if (!ALLOWED_HOSTS.includes(host)) throw new Error('host');
  const res = await fetch(url, { credentials: 'omit', referrerPolicy: 'no-referrer', redirect: 'follow', cache: 'no-store', headers: { Accept: host === 'api.github.com' ? 'application/vnd.github+json' : 'text/plain' } });
  if (res.url && !ALLOWED_HOSTS.includes(new URL(res.url).hostname)) throw new Error('host');
  if (!res.ok) throw new Error(String(res.status));
  const text = await res.text();
  if (text.length > (host === 'api.github.com' ? 8 * MAX_FILE : MAX_FILE)) throw new Error('size');
  return text;
};

export const MAX_CANDIDATES = 60;
/** Stop reading files once this many themes were found. */
export const MAX_IMPORTED = 12;
const EXT = /\.(json|m?js|cjs|tsx?)$/i;
const SKIP = /(^|\/)(node_modules|dist|build|\.github|test|tests|__tests__|coverage)\/|(^|\/)(package(-lock)?\.json|tsconfig[^/]*\.json|\.eslintrc[^/]*|[^/]*\.d\.ts|[^/]*\.(test|spec)\.[^/]+)$/i;
/** Candidate files of a repository listing, best first. */
export function candidates(tree: unknown, prefix: string): string[] {
  const items = (tree && typeof tree === 'object' && Array.isArray((tree as { tree?: unknown }).tree) ? (tree as { tree: unknown[] }).tree : []) as { path?: unknown; type?: unknown; size?: unknown }[];
  const pre = prefix ? prefix.replace(/\/+$/, '') + '/' : '';
  const score = (p: string) => (/theme/i.test(p) ? 4 : 0) + (/colou?r|palette/i.test(p) ? 2 : 0) + (/\.json$/i.test(p) ? 1 : 0) - p.split('/').length * 0.1;
  return items
    .filter((x) => x.type === 'blob' && typeof x.path === 'string' && (x.path.startsWith(pre) || !pre) && EXT.test(x.path) && !SKIP.test(x.path) && (typeof x.size !== 'number' || x.size <= MAX_FILE) && safePath(x.path))
    .map((x) => x.path as string)
    .sort((a, b) => score(b) - score(a))
    .slice(0, MAX_CANDIDATES);
}

export interface ImportedTheme extends FoundTheme { file: string; source: string }
export type ImportResult = { ok: true; themes: ImportedTheme[]; looked: number } | { ok: false; error: string };
/** Look up a GitHub link and return the themes found (each with the file it came from). */
export async function importFromGithub(input: string, fetchText: FetchText = fetchPublicText): Promise<ImportResult> {
  const plan = planFromUrl(input);
  if (!plan) return { ok: false, error: 'Paste a link to a public GitHub repository, folder or file (github.com or raw.githubusercontent.com).' };
  const source = `https://github.com/${plan.owner}/${plan.repo}`;
  let files: { path: string; url: string }[];
  if (plan.kind === 'file') files = [{ path: plan.path, url: plan.url }];
  else {
    let tree: unknown;
    try { tree = JSON.parse(await fetchText(treeUrl(plan.owner, plan.repo, plan.ref))); } catch { return { ok: false, error: 'That repository could not be read. Check that it exists and is public.' }; }
    files = candidates(tree, plan.path).map((p) => ({ path: p, url: rawUrl(plan.owner, plan.repo, plan.ref, p) }));
    if (!files.length) return { ok: false, error: 'No JSON, JavaScript or TypeScript files were found there.' };
  }
  const themes: ImportedTheme[] = []; let looked = 0;
  for (const f of files) {
    let text: string;
    try { text = await fetchText(f.url); } catch { continue; }
    looked++;
    for (const t of extractThemes(text, f.path)) themes.push({ ...t, file: f.path, source });
    if (themes.length >= MAX_IMPORTED) break;
  }
  if (!looked) return { ok: false, error: 'The file could not be downloaded. Check the link and that the repository is public.' };
  if (!themes.length) return { ok: false, error: `No theme colours were found (looked in ${looked} file${looked === 1 ? '' : 's'}). A theme needs at least "surface-0" and "text-primary" colours.` };
  return { ok: true, themes, looked };
}
