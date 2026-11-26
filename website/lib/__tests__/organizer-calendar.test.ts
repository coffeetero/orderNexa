import { describe, expect, it } from 'vitest';
import { fromMinutes, isTimedInDay, itemsOnDay, layoutDay, toMinutes, type CalItem } from '@/lib/organizer/calendar';

const item = (key: string, start: string, end: string, extra: Partial<CalItem> = {}): CalItem => ({
  key, kind: 'EVENT', event_id: 1, production_run_id: null, occurrence_date: '2026-11-25', calendar_id: 1, color: 'blue',
  title: key, location: null, all_day: false, start_date: '2026-11-25', end_date: '2026-11-25', start_time: start, end_time: end,
  time_label: '', short_label: null, day_label: '', is_recurring: false, ...extra,
});

describe('calendar time helpers', () => {
  it('converts between HH:MM and minutes, capping at 23:59', () => {
    expect(toMinutes('07:30')).toBe(450);
    expect(fromMinutes(450)).toBe('07:30');
    expect(fromMinutes(24 * 60 + 30)).toBe('23:59');
    expect(toMinutes(null)).toBe(0);
  });
});

describe('layoutDay', () => {
  it('gives separate events the full width', () => {
    const p = layoutDay([item('a', '07:00', '08:00'), item('b', '09:00', '10:00')]);
    expect(p.map((x) => [x.item.key, x.col, x.cols])).toEqual([['a', 0, 1], ['b', 0, 1]]);
  });

  it('puts overlapping events side by side and reuses a freed column', () => {
    const p = layoutDay([item('a', '07:00', '09:00'), item('b', '07:30', '08:00'), item('c', '08:00', '08:30')]);
    const byKey = Object.fromEntries(p.map((x) => [x.item.key, x]));
    expect(byKey.a.col).toBe(0);
    expect(byKey.b.col).toBe(1);
    expect(byKey.c.col).toBe(1);
    expect(p.every((x) => x.cols === 2)).toBe(true);
  });

  it('keeps very short events readable', () => {
    const [p] = layoutDay([item('a', '07:00', '07:00')]);
    expect(p.height).toBe(20);
  });
});

describe('day membership', () => {
  it('finds multi-day items on each day they cover and keeps them out of the time grid', () => {
    const multi = item('m', '22:00', '02:00', { end_date: '2026-11-26' });
    expect(itemsOnDay([multi], '2026-11-26')).toHaveLength(1);
    expect(itemsOnDay([multi], '2026-11-27')).toHaveLength(0);
    expect(isTimedInDay(multi)).toBe(false);
    expect(isTimedInDay(item('x', '07:00', '08:00'))).toBe(true);
    expect(isTimedInDay(item('p', '07:00', '08:00', { kind: 'PRODUCTION' }))).toBe(false);
  });
});
