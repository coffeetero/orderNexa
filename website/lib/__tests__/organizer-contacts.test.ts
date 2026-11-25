import { describe, expect, it } from 'vitest';
import {
  normalizeDate, parseContactsCsv, parseContactsFile, parseVCards, phoneType, toContactsCsv, toVCards, type ContactDetail,
} from '@/lib/organizer/contacts';

const IPHONE_VCF = [
  'BEGIN:VCARD',
  'VERSION:3.0',
  'PRODID:-//Apple Inc.//iPhone OS 17.0//EN',
  'N:Lovelace;Ada;M;Dr.;',
  'FN:Dr. Ada M Lovelace',
  'NICKNAME:Ada',
  'ORG:Analytical Engines;Research',
  'TITLE:Engineer',
  'EMAIL;type=INTERNET;type=WORK;type=pref:ada@example.test',
  'TEL;type=CELL;type=VOICE;type=pref:(555) 010-1234',
  'TEL;type=WORK;type=FAX:555 010 2222',
  'item1.TEL:555 010 3333',
  'item1.X-ABLabel:Studio',
  'item2.ADR;type=HOME;type=pref:;;1 Main St;London;;N1 1AA;United Kingdom',
  'item2.X-ABADR:gb',
  'item3.URL;type=pref:https://ada.example.test',
  'item3.X-ABLabel:_$!<HomePage>!$_',
  'BDAY;X-APPLE-OMIT-YEAR=1604:1604-12-10',
  'item4.X-ABDATE:2001-06-01',
  'item4.X-ABLabel:_$!<Anniversary>!$_',
  'item5.X-ABRELATEDNAMES:Lord Byron',
  'item5.X-ABLabel:_$!<Father>!$_',
  'X-SOCIALPROFILE;type=linkedin:https://linkedin.com/in/ada',
  'NOTE:Line one\\nLine two\\, with comma',
  'CATEGORIES:Suppliers,VIP',
  'END:VCARD',
  'BEGIN:VCARD',
  'VERSION:2.1',
  'N;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:M=C3=BCller;J=C3=B6rg;;;',
  'TEL;HOME:555-0100',
  'END:VCARD',
].join('\r\n');

describe('vCard import', () => {
  const [ada, jorg] = parseVCards(IPHONE_VCF);

  it('reads names, organization and title', () => {
    expect(ada).toMatchObject({ first_name: 'Ada', last_name: 'Lovelace', middle_name: 'M', name_prefix: 'Dr.', nickname: 'Ada',
      company_name: 'Analytical Engines', department: 'Research', job_title: 'Engineer' });
  });

  it('reads labelled phones, emails, addresses, websites and social profiles', () => {
    expect(ada.points).toEqual([
      { type: 'EMAIL', label: 'work', value: 'ada@example.test', is_primary: true },
      { type: 'MOBILE', label: 'mobile', value: '(555) 010-1234', is_primary: true },
      { type: 'FAX', label: 'work fax', value: '555 010 2222', is_primary: false },
      { type: 'PHONE', label: 'studio', value: '555 010 3333', is_primary: false },
      { type: 'ADDRESS', label: 'home', value: '1 Main St\nLondon, N1 1AA\nUnited Kingdom', is_primary: true },
      { type: 'WEBSITE', label: 'homepage', value: 'https://ada.example.test' },
      { type: 'OTHER', label: 'Linkedin', value: 'https://linkedin.com/in/ada' },
    ]);
  });

  it('reads birthday without a year, other dates, related names, notes and categories', () => {
    expect(ada.important_dates).toEqual([{ label: 'birthday', date: '--12-10' }, { label: 'anniversary', date: '2001-06-01' }]);
    expect(ada.related_people).toEqual([{ label: 'father', name: 'Lord Byron' }]);
    expect(ada.notes).toBe('Line one\nLine two, with comma');
    expect(ada.tag_names).toEqual(['Suppliers', 'VIP']);
  });

  it('decodes vCard 2.1 quoted-printable', () => {
    expect(jorg).toMatchObject({ first_name: 'Jörg', last_name: 'Müller' });
    expect(jorg.points[0]).toMatchObject({ type: 'PHONE', label: 'home', value: '555-0100' });
  });

  it('unfolds long lines and splits FN when there is no N', () => {
    const [c] = parseVCards('BEGIN:VCARD\nVERSION:4.0\nFN:Grace Brewster\n  Hopper\nEMAIL:grace@example.test\nEND:VCARD');
    expect(c).toMatchObject({ first_name: 'Grace Brewster', last_name: 'Hopper' });
  });
});

const detail = (over: Partial<ContactDetail> = {}): ContactDetail => ({
  contact_id: 1, full_name: 'Ada Lovelace', kind: 'COMPANY', customer_id: null, customer_name: null, customer_number: null,
  has_photo: false, tags: [{ tag_id: 9, tag_name: 'VIP', tag_color: 'gray' }], created_at: '', updated_at: '',
  created_by_name: null, updated_by_name: null, first_name: 'Ada', last_name: 'Lovelace', company_name: 'Engines; Ltd',
  notes: 'Two\nlines', is_favorite: true,
  important_dates: [{ label: 'birthday', date: '--12-10' }, { label: 'anniversary', date: '2001-06-01' }],
  related_people: [{ label: 'father', name: 'Lord Byron' }],
  points: [
    { type: 'MOBILE', label: 'mobile', value: '555 0101', is_primary: true },
    { type: 'PHONE', label: 'studio', value: '555 0102' },
    { type: 'EMAIL', label: 'work', value: 'ada@example.test' },
    { type: 'ADDRESS', label: 'home', value: '1 Main St\nLondon' },
    { type: 'OTHER', label: 'LinkedIn', value: 'ada-l' },
  ],
  ...over,
});

describe('vCard export', () => {
  it('round-trips through the importer', () => {
    const vcf = toVCards([detail()]);
    expect(vcf).toContain('TEL;TYPE=CELL,pref:555 0101');
    expect(vcf).toContain('ORG:Engines\\; Ltd;');
    const [back] = parseVCards(vcf);
    expect(back).toMatchObject({ first_name: 'Ada', last_name: 'Lovelace', company_name: 'Engines; Ltd', notes: 'Two\nlines', tag_names: ['VIP'] });
    expect(back.important_dates).toEqual(detail().important_dates);
    expect(back.related_people).toEqual(detail().related_people);
    expect(back.points.map((p) => [p.type, p.label, p.value])).toEqual([
      ['MOBILE', 'mobile', '555 0101'], ['PHONE', 'studio', '555 0102'], ['EMAIL', 'work', 'ada@example.test'],
      ['ADDRESS', 'home', '1 Main St\nLondon'], ['OTHER', 'Linkedin', 'ada-l'],
    ]);
  });

  it('folds lines longer than 75 characters', () => {
    const vcf = toVCards([detail({ notes: 'x'.repeat(200) })]);
    expect(vcf.split('\r\n').every((l) => l.length <= 75)).toBe(true);
    expect(parseVCards(vcf)[0].notes).toBe('x'.repeat(200));
  });
});

const GOOGLE_CSV = [
  'First Name,Middle Name,Last Name,Phonetic First Name,Name Prefix,Name Suffix,Nickname,File As,Organization Name,Organization Title,Organization Department,Birthday,Notes,Photo,Labels,E-mail 1 - Label,E-mail 1 - Value,E-mail 2 - Label,E-mail 2 - Value,Phone 1 - Label,Phone 1 - Value,Address 1 - Label,Address 1 - Formatted,Address 1 - Street,Address 1 - City,Website 1 - Label,Website 1 - Value,Relation 1 - Label,Relation 1 - Value,Event 1 - Label,Event 1 - Value',
  'Ada,,Lovelace,,,,,,Engines,Engineer,,--12-10,"Met at, the fair",,* myContacts ::: * starred ::: Suppliers,* Work,ada@example.test,Home,ada@home.test ::: ada2@home.test,Mobile,+1 555 0101,Home,"1 Main St\nLondon",1 Main St,London,Profile,https://ada.test,Spouse,William King,Anniversary,1835-07-08',
  ',,,,,,,,Flour Co,,,,,,,,,,,,,,,,,,,,,,',
  ',,,,,,,,,,,,,,,,,,,,,,,,,,,,,,',
].join('\n');

describe('CSV import', () => {
  it('reads the Google Contacts layout', () => {
    const rows = parseContactsCsv(GOOGLE_CSV);
    expect(rows).toHaveLength(2);
    const [ada, flour] = rows;
    expect(ada).toMatchObject({ first_name: 'Ada', last_name: 'Lovelace', company_name: 'Engines', job_title: 'Engineer',
      notes: 'Met at, the fair', is_favorite: true, tag_names: ['Suppliers'] });
    expect(ada.points).toEqual([
      { type: 'EMAIL', label: 'work', value: 'ada@example.test' },
      { type: 'EMAIL', label: 'home', value: 'ada@home.test' },
      { type: 'EMAIL', label: 'home', value: 'ada2@home.test' },
      { type: 'MOBILE', label: 'mobile', value: '+1 555 0101' },
      { type: 'ADDRESS', label: 'home', value: '1 Main St\nLondon' },
      { type: 'WEBSITE', label: 'profile', value: 'https://ada.test' },
    ]);
    expect(ada.important_dates).toEqual([{ label: 'birthday', date: '--12-10' }, { label: 'anniversary', date: '1835-07-08' }]);
    expect(ada.related_people).toEqual([{ label: 'spouse', name: 'William King' }]);
    expect(flour.company_name).toBe('Flour Co');
  });

  it('reads older Google and Outlook headers', () => {
    const old = parseContactsCsv('Name,Given Name,Family Name,E-mail 1 - Type,E-mail 1 - Value,Organization 1 - Name\nBob B,Bob,Baker,* Work,bob@example.test,Bakery\n');
    expect(old[0]).toMatchObject({ first_name: 'Bob', last_name: 'Baker', company_name: 'Bakery' });
    expect(old[0].points).toEqual([{ type: 'EMAIL', label: 'work', value: 'bob@example.test' }]);
    const outlook = parseContactsCsv('First Name,Last Name,Company,Job Title,E-mail Address,Mobile Phone,Business Fax,Business Street,Business City,Business State,Business Postal Code\nCy,Cook,Diner,Chef,cy@example.test,555-1,555-2,9 High St,Newark,NJ,07102\n');
    expect(outlook[0]).toMatchObject({ first_name: 'Cy', company_name: 'Diner', job_title: 'Chef' });
    expect(outlook[0].points).toEqual([
      { type: 'EMAIL', label: null, value: 'cy@example.test' },
      { type: 'MOBILE', label: 'mobile', value: '555-1' },
      { type: 'FAX', label: 'work fax', value: '555-2' },
      { type: 'ADDRESS', label: 'work', value: '9 High St\nNewark, NJ 07102' },
    ]);
  });
});

describe('CSV export', () => {
  it('writes the Google layout and reads back', () => {
    const csv = toContactsCsv([detail(), detail({ contact_id: 2, kind: 'CUSTOMER', customer_number: '15700', customer_name: 'Featherstone', first_name: 'Bob', points: [], tags: [], is_favorite: false })]);
    expect(csv.startsWith('﻿First Name,')).toBe(true);
    expect(csv).toContain('15700 Featherstone');
    const [ada, bob] = parseContactsCsv(csv);
    expect(ada).toMatchObject({ first_name: 'Ada', company_name: 'Engines; Ltd', notes: 'Two\nlines', is_favorite: true, tag_names: ['VIP'] });
    expect(ada.points.map((p) => [p.type, p.value])).toEqual([
      ['EMAIL', 'ada@example.test'], ['MOBILE', '555 0101'], ['PHONE', '555 0102'], ['ADDRESS', '1 Main St\nLondon'], ['OTHER', 'ada-l'],
    ]);
    expect(ada.important_dates).toEqual(detail().important_dates);
    expect(bob.first_name).toBe('Bob');
  });
});

describe('helpers', () => {
  it('normalizes dates', () => {
    expect(normalizeDate('1980-05-12')).toBe('1980-05-12');
    expect(normalizeDate('19800512')).toBe('1980-05-12');
    expect(normalizeDate('--0512')).toBe('--05-12');
    expect(normalizeDate('1604-05-12')).toBe('--05-12');
    expect(normalizeDate('5/12/1980')).toBe('1980-05-12');
    expect(normalizeDate('soon')).toBeNull();
  });
  it('maps phone labels to types', () => {
    expect(phoneType('Mobile')).toBe('MOBILE');
    expect(phoneType('iPhone')).toBe('MOBILE');
    expect(phoneType('work fax')).toBe('FAX');
    expect(phoneType('work')).toBe('PHONE');
    expect(phoneType(null)).toBe('PHONE');
  });
  it('picks the parser by file', () => {
    expect(parseContactsFile('a.vcf', IPHONE_VCF)).toHaveLength(2);
    expect(parseContactsFile('a.csv', GOOGLE_CSV)).toHaveLength(2);
  });
});
