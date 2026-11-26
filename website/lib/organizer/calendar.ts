/**
 * Organizer › Calendar: shared types, calendar colours (theme tokens only) and the side-by-side layout of overlapping
 * timed events in the Day and Week views. Dates, ranges, repeats and labels come from the database
 * (org_calendar_view_get); nothing here does date arithmetic.
 */

export type CalendarView = 'day' | 'week' | 'month' | 'agenda';
export type CalendarColor = 'accent' | 'blue' | 'green' | 'amber' | 'red' | 'gray';
export type RepeatFreq = 'NONE' | 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
export type Scope = 'ONE' | 'FOLLOWING' | 'ALL';

export interface CalendarRow {
  calendar_id: number;
  calendar_name: string;
  calendar_color: CalendarColor;
  visibility: 'SHARED' | 'PRIVATE';
  is_owner: boolean;
  owner_name: string | null;
}

export interface CalendarsData {
  time_zone: string;
  today: string;
  can_edit: boolean;
  can_delete: boolean;
  calendars: CalendarRow[];
}

export interface CalDay {
  date: string;
  day: number;
  dow: number;
  label: string;
  in_month: boolean;
  is_today: boolean;
}

export interface CalItem {
  key: string;
  kind: 'EVENT' | 'PRODUCTION' | 'DELIVERY';
  event_id: number | null;
  production_run_id: number | null;
  occurrence_date: string;
  calendar_id: number | null;
  color: CalendarColor;
  title: string;
  location: string | null;
  all_day: boolean;
  start_date: string;
  end_date: string;
  start_time: string | null;
  end_time: string | null;
  time_label: string;
  short_label: string | null;
  day_label: string;
  is_recurring: boolean;
  run_status?: string;
}

export interface ViewData {
  view: CalendarView | 'mini' | 'search';
  today: string;
  anchor: string;
  from: string;
  to: string;
  prev: string;
  next: string;
  title: string;
  time_zone: string;
  now_minutes: number;
  days: CalDay[];
  events: CalItem[];
}

export interface EventDetail {
  event_id?: number;
  calendar_id: number | null;
  title: string;
  location: string | null;
  notes: string | null;
  all_day: boolean;
  start_date: string;
  end_date: string;
  start_time: string | null;
  end_time: string | null;
  repeat_freq: RepeatFreq;
  repeat_interval: number;
  repeat_days: number[];
  repeat_until: string | null;
  repeat_count: number | null;
  repeat_label?: string | null;
  created_by_name?: string | null;
  updated_by_name?: string | null;
}

export const CALENDAR_COLORS: CalendarColor[] = ['accent', 'blue', 'green', 'amber', 'red', 'gray'];
export const COLOR_NAMES: Record<CalendarColor, string> = {
  accent: 'Theme accent', blue: 'Blue', green: 'Green', amber: 'Amber', red: 'Red', gray: 'Grey',
};

/** Token classes per calendar colour: dot/fill, soft background, left bar, border. Written out so Tailwind keeps them. */
export const COLOR_CLASS: Record<CalendarColor, { dot: string; soft: string; bar: string; border: string }> = {
  accent: { dot: 'bg-primary', soft: 'bg-primary/15', bar: 'border-l-primary', border: 'border-primary' },
  blue: { dot: 'bg-info', soft: 'bg-info/15', bar: 'border-l-info', border: 'border-info' },
  green: { dot: 'bg-success', soft: 'bg-success/15', bar: 'border-l-success', border: 'border-success' },
  amber: { dot: 'bg-warning', soft: 'bg-warning/15', bar: 'border-l-warning', border: 'border-warning' },
  red: { dot: 'bg-destructive', soft: 'bg-destructive/15', bar: 'border-l-destructive', border: 'border-destructive' },
  gray: { dot: 'bg-muted-foreground', soft: 'bg-muted-foreground/15', bar: 'border-l-muted-foreground', border: 'border-muted-foreground' },
};

/** 'HH:MM' → minutes after midnight. */
export function toMinutes(hhmm: string | null): number {
  if (!hhmm) return 0;
  const [h, m] = hhmm.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

/** Minutes after midnight → 'HH:MM' (capped at 23:59). */
export function fromMinutes(min: number): string {
  const v = Math.max(0, Math.min(23 * 60 + 59, Math.round(min)));
  return `${String(Math.floor(v / 60)).padStart(2, '0')}:${String(v % 60).padStart(2, '0')}`;
}

/** True when the item is drawn in the time grid (timed and within one day); otherwise it goes in the all-day row. */
export function isTimedInDay(e: CalItem): boolean {
  return !e.all_day && e.start_date === e.end_date && e.kind === 'EVENT';
}

/** Items that cover a day (ISO date strings compare in date order). */
export function itemsOnDay(items: CalItem[], date: string): CalItem[] {
  return items.filter((e) => e.start_date <= date && e.end_date >= date);
}

export interface Placed { item: CalItem; top: number; height: number; col: number; cols: number }

/**
 * Places one day's timed events: overlapping events share the width side by side, as in Google and Apple Calendar.
 * Events are grouped into clusters that overlap in time; within a cluster each event takes the first free column.
 * minHeight keeps a short event readable (in minutes).
 */
export function layoutDay(items: CalItem[], minHeight = 20): Placed[] {
  const evs = items
    .map((item) => {
      const s = toMinutes(item.start_time);
      return { item, s, e: Math.max(toMinutes(item.end_time), s + minHeight) };
    })
    .sort((a, b) => a.s - b.s || b.e - a.e);
  const out: Placed[] = [];
  let cluster: { item: CalItem; s: number; e: number; col: number }[] = [];
  let clusterEnd = -1;
  const flush = () => {
    const cols = cluster.reduce((m, c) => Math.max(m, c.col + 1), 0);
    for (const c of cluster) out.push({ item: c.item, top: c.s, height: c.e - c.s, col: c.col, cols });
    cluster = [];
  };
  for (const ev of evs) {
    if (cluster.length > 0 && ev.s >= clusterEnd) flush();
    const colEnds: number[] = [];
    for (const c of cluster) colEnds[c.col] = Math.max(colEnds[c.col] ?? -1, c.e);
    let col = 0;
    while (colEnds[col] !== undefined && colEnds[col] > ev.s) col++;
    cluster.push({ ...ev, col });
    clusterEnd = Math.max(clusterEnd, ev.e);
  }
  if (cluster.length > 0) flush();
  return out;
}
