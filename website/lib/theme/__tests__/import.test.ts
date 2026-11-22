import { readFileSync } from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { extractThemes } from '@/lib/theme/extract';
import { candidates, importFromGithub, planFromUrl, rawUrl, treeUrl } from '@/lib/theme/github';

const fx = (name: string) => readFileSync(path.join(__dirname, 'fixtures', name), 'utf8');

describe('Claude Code terminal themes (ccthemes format)', () => {
  it('reads a dark theme: accent, status and text colours, with a chosen background', () => {
    const [t] = extractThemes(fx('nord.json'), 'nord.json');
    expect(t.label).toBe('Nord');
    expect(t.inputs.dark).toBeDefined();
    expect(t.inputs.light).toBeUndefined();
    expect(t.inputs.dark).toMatchObject({ accent: '#81a1c1', success: '#a3be8c', danger: '#bf616a', warning: '#ebcb8b', 'text-primary': '#d8dee9' });
    expect(t.inputs.dark!['surface-0']).toMatch(/^#[0-9a-f]{6}$/);
  });
  it('reads a light theme as a light variant', () => {
    const [t] = extractThemes(fx('github-light.json'), 'github-light.json');
    expect(t.inputs.light).toBeDefined();
    expect(t.inputs.dark).toBeUndefined();
  });
  it('rejects theme files without accent/text or with bad colours', () => {
    expect(extractThemes(JSON.stringify({ name: 'x', base: 'dark', overrides: { claude: 'red', text: '#fff' } }), 'x.json')).toEqual([]);
    expect(extractThemes('{ not json', 'x.json')).toEqual([]);
  });
  it('still reads the seed format (inputs.light / inputs.dark)', () => {
    const seeds = { 'surface-0': '#ffffff', 'text-primary': '#111111', accent: '#005599' };
    const [t] = extractThemes(JSON.stringify({ label: 'Seeds', inputs: { light: seeds } }), 't.json');
    expect(t.label).toBe('Seeds');
    expect(t.inputs.light?.accent).toBe('#005599');
  });
  it('is never evaluated: code in a theme file is only read as text', () => {
    const evil = `globalThis.__ran = true; export const t = { inputs: { dark: { 'surface-0': '#101010', 'text-primary': '#eeeeee' } } };`;
    const found = extractThemes(evil, 'theme.js');
    expect((globalThis as { __ran?: boolean }).__ran).toBeUndefined();
    expect(found[0]?.inputs.dark).toBeDefined();
  });
});

describe('GitHub links', () => {
  it('accepts repo, folder, file and raw links; rejects everything else', () => {
    expect(planFromUrl('https://github.com/owner/repo')).toMatchObject({ kind: 'tree', owner: 'owner', repo: 'repo' });
    expect(planFromUrl('https://github.com/livlign/ccthemes/tree/main/plugins/theme-gallery/themes')).toMatchObject({ kind: 'tree', path: 'plugins/theme-gallery/themes' });
    expect(planFromUrl('https://github.com/o/r/blob/main/themes/a.json')).toMatchObject({ kind: 'file', path: 'themes/a.json' });
    expect(planFromUrl('https://raw.githubusercontent.com/o/r/main/a.json')).toMatchObject({ kind: 'file' });
    for (const bad of ['http://github.com/o/r', 'https://evil.com/o/r', 'https://user:pw@github.com/o/r', 'https://github.com:444/o/r', 'ftp://github.com/o/r', 'not a url', 'https://github.com/o', 'https://raw.githubusercontent.com/o/r/main/../x.json']) {
      expect(planFromUrl(bad), bad).toBeNull();
    }
  });
  it('only ever fetches the two allowed hosts', () => {
    expect(new URL(rawUrl('o', 'r', 'main', 'a/b.json')).hostname).toBe('raw.githubusercontent.com');
    expect(new URL(treeUrl('o', 'r', 'main')).hostname).toBe('api.github.com');
  });
  it('ranks theme-looking JSON files first and skips package/test files', () => {
    const tree = { tree: [
      { path: 'package.json', type: 'blob', size: 100 }, { path: 'src/a.test.ts', type: 'blob', size: 100 },
      { path: 'themes/nord.json', type: 'blob', size: 100 }, { path: 'README.md', type: 'blob', size: 100 }, { path: 'src/util.ts', type: 'blob', size: 100 },
    ] };
    const c = candidates(tree, '');
    expect(c[0]).toBe('themes/nord.json');
    expect(c).not.toContain('package.json');
    expect(c).not.toContain('src/a.test.ts');
  });
});

describe('importing from a repository (offline: a fake fetch, no network)', () => {
  const files: Record<string, string> = { 'themes/nord.json': fx('nord.json'), 'themes/github-light.json': fx('github-light.json'), 'themes/readme.json': '{"hello":1}' };
  const fake = async (url: string) => {
    if (url.startsWith('https://api.github.com/')) return JSON.stringify({ tree: Object.keys(files).map((p) => ({ path: p, type: 'blob', size: files[p].length })) });
    // https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path...>
    const p = decodeURIComponent(new URL(url).pathname.split('/').slice(4).join('/'));
    if (p in files) return files[p];
    throw new Error('404');
  };
  it('finds every theme in a folder, not just the first file', async () => {
    const r = await importFromGithub('https://github.com/owner/repo', fake);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.themes.map((t) => t.label).sort()).toEqual(['GitHub Light', 'Nord']);
  });
  it('explains a link that is not GitHub, and a repository with no themes', async () => {
    const a = await importFromGithub('https://example.com/x', fake);
    expect(a.ok).toBe(false);
    const none = await importFromGithub('https://github.com/owner/repo', async (u) => (u.startsWith('https://api.github.com/') ? JSON.stringify({ tree: [{ path: 'a.json', type: 'blob', size: 5 }] }) : '{}'));
    expect(none.ok).toBe(false);
  });
});
