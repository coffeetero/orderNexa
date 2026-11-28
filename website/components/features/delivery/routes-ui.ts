import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';

export const DAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'] as const;
export type Day = (typeof DAYS)[number];
export const DAY_SHORT: Record<Day, string> = { MON: 'Mon', TUE: 'Tue', WED: 'Wed', THU: 'Thu', FRI: 'Fri', SAT: 'Sat', SUN: 'Sun' };
export const DAY_LONG: Record<Day, string> = { MON: 'Monday', TUE: 'Tuesday', WED: 'Wednesday', THU: 'Thursday', FRI: 'Friday', SAT: 'Saturday', SUN: 'Sunday' };
export const DAY_LETTER: Record<Day, string> = { MON: 'M', TUE: 'T', WED: 'W', THU: 'T', FRI: 'F', SAT: 'S', SUN: 'S' };

export interface Route {
  route_id: number;
  route_code: string;
  route_name: string;
  sort_order: number;
  is_active: boolean;
  default_driver_user_id: number | null;
  driver_name: string | null;
  start_time: string | null;
  notes: string | null;
  counts: Record<Day, number>;
}
export interface RoutesData {
  production_code: string;
  production_codes: { code: string; label: string }[];
  staff: { user_id: number; user_name: string }[];
  routes: Route[];
}
/** Where an address is on a map (om_customer_ship_point). */
export interface MapPoint {
  contact_point_id: number;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  geocode_status: string | null;
}
export interface Stop {
  route_stop_id: number;
  stop_no: number;
  customer_id: number;
  customer_number: string | null;
  customer_name: string;
  customer_type: string | null;
  parent_name: string | null;
  is_active: boolean;
  address: string | null;
  point: MapPoint | null;
  window_from: string | null;
  window_to: string | null;
  driver_notes: string | null;
}
export interface StopsData {
  stops: Stop[];
  origin: MapPoint | null;
  day_assignments: { customer_id: number; route_id: number; route_code: string; stop_no: number }[];
}
export interface Unassigned {
  customer_id: number;
  customer_number: string | null;
  customer_name: string;
  customer_type: string | null;
  account_name: string | null;
  last_order_date: string | null;
}
export interface DateChange {
  exception_id: number;
  exception_date: string;
  day_of_week: Day;
  production_code: string;
  customer_id: number;
  customer_number: string | null;
  customer_name: string;
  kind: 'SKIP' | 'ROUTE';
  route_id: number | null;
  route_code: string | null;
  route_name: string | null;
  stop_no: number | null;
  notes: string | null;
  usual_route_code: string | null;
  usual_stop_no: number | null;
}

/** Ship-to locations: accounts and sites (departments are delivered with their site or account). */
export const isShipTo = (c: CustomerOption) => ['ACCOUNT', 'SITE'].includes((c.customer_type ?? '').trim().toUpperCase());
export const customerLabel = (c: { customer_number: string | null; customer_name: string }) =>
  c.customer_number ? `${c.customer_number} · ${c.customer_name}` : c.customer_name;

/** "05:30" → "5:30 AM" (display only). */
export function timeLabel(t: string | null): string {
  if (!t) return '';
  const [h, m] = t.split(':').map(Number);
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}
/** "2026-11-25" → "11/25/2026". */
export const shortDate = (d: string | null) => (d ? `${d.slice(5, 7)}/${d.slice(8, 10)}/${d.slice(0, 4)}` : '');

export async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const j = (await res.json().catch(() => ({}))) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Something went wrong. Try again.');
  return j.data as T;
}
export const post = <T,>(url: string, body: unknown) =>
  call<T>(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

export const IN = 'h-9 w-full min-w-0 rounded-md border border-input bg-background px-2.5 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50';
export const LAB = 'bps-label mb-1 block text-xs font-semibold text-muted-foreground';
export const TH = 'h-8 whitespace-nowrap bg-muted/50 px-2 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';
export const TD = 'whitespace-nowrap px-2 py-1.5';
