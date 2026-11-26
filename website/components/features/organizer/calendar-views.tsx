'use client';

import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, Repeat } from 'lucide-react';
import { cn } from '@/lib/utils';
import {
  COLOR_CLASS, fromMinutes, isTimedInDay, itemsOnDay, layoutDay, type CalDay, type CalItem, type ViewData,
} from '@/lib/organizer/calendar';

const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const HOUR_PX = 44;
const SCROLL_TO_HOUR = 5; // bakeries start early
const hourLabel = (h: number) => (h === 0 ? '' : `${h % 12 === 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}`);

export type OpenItem = (item: CalItem) => void;
export type CreateAt = (date: string, startTime: string | null) => void;

/** One event in a month cell, an all-day row or a list. Production runs are drawn dashed (read-only). */
export function EventChip({ item, onOpen, showTime = true, className }: {
  item: CalItem; onOpen: OpenItem; showTime?: boolean; className?: string;
}) {
  const c = COLOR_CLASS[item.color] ?? COLOR_CLASS.gray;
  const banner = item.all_day || item.start_date !== item.end_date;
  const prod = item.kind !== 'EVENT';
  return (
    <button
      type="button"
      onClick={(e) => { e.stopPropagation(); onOpen(item); }}
      title={`${item.title} · ${item.time_label}${item.location ? ` · ${item.location}` : ''}`}
      className={cn(
        'flex w-full min-w-0 items-center gap-1.5 rounded px-1.5 text-left text-xs leading-[18px] hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
        prod ? 'border border-dashed border-border text-muted-foreground'
          : banner ? cn('border-l-[3px] text-foreground', c.soft, c.bar) : 'text-foreground',
        className,
      )}
    >
      {!prod && !banner && <span className={cn('h-2 w-2 shrink-0 rounded-full', c.dot)} />}
      {showTime && !banner && item.short_label && <span className="shrink-0 text-muted-foreground">{item.short_label}</span>}
      <span className="truncate">{item.title}</span>
    </button>
  );
}

/** The small month picker in the left rail. */
export function MiniMonth({ data, selFrom, selTo, onPick, onMove }: {
  data: ViewData | null; selFrom: string | null; selTo: string | null; onPick: (date: string) => void; onMove: (date: string) => void;
}) {
  if (!data) return <div className="h-[13.5rem]" />;
  return (
    <div className="text-xs">
      <div className="mb-1 flex items-center justify-between">
        <button type="button" aria-label="Previous month" className="flex h-7 w-7 items-center justify-center rounded hover:bg-accent" onClick={() => onMove(data.prev)}>
          <ChevronLeft className="h-4 w-4" />
        </button>
        <span className="text-sm font-semibold">{data.title}</span>
        <button type="button" aria-label="Next month" className="flex h-7 w-7 items-center justify-center rounded hover:bg-accent" onClick={() => onMove(data.next)}>
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
      <div className="grid grid-cols-7 text-center">
        {DOW.map((d) => <div key={d} className="py-0.5 text-[11px] font-medium text-muted-foreground">{d[0]}</div>)}
        {data.days.map((d) => {
          const sel = selFrom !== null && selTo !== null && d.date >= selFrom && d.date <= selTo;
          return (
            <button
              key={d.date}
              type="button"
              aria-label={d.label}
              onClick={() => onPick(d.date)}
              className={cn('mx-auto my-px flex h-7 w-7 items-center justify-center rounded-full tabular-nums hover:bg-accent',
                !d.in_month && 'text-muted-foreground', sel && !d.is_today && 'bg-primary/10',
                d.is_today && 'bg-primary font-semibold text-primary-foreground hover:bg-primary/90')}
            >
              {d.day}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** Month grid: whole weeks; each cell shows as many events as fit and "+n more" (opens the day). */
export function MonthView({ data, onOpen, onCreate, onDay }: {
  data: ViewData; onOpen: OpenItem; onCreate: CreateAt; onDay: (date: string) => void;
}) {
  const gridRef = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState(3);
  const weeks = data.days.length / 7;
  useLayoutEffect(() => {
    const el = gridRef.current;
    if (!el) return;
    const measure = () => setFit(Math.max(1, Math.floor((el.clientHeight / weeks - 27) / 19)));
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [weeks]);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="grid grid-cols-7 border-b">
        {DOW.map((d) => <div key={d} className="px-2 py-1.5 text-xs font-medium text-muted-foreground">{d}</div>)}
      </div>
      <div ref={gridRef} className="grid min-h-0 flex-1 grid-cols-7" style={{ gridTemplateRows: `repeat(${weeks}, minmax(0, 1fr))` }}>
        {data.days.map((d) => {
          const items = itemsOnDay(data.events, d.date);
          const shown = items.slice(0, fit);
          const more = items.length - shown.length;
          return (
            <div
              key={d.date}
              role="gridcell"
              aria-label={d.label}
              onClick={() => onCreate(d.date, null)}
              className={cn('min-w-0 cursor-pointer overflow-hidden border-b border-r px-1 pb-0.5 pt-0.5 [&:nth-child(7n)]:border-r-0',
                !d.in_month && 'bg-muted/40')}
            >
              <div className="mb-0.5 flex items-center justify-between gap-1">
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); onDay(d.date); }}
                  aria-label={`Open ${d.label}`}
                  className={cn('inline-flex h-[22px] min-w-[22px] items-center justify-center rounded-full px-1 text-xs font-medium tabular-nums hover:bg-accent',
                    !d.in_month && 'text-muted-foreground', d.is_today && 'bg-primary font-semibold text-primary-foreground hover:bg-primary/90')}
                >
                  {d.day}
                </button>
                {more > 0 && (
                  <button type="button" className="truncate px-1 text-xs font-medium text-muted-foreground hover:text-foreground hover:underline"
                    onClick={(ev) => { ev.stopPropagation(); onDay(d.date); }}>
                    +{more} more
                  </button>
                )}
              </div>
              <div className="space-y-px">
                {shown.map((e) => <EventChip key={e.key} item={e} onOpen={onOpen} />)}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** Day and Week: an all-day row, then a 24-hour grid that opens at 5 AM. Click a slot to add an event there. */
export function TimeGridView({ data, onOpen, onCreate, onDay }: {
  data: ViewData; onOpen: OpenItem; onCreate: CreateAt; onDay: (date: string) => void;
}) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const days = data.days;
  const cols = `3.5rem repeat(${days.length}, minmax(0, 1fr))`;
  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = SCROLL_TO_HOUR * HOUR_PX;
  }, [data.view]);

  const slotClick = (d: CalDay, e: React.MouseEvent<HTMLDivElement>) => {
    const y = e.clientY - e.currentTarget.getBoundingClientRect().top;
    onCreate(d.date, fromMinutes(Math.floor((y / HOUR_PX) * 2) * 30));
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="grid border-b" style={{ gridTemplateColumns: cols }}>
        <div />
        {days.map((d) => (
          <button key={d.date} type="button" onClick={() => onDay(d.date)}
            className="flex flex-col items-center py-1 text-xs font-medium uppercase tracking-wide text-muted-foreground hover:bg-accent">
            {DOW[d.dow]}
            <span className={cn('flex h-7 min-w-[1.75rem] items-center justify-center rounded-full px-1 text-lg font-medium normal-case tracking-normal tabular-nums text-foreground',
              d.is_today && 'bg-primary font-semibold text-primary-foreground')}>{d.day}</span>
          </button>
        ))}
      </div>
      <div className="grid border-b" style={{ gridTemplateColumns: cols }}>
        <div className="py-1 pr-1.5 text-right text-[11px] text-muted-foreground">all-day</div>
        {days.map((d) => (
          <div key={d.date} className="min-h-[26px] cursor-pointer space-y-px border-l p-0.5" onClick={() => onCreate(d.date, null)}>
            {itemsOnDay(data.events, d.date).filter((e) => !isTimedInDay(e)).map((e) => (
              <EventChip key={e.key} item={e} onOpen={onOpen} />
            ))}
          </div>
        ))}
      </div>
      <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto">
        <div className="relative grid" style={{ gridTemplateColumns: cols, height: 24 * HOUR_PX }}>
          <div className="relative">
            {Array.from({ length: 24 }, (_, h) => (
              <div key={h} className="absolute right-1.5 -translate-y-2 text-[11px] text-muted-foreground" style={{ top: h * HOUR_PX }}>{hourLabel(h)}</div>
            ))}
          </div>
          {days.map((d) => (
            <div
              key={d.date}
              className="relative cursor-pointer border-l"
              style={{ backgroundImage: `repeating-linear-gradient(to bottom, transparent 0 ${HOUR_PX - 1}px, hsl(var(--border)) ${HOUR_PX - 1}px ${HOUR_PX}px)` }}
              onClick={(e) => slotClick(d, e)}
            >
              {layoutDay(data.events.filter((e) => isTimedInDay(e) && e.start_date === d.date)).map((p) => {
                const c = COLOR_CLASS[p.item.color] ?? COLOR_CLASS.gray;
                const short = p.height < 40;
                return (
                  <button
                    key={p.item.key}
                    type="button"
                    onClick={(e) => { e.stopPropagation(); onOpen(p.item); }}
                    title={`${p.item.title} · ${p.item.time_label}`}
                    className={cn('absolute overflow-hidden rounded border-l-[3px] px-1.5 text-left text-xs leading-4 text-foreground shadow-sm hover:brightness-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                      c.bar, 'bg-card')}
                    style={{
                      top: (p.top / 60) * HOUR_PX, height: Math.max((p.height / 60) * HOUR_PX - 1, 16),
                      left: `calc(${(p.col / p.cols) * 100}% + 1px)`, width: `calc(${100 / p.cols}% - 3px)`,
                    }}
                  >
                    <span aria-hidden className={cn('absolute inset-0', c.soft)} />
                    <span className={cn('relative block truncate font-semibold', short && 'inline')}>{p.item.title}</span>
                    <span className={cn('relative truncate text-muted-foreground', short ? 'ml-1 inline' : 'block')}>
                      {p.item.time_label}{p.item.location && !short ? ` · ${p.item.location}` : ''}
                    </span>
                  </button>
                );
              })}
              {d.is_today && (
                <div aria-hidden className="pointer-events-none absolute inset-x-0 z-10 h-0.5 bg-destructive"
                  style={{ top: (data.now_minutes / 60) * HOUR_PX }}>
                  <span className="absolute -left-1 -top-1 h-2.5 w-2.5 rounded-full bg-destructive" />
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/** Agenda and search results: days that have events, each event with its time and calendar colour. */
export function AgendaView({ data, onOpen, emptyText }: { data: ViewData; onOpen: OpenItem; emptyText: string }) {
  const groups: { date: string; label: string; today: boolean; items: CalItem[] }[] = [];
  for (const e of data.events) {
    const last = groups[groups.length - 1];
    if (last && last.date === e.start_date) last.items.push(e);
    else groups.push({ date: e.start_date, label: e.day_label, today: e.start_date === data.today, items: [e] });
  }
  if (groups.length === 0) return <p className="p-4 text-sm text-muted-foreground">{emptyText}</p>;
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <table className="w-full text-sm">
        <tbody>
          {groups.map((g) => g.items.map((e, i) => {
            const c = COLOR_CLASS[e.color] ?? COLOR_CLASS.gray;
            return (
              <tr key={e.key} className={cn('cursor-pointer hover:bg-muted/40', i === g.items.length - 1 && 'border-b')} onClick={() => onOpen(e)}>
                <td className="w-36 whitespace-nowrap px-4 py-1.5 align-top font-medium max-sm:w-24 max-sm:px-2 max-sm:text-xs">
                  {i === 0 && <>{g.label}{g.today && <span className="ml-1.5 text-xs font-normal text-primary">Today</span>}</>}
                </td>
                <td className="w-48 whitespace-nowrap px-2 py-1.5 align-top text-muted-foreground max-sm:hidden">{e.time_label}</td>
                <td className="max-w-0 px-2 py-1.5 align-top">
                  <span className="flex min-w-0 items-center gap-2">
                    {e.kind === 'EVENT'
                      ? <span className={cn('h-2.5 w-2.5 shrink-0 rounded-full', c.dot)} />
                      : <span className="h-2.5 w-2.5 shrink-0 rounded-full border border-dashed border-muted-foreground" />}
                    <span className="truncate">{e.title}</span>
                    {e.is_recurring && <Repeat aria-label="Repeats" className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />}
                    {e.location && <span className="truncate text-muted-foreground max-sm:hidden">· {e.location}</span>}
                  </span>
                  <span className="block text-xs text-muted-foreground sm:hidden">{e.time_label}{e.location ? ` · ${e.location}` : ''}</span>
                </td>
              </tr>
            );
          }))}
        </tbody>
      </table>
    </div>
  );
}
