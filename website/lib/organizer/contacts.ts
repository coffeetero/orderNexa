/**
 * Organizer › Contacts: shared types plus vCard (.vcf) and CSV reading/writing.
 * Parsing only turns a file into save payloads; the database (org_contacts_import) validates and saves them.
 * vCard: reads 2.1 / 3.0 / 4.0 (iPhone, Google, Outlook), writes 3.0 (imports into iPhone and Google).
 * CSV: reads Google (current and older headers) and Outlook exports, writes the Google Contacts layout.
 */
import { parseCsv } from '@/lib/orders/import-csv';

export type PointType = 'PHONE' | 'MOBILE' | 'FAX' | 'EMAIL' | 'ADDRESS' | 'WEBSITE' | 'OTHER';
export interface ContactPoint { contact_point_id?: number | null; type: PointType; label: string | null; value: string; is_primary?: boolean }
export interface LabelledDate { label: string; date: string }
export interface RelatedPerson { label: string; name: string }

/** What a save / import sends (org_contact_save payload). */
export interface ContactInput {
  name_prefix?: string | null; first_name?: string | null; middle_name?: string | null; last_name?: string | null;
  name_suffix?: string | null; nickname?: string | null; company_name?: string | null; job_title?: string | null;
  department?: string | null; notes?: string | null; is_favorite?: boolean;
  important_dates: LabelledDate[]; related_people: RelatedPerson[]; points: ContactPoint[];
  photo_data?: string | null; tag_names?: string[];
}

export interface ContactTag { tag_id: number; tag_name: string; tag_color: string; contact_count?: number }

/** A contact as org_contact_json / org_contacts_export return it. */
export interface ContactDetail extends ContactInput {
  contact_id: number; full_name: string; kind: 'COMPANY' | 'CUSTOMER';
  customer_id: number | null; customer_name: string | null; customer_number: string | null;
  has_photo: boolean; tags: ContactTag[]; created_at: string; updated_at: string;
  created_by_name: string | null; updated_by_name: string | null;
  timeline?: { note_id: number; note_text: string; is_pinned: boolean; created_at: string; author_name: string }[];
}

export const PHOTO_MAX = 200000;

/** Phone label → stored type: mobile / cell / iPhone → MOBILE, anything with fax → FAX, else PHONE. */
export function phoneType(label: string | null | undefined): PointType {
  const l = (label ?? '').toLowerCase();
  if (/fax/.test(l)) return 'FAX';
  if (/mobile|cell|iphone/.test(l)) return 'MOBILE';
  return 'PHONE';
}

/** Accepts 1980-05-12, 19800512, --05-12, --0512, 1604-05-12 (Apple: no year), 5/12/1980; returns YYYY-MM-DD or --MM-DD. */
export function normalizeDate(raw: string | null | undefined): string | null {
  const s = (raw ?? '').trim().replace(/T.*$/, '');
  let m = /^(\d{4})-?(\d{2})-?(\d{2})$/.exec(s);
  if (m) return m[1] === '1604' ? `--${m[2]}-${m[3]}` : `${m[1]}-${m[2]}-${m[3]}`;
  m = /^--(\d{2})-?(\d{2})$/.exec(s);
  if (m) return `--${m[1]}-${m[2]}`;
  m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(s);
  if (m) return `${m[3]}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}`;
  return null;
}

const clean = (s: string | null | undefined) => {
  const t = (s ?? '').trim();
  return t === '' ? null : t;
};

/** Apple wraps standard labels as _$!<Mobile>!$_ */
const appleLabel = (s: string) => s.replace(/^_\$!<(.*)>!\$_$/, '$1').trim();

// ───────────────────────────── vCard ─────────────────────────────

interface VLine { group: string | null; name: string; params: Record<string, string[]>; value: string }

const unescapeV = (s: string) => s.replace(/\\n/gi, '\n').replace(/\\([,;\\])/g, '$1');

/** Splits on an unescaped separator. */
function splitV(s: string, sep: string): string[] {
  const out: string[] = [];
  let cur = '';
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && i + 1 < s.length) { cur += s[i] + s[i + 1]; i++; }
    else if (s[i] === sep) { out.push(cur); cur = ''; }
    else cur += s[i];
  }
  out.push(cur);
  return out;
}

function decodeQP(s: string): string {
  const bytes: number[] = [];
  const src = s.replace(/=\r?\n/g, '');
  for (let i = 0; i < src.length; i++) {
    if (src[i] === '=' && /^[0-9A-F]{2}$/i.test(src.slice(i + 1, i + 3))) { bytes.push(parseInt(src.slice(i + 1, i + 3), 16)); i += 2; }
    else bytes.push(src.charCodeAt(i));
  }
  return new TextDecoder().decode(new Uint8Array(bytes));
}

function parseLine(line: string): VLine | null {
  let inQuote = false;
  let colon = -1;
  for (let i = 0; i < line.length; i++) {
    if (line[i] === '"') inQuote = !inQuote;
    else if (line[i] === ':' && !inQuote) { colon = i; break; }
  }
  if (colon < 0) return null;
  const head = splitV(line.slice(0, colon), ';');
  let name = head[0];
  let group: string | null = null;
  const dot = name.indexOf('.');
  if (dot >= 0) { group = name.slice(0, dot).toLowerCase(); name = name.slice(dot + 1); }
  const params: Record<string, string[]> = {};
  for (const p of head.slice(1)) {
    const eq = p.indexOf('=');
    const key = (eq >= 0 ? p.slice(0, eq) : 'TYPE').toUpperCase();
    const vals = (eq >= 0 ? p.slice(eq + 1) : p).replace(/"/g, '').split(',').map((v) => v.trim()).filter(Boolean);
    params[key] = [...(params[key] ?? []), ...vals];
  }
  let value = line.slice(colon + 1);
  if ((params.ENCODING ?? []).some((e) => e.toUpperCase() === 'QUOTED-PRINTABLE')) value = decodeQP(value);
  return { group, name: name.toUpperCase(), params, value };
}

const types = (l: VLine) => (l.params.TYPE ?? []).map((t) => t.toLowerCase());

/** The label for a TEL/EMAIL/ADR/URL line: the grouped X-ABLabel if any, else the first meaningful TYPE. */
function vLabel(l: VLine, abLabels: Map<string, string>, ignore: string[]): string | null {
  if (l.group && abLabels.has(l.group)) return abLabels.get(l.group) ?? null;
  const t = types(l).filter((x) => !ignore.includes(x) && x !== 'pref');
  if (t.includes('cell')) return 'mobile';
  if (t.includes('iphone')) return 'iPhone';
  if (t.includes('fax')) return t.includes('home') ? 'home fax' : t.includes('work') ? 'work fax' : 'fax';
  return t[0] ?? null;
}

function cardToContact(lines: VLine[]): ContactInput {
  const c: ContactInput = { important_dates: [], related_people: [], points: [] };
  const abLabels = new Map<string, string>();
  for (const l of lines) if (l.name === 'X-ABLABEL' && l.group) abLabels.set(l.group, appleLabel(unescapeV(l.value)).toLowerCase());
  let fn: string | null = null;
  const pref = (l: VLine) => types(l).includes('pref') || (l.params.PREF ?? []).length > 0;

  for (const l of lines) {
    const v = l.value;
    switch (l.name) {
      case 'N': {
        const [last, first, middle, prefix, suffix] = splitV(v, ';').map((x) => clean(unescapeV(x)));
        Object.assign(c, { last_name: last, first_name: first, middle_name: middle, name_prefix: prefix, name_suffix: suffix });
        break;
      }
      case 'FN': fn = clean(unescapeV(v)); break;
      case 'NICKNAME': c.nickname = clean(unescapeV(splitV(v, ',')[0])); break;
      case 'ORG': {
        const [org, dept] = splitV(v, ';').map((x) => clean(unescapeV(x)));
        c.company_name = org; c.department = dept ?? c.department;
        break;
      }
      case 'TITLE': c.job_title = clean(unescapeV(v)); break;
      case 'NOTE': c.notes = clean(unescapeV(v)); break;
      case 'BDAY': {
        const d = normalizeDate(v);
        if (d) c.important_dates.push({ label: 'birthday', date: d });
        break;
      }
      case 'ANNIVERSARY': case 'X-ANNIVERSARY': {
        const d = normalizeDate(v);
        if (d) c.important_dates.push({ label: 'anniversary', date: d });
        break;
      }
      case 'X-ABDATE': {
        const d = normalizeDate(v);
        if (d) c.important_dates.push({ label: (l.group && abLabels.get(l.group)) || 'other', date: d });
        break;
      }
      case 'TEL': {
        const value = clean(unescapeV(v).replace(/^tel:/i, ''));
        if (!value) break;
        const label = vLabel(l, abLabels, ['voice', 'text', 'msg']);
        c.points.push({ type: phoneType(label), label, value, is_primary: pref(l) });
        break;
      }
      case 'EMAIL': {
        const value = clean(unescapeV(v).replace(/^mailto:/i, ''));
        if (value) c.points.push({ type: 'EMAIL', label: vLabel(l, abLabels, ['internet', 'x400']), value, is_primary: pref(l) });
        break;
      }
      case 'ADR': {
        const [pobox, ext, street, city, region, postal, country] = splitV(v, ';').map((x) => clean(unescapeV(x)));
        const cityLine = [city, [region, postal].filter(Boolean).join(' ')].filter(Boolean).join(', ');
        const value = [street, ext, pobox ? `PO Box ${pobox}` : null, cityLine, country].filter(Boolean).join('\n');
        if (value) c.points.push({ type: 'ADDRESS', label: vLabel(l, abLabels, ['postal', 'parcel', 'dom', 'intl']), value, is_primary: pref(l) });
        break;
      }
      case 'URL': {
        const value = clean(unescapeV(v));
        if (value) c.points.push({ type: 'WEBSITE', label: vLabel(l, abLabels, []), value });
        break;
      }
      case 'X-SOCIALPROFILE': case 'IMPP': {
        const value = clean(unescapeV(v).replace(/^x-apple:/i, ''));
        const service = (l.params['X-SERVICE-TYPE'] ?? l.params.TYPE ?? [])[0] ?? (l.name === 'IMPP' ? value?.split(':')[0] : null);
        if (value) c.points.push({ type: 'OTHER', label: service ? service.charAt(0).toUpperCase() + service.slice(1) : null, value });
        break;
      }
      case 'X-ABRELATEDNAMES': case 'RELATED': {
        const name = clean(unescapeV(v));
        if (name) c.related_people.push({ label: (l.group && abLabels.get(l.group)) || types(l)[0] || 'other', name });
        break;
      }
      case 'CATEGORIES':
        c.tag_names = [...(c.tag_names ?? []), ...splitV(v, ',').map((x) => unescapeV(x).trim()).filter(Boolean)];
        break;
      case 'PHOTO': {
        let data: string | null = null;
        if (/^data:image\//i.test(v)) data = v;
        else if ((l.params.ENCODING ?? []).some((e) => /^(b|base64)$/i.test(e))) {
          const t = types(l).find((x) => /jpe?g|png|gif/.test(x)) ?? 'jpeg';
          data = `data:image/${t === 'jpg' ? 'jpeg' : t};base64,${v.replace(/\s/g, '')}`;
        }
        if (data && data.length <= PHOTO_MAX) c.photo_data = data;
        break;
      }
    }
  }
  if (!c.first_name && !c.last_name && fn && fn !== c.company_name) {
    const parts = fn.split(/\s+/);
    c.first_name = parts.length > 1 ? parts.slice(0, -1).join(' ') : parts[0];
    c.last_name = parts.length > 1 ? parts[parts.length - 1] : null;
  }
  return c;
}

/** .vcf text → contacts (one per BEGIN:VCARD … END:VCARD). */
export function parseVCards(text: string): ContactInput[] {
  // unfold: a line starting with space/tab continues the previous one; QP soft breaks end with '='
  const raw = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const lines: string[] = [];
  for (const line of raw.split('\n')) {
    const prev = lines.length - 1;
    if ((line.startsWith(' ') || line.startsWith('\t')) && prev >= 0) lines[prev] += line.slice(1);
    else if (prev >= 0 && /ENCODING=QUOTED-PRINTABLE/i.test(lines[prev]) && lines[prev].endsWith('=')) lines[prev] = lines[prev].slice(0, -1) + line;
    else lines.push(line);
  }
  const cards: ContactInput[] = [];
  let cur: VLine[] | null = null;
  for (const line of lines) {
    const t = line.trim().toUpperCase();
    if (t === 'BEGIN:VCARD') cur = [];
    else if (t === 'END:VCARD') { if (cur) cards.push(cardToContact(cur)); cur = null; }
    else if (cur && line.trim()) { const l = parseLine(line); if (l) cur.push(l); }
  }
  return cards;
}

const escV = (s: string | null | undefined) => (s ?? '').replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/([,;])/g, '\\$1');

/** Folds a content line at 75 characters (continuation lines start with a space). */
function fold(line: string): string {
  if (line.length <= 75) return line;
  const parts = [line.slice(0, 75)];
  for (let i = 75; i < line.length; i += 74) parts.push(' ' + line.slice(i, i + 74));
  return parts.join('\r\n');
}

const STD_TEL: Record<string, string> = { mobile: 'CELL', iphone: 'IPHONE', work: 'WORK', home: 'HOME', main: 'MAIN', pager: 'PAGER', other: 'OTHER', 'work fax': 'WORK,FAX', 'home fax': 'HOME,FAX', fax: 'FAX' };
const STD_SIMPLE = ['work', 'home', 'other'];

/** Contacts → one .vcf text (vCard 3.0). Custom labels use Apple's itemN.X-ABLabel grouping. */
export function toVCards(contacts: ContactDetail[] | ContactInput[]): string {
  const out: string[] = [];
  for (const c of contacts) {
    let item = 0;
    const lines: string[] = ['BEGIN:VCARD', 'VERSION:3.0'];
    const custom = (prop: string, value: string, label: string) => {
      item++;
      lines.push(`item${item}.${prop}:${value}`, `item${item}.X-ABLabel:${escV(label)}`);
    };
    lines.push(`N:${[c.last_name, c.first_name, c.middle_name, c.name_prefix, c.name_suffix].map(escV).join(';')}`);
    const fn = (c as ContactDetail).full_name
      ?? ([c.name_prefix, c.first_name, c.middle_name, c.last_name, c.name_suffix].filter(Boolean).join(' ') || c.company_name || '');
    lines.push(`FN:${escV(fn)}`);
    if (c.nickname) lines.push(`NICKNAME:${escV(c.nickname)}`);
    if (c.company_name || c.department) lines.push(`ORG:${escV(c.company_name)};${escV(c.department)}`);
    if (c.job_title) lines.push(`TITLE:${escV(c.job_title)}`);
    for (const p of c.points) {
      const label = (p.label ?? '').trim();
      const lower = label.toLowerCase();
      const pref = p.is_primary ? ',pref' : '';
      if (p.type === 'PHONE' || p.type === 'MOBILE' || p.type === 'FAX') {
        const std = STD_TEL[lower] ?? (label ? null : p.type === 'MOBILE' ? 'CELL' : p.type === 'FAX' ? 'FAX' : 'VOICE');
        if (std) lines.push(`TEL;TYPE=${std}${pref}:${escV(p.value)}`);
        else custom('TEL', escV(p.value), label);
      } else if (p.type === 'EMAIL') {
        if (!label || STD_SIMPLE.includes(lower)) lines.push(`EMAIL;TYPE=INTERNET${label ? ',' + lower.toUpperCase() : ''}${pref}:${escV(p.value)}`);
        else custom('EMAIL;TYPE=INTERNET', escV(p.value), label);
      } else if (p.type === 'ADDRESS') {
        const v = `;;${escV(p.value)};;;;`;
        if (!label || STD_SIMPLE.includes(lower)) lines.push(`ADR${label ? ';TYPE=' + lower.toUpperCase() : ''}:${v}`);
        else custom('ADR', v, label);
      } else if (p.type === 'WEBSITE') {
        if (!label || STD_SIMPLE.includes(lower)) lines.push(`URL${label ? ';TYPE=' + lower.toUpperCase() : ''}:${p.value}`);
        else custom('URL', p.value, label);
      } else {
        lines.push(`X-SOCIALPROFILE${label ? ';TYPE=' + label.toLowerCase().replace(/[^a-z0-9-]/g, '') : ''}:${escV(p.value)}`);
      }
    }
    for (const d of c.important_dates) {
      const noYear = d.date.startsWith('--');
      if (d.label === 'birthday') lines.push(noYear ? `BDAY;X-APPLE-OMIT-YEAR=1604:1604${d.date.slice(1)}` : `BDAY;VALUE=date:${d.date}`);
      else custom('X-ABDATE', noYear ? `1604${d.date.slice(1)}` : d.date, d.label === 'anniversary' ? '_$!<Anniversary>!$_' : d.label);
    }
    for (const r of c.related_people) custom('X-ABRELATEDNAMES', escV(r.name), r.label);
    const tags = (c as ContactDetail).tags?.map((t) => t.tag_name) ?? c.tag_names ?? [];
    if (tags.length) lines.push(`CATEGORIES:${tags.map(escV).join(',')}`);
    if (c.notes) lines.push(`NOTE:${escV(c.notes)}`);
    const photo = /^data:image\/(\w+);base64,(.*)$/.exec(c.photo_data ?? '');
    if (photo) lines.push(`PHOTO;ENCODING=b;TYPE=${photo[1].toUpperCase()}:${photo[2]}`);
    lines.push('END:VCARD');
    out.push(lines.map(fold).join('\r\n'));
  }
  return out.join('\r\n') + (out.length ? '\r\n' : '');
}

// ───────────────────────────── CSV ─────────────────────────────

const SEP = ' ::: ';
const splitMulti = (s: string) => s.split(':::').map((x) => x.trim()).filter(Boolean);

/** Google / Outlook CSV text → contacts. Columns are matched by header name, so order and extra columns do not matter. */
export function parseContactsCsv(text: string): ContactInput[] {
  const rows = parseCsv(text);
  if (rows.length < 2) return [];
  const head = rows[0].map((h) => h.trim().toLowerCase());
  const col = (...names: string[]) => names.map((n) => head.indexOf(n.toLowerCase())).find((i) => i >= 0) ?? -1;
  const single: Record<string, number> = {
    first_name: col('First Name', 'Given Name'), middle_name: col('Middle Name', 'Additional Name'),
    last_name: col('Last Name', 'Family Name'), name_prefix: col('Name Prefix', 'Title'), name_suffix: col('Name Suffix', 'Suffix'),
    nickname: col('Nickname'), company_name: col('Organization Name', 'Organization 1 - Name', 'Company'),
    job_title: col('Organization Title', 'Organization 1 - Title', 'Job Title'),
    department: col('Organization Department', 'Organization 1 - Department', 'Department'), notes: col('Notes'),
  };
  const fullName = col('Name', 'Full Name', 'Display Name');
  const birthday = col('Birthday');
  const labels = col('Labels', 'Group Membership', 'Categories');
  // numbered groups: "E-mail 1 - Value", "Phone 2 - Label", "Address 1 - Street" …
  const groups = new Map<string, Record<string, number>>();
  head.forEach((h, i) => {
    const m = /^(e-mail|phone|address|website|relation|event|im) (\d+) - (.+)$/.exec(h);
    if (!m) return;
    const key = `${m[1]}|${m[2]}`;
    groups.set(key, { ...(groups.get(key) ?? {}), [m[3] === 'type' ? 'label' : m[3]]: i });
  });
  // Outlook / simple flat columns: header → [type, label]
  const flat: [string, PointType, string | null][] = [
    ['E-mail Address', 'EMAIL', null], ['E-mail 2 Address', 'EMAIL', null], ['E-mail 3 Address', 'EMAIL', null], ['Email', 'EMAIL', null],
    ['Mobile Phone', 'MOBILE', 'mobile'], ['Mobile', 'MOBILE', 'mobile'], ['Business Phone', 'PHONE', 'work'], ['Business Phone 2', 'PHONE', 'work'],
    ['Home Phone', 'PHONE', 'home'], ['Primary Phone', 'PHONE', 'main'], ['Company Main Phone', 'PHONE', 'main'], ['Other Phone', 'PHONE', 'other'],
    ['Phone', 'PHONE', null], ['Business Fax', 'FAX', 'work fax'], ['Home Fax', 'FAX', 'home fax'], ['Web Page', 'WEBSITE', null], ['Website', 'WEBSITE', null],
  ];
  const flatAddr = ['Business', 'Home', 'Other'].map((k) => ({
    label: k === 'Business' ? 'work' : k.toLowerCase(),
    street: col(`${k} Street`), city: col(`${k} City`), region: col(`${k} State`), postal: col(`${k} Postal Code`), country: col(`${k} Country/Region`, `${k} Country`),
  }));

  return rows.slice(1).map((r) => {
    const get = (i: number | undefined) => (i === undefined || i < 0 ? '' : (r[i] ?? '').trim());
    const c: ContactInput = { important_dates: [], related_people: [], points: [] };
    for (const [k, i] of Object.entries(single)) (c as unknown as Record<string, string | null>)[k] = clean(get(i));
    if (!c.first_name && !c.last_name && get(fullName)) {
      const parts = get(fullName).split(/\s+/);
      c.first_name = parts.length > 1 ? parts.slice(0, -1).join(' ') : parts[0];
      c.last_name = parts.length > 1 ? parts[parts.length - 1] : null;
    }
    const bd = normalizeDate(get(birthday));
    if (bd) c.important_dates.push({ label: 'birthday', date: bd });
    const tags = splitMulti(get(labels));
    if (tags.some((t) => t.toLowerCase() === '* starred')) c.is_favorite = true;
    c.tag_names = tags.filter((t) => !t.startsWith('*'));

    groups.forEach((g, key) => {
      const kind = key.split('|')[0];
      const label = clean(appleLabel(get(g.label).replace(/^\*\s*/, ''))) ?? null;
      const lower = label?.toLowerCase() ?? null;
      if (kind === 'address') {
        const formatted = get(g.formatted);
        const city = [get(g.city), [get(g.region), get(g['postal code'])].filter(Boolean).join(' ')].filter(Boolean).join(', ');
        const value = formatted || [get(g.street), get(g['extended address']), get(g['po box']) ? `PO Box ${get(g['po box'])}` : '', city, get(g.country)]
          .filter(Boolean).join('\n');
        if (value) c.points.push({ type: 'ADDRESS', label: lower, value });
        return;
      }
      for (const value of splitMulti(get(g.value))) {
        if (kind === 'e-mail') c.points.push({ type: 'EMAIL', label: lower, value });
        else if (kind === 'phone') c.points.push({ type: phoneType(lower), label: lower, value });
        else if (kind === 'website') c.points.push({ type: 'WEBSITE', label: lower, value });
        else if (kind === 'im') c.points.push({ type: 'OTHER', label, value });
        else if (kind === 'relation') c.related_people.push({ label: lower ?? 'other', name: value });
        else if (kind === 'event') {
          const d = normalizeDate(value);
          if (d) c.important_dates.push({ label: lower ?? 'other', date: d });
        }
      }
    });
    for (const [h, type, label] of flat) {
      const v = get(col(h));
      if (v) c.points.push({ type, label, value: v });
    }
    for (const a of flatAddr) {
      const city = [get(a.city), [get(a.region), get(a.postal)].filter(Boolean).join(' ')].filter(Boolean).join(', ');
      const value = [get(a.street), city, get(a.country)].filter(Boolean).join('\n');
      if (value) c.points.push({ type: 'ADDRESS', label: a.label, value });
    }
    return c;
  }).filter((c) => c.first_name || c.last_name || c.company_name || c.nickname || c.points.length > 0);
}

const csvCell = (s: string | null | undefined) => {
  const v = s ?? '';
  return /[",\n\r]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
};

/** Contacts → CSV in the Google Contacts layout (also opens in Excel). Adds "BPS Customer" for customer contacts. */
export function toContactsCsv(contacts: ContactDetail[]): string {
  const count = (pick: (c: ContactDetail) => number) => Math.max(1, ...contacts.map(pick));
  const isPhone = (p: ContactPoint) => p.type === 'PHONE' || p.type === 'MOBILE' || p.type === 'FAX';
  const nEmail = count((c) => c.points.filter((p) => p.type === 'EMAIL').length);
  const nPhone = count((c) => c.points.filter(isPhone).length);
  const nAddr = count((c) => c.points.filter((p) => p.type === 'ADDRESS').length);
  const nWeb = count((c) => c.points.filter((p) => p.type === 'WEBSITE').length);
  const nIm = count((c) => c.points.filter((p) => p.type === 'OTHER').length);
  const nRel = count((c) => c.related_people.length);
  const nEvt = count((c) => c.important_dates.filter((d) => d.label !== 'birthday').length);
  const header = ['First Name', 'Middle Name', 'Last Name', 'Name Prefix', 'Name Suffix', 'Nickname', 'Organization Name',
    'Organization Title', 'Organization Department', 'Birthday', 'Notes', 'Labels'];
  const pairs = (name: string, n: number) => Array.from({ length: n }, (_, i) => [`${name} ${i + 1} - Label`, `${name} ${i + 1} - Value`]).flat();
  header.push(...pairs('E-mail', nEmail), ...pairs('Phone', nPhone));
  for (let i = 1; i <= nAddr; i++) header.push(`Address ${i} - Label`, `Address ${i} - Formatted`);
  header.push(...pairs('Website', nWeb), ...pairs('IM', nIm), ...pairs('Relation', nRel), ...pairs('Event', nEvt), 'BPS Customer');
  const fill = (vals: [string | null, string][], n: number) =>
    Array.from({ length: n }, (_, i) => [vals[i]?.[0] ?? '', vals[i]?.[1] ?? '']).flat();
  const lines = [header.map(csvCell).join(',')];
  for (const c of contacts) {
    const pts = (f: (p: ContactPoint) => boolean): [string | null, string][] => c.points.filter(f).map((p) => [p.label, p.value]);
    const labels = [...(c.is_favorite ? ['* starred'] : []), ...c.tags.map((t) => t.tag_name)].join(SEP);
    const row = [c.first_name, c.middle_name, c.last_name, c.name_prefix, c.name_suffix, c.nickname, c.company_name, c.job_title,
      c.department, c.important_dates.find((d) => d.label === 'birthday')?.date ?? '', c.notes, labels,
      ...fill(pts((p) => p.type === 'EMAIL'), nEmail), ...fill(pts(isPhone), nPhone), ...fill(pts((p) => p.type === 'ADDRESS'), nAddr),
      ...fill(pts((p) => p.type === 'WEBSITE'), nWeb), ...fill(pts((p) => p.type === 'OTHER'), nIm),
      ...fill(c.related_people.map((r) => [r.label, r.name]), nRel),
      ...fill(c.important_dates.filter((d) => d.label !== 'birthday').map((d) => [d.label, d.date]), nEvt),
      c.kind === 'CUSTOMER' ? [c.customer_number, c.customer_name].filter(Boolean).join(' ') : ''];
    lines.push(row.map((v) => csvCell(v ?? '')).join(','));
  }
  return '\uFEFF' + lines.join('\r\n') + '\r\n';
}

/** Reads a picked file as contacts: .vcf / .vcard as vCard, anything else as CSV. */
export function parseContactsFile(name: string, text: string): ContactInput[] {
  return /\.(vcf|vcard)$/i.test(name) || /^\s*BEGIN:VCARD/i.test(text) ? parseVCards(text) : parseContactsCsv(text);
}
