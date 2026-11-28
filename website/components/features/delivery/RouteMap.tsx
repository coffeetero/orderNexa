'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import type { MapPoint, Stop } from './routes-ui';

/* Minimal typing of the parts of the Google Maps JavaScript API this map uses. */
type LatLng = { lat: number; lng: number };
interface GMap { fitBounds(b: unknown, pad?: number): void; setCenter(c: LatLng): void; setZoom(z: number): void }
interface GOverlay { setMap(m: GMap | null): void; addListener?(ev: string, fn: () => void): void }
interface GoogleMaps {
  Map: new (el: HTMLElement, o: Record<string, unknown>) => GMap;
  Marker: new (o: Record<string, unknown>) => GOverlay;
  Polyline: new (o: Record<string, unknown>) => GOverlay;
  InfoWindow: new (o?: Record<string, unknown>) => { setContent(c: string | Node): void; open(o: Record<string, unknown>): void };
  LatLngBounds: new () => { extend(p: LatLng): void };
  SymbolPath: { CIRCLE: number };
}
declare global { interface Window { google?: { maps: GoogleMaps }; __bpsMapsLoading?: Promise<void> } }

const KEY = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? '';

/** Loads the Maps JavaScript API once per page. */
function loadMaps(): Promise<void> {
  if (typeof window === 'undefined') return Promise.reject(new Error('no window'));
  if (window.google?.maps) return Promise.resolve();
  if (!window.__bpsMapsLoading) {
    window.__bpsMapsLoading = new Promise<void>((resolve, reject) => {
      const s = document.createElement('script');
      s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(KEY)}&v=weekly`;
      s.async = true;
      s.onload = () => resolve();
      s.onerror = () => { window.__bpsMapsLoading = undefined; reject(new Error('Google Maps could not load')); };
      document.head.appendChild(s);
    });
  }
  return window.__bpsMapsLoading;
}

const located = (p: MapPoint | null | undefined): p is MapPoint & { latitude: number; longitude: number } =>
  !!p && p.latitude !== null && p.longitude !== null && p.geocode_status === 'OK';

/**
 * Routes Maintenance: the selected route's stops on a Google map — the company's address as the start (when it has one),
 * a numbered pin per stop in stop order, joined by straight lines. Addresses not yet looked up are geocoded on the server
 * (/api/geocode/run) the first time they show; ones Google cannot find are listed under the map.
 */
export function RouteMap({ tenantId, stops, origin }: { tenantId: number; stops: Stop[]; origin: MapPoint | null }) {
  const el = useRef<HTMLDivElement | null>(null);
  const [ready, setReady] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [lookupNote, setLookupNote] = useState<string | null>(null);
  // coordinates found by this session's lookups, by contact point, until the stops reload with them
  const [found, setFound] = useState<Record<number, { latitude: number; longitude: number } | null>>({});

  useEffect(() => {
    if (!KEY) return;
    let live = true;
    loadMaps().then(() => { if (live) setReady(true); }).catch((e: Error) => { if (live) setLoadError(e.message); });
    return () => { live = false; };
  }, []);

  // look up this route's addresses that have no coordinates yet
  const pending = useMemo(() => {
    const pts = [origin, ...stops.map((s) => s.point)];
    return pts.filter((p): p is MapPoint => !!p && (p.geocode_status === 'PENDING' || p.geocode_status === 'FAILED') && !(p.contact_point_id in found))
      .map((p) => p.contact_point_id);
  }, [stops, origin, found]);
  useEffect(() => {
    if (!KEY || pending.length === 0) return;
    let live = true;
    fetch('/api/geocode/run', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tenant_id: tenantId, contact_point_ids: pending }) })
      .then((r) => r.json())
      .then((j: { data?: { results: { contact_point_id: number; status: string; latitude?: number; longitude?: number }[] }; error?: string }) => {
        if (!live) return;
        if (j.error) { setLookupNote(j.error); setFound((f) => ({ ...f, ...Object.fromEntries(pending.map((id) => [id, null])) })); return; }
        setFound((f) => ({ ...f, ...Object.fromEntries((j.data?.results ?? []).map((r) => [r.contact_point_id,
          r.status === 'OK' && r.latitude !== undefined && r.longitude !== undefined ? { latitude: r.latitude, longitude: r.longitude } : null])) }));
      })
      .catch(() => {});
    return () => { live = false; };
  }, [pending, tenantId]);

  // stable between renders, so the map is rebuilt only when the stops or their coordinates change
  const { start, pins } = useMemo(() => {
    const withCoords = (p: MapPoint | null): LatLng | null => {
      if (!p) return null;
      const f = found[p.contact_point_id];
      if (f) return { lat: f.latitude, lng: f.longitude };
      return located(p) ? { lat: Number(p.latitude), lng: Number(p.longitude) } : null;
    };
    return { start: withCoords(origin), pins: stops.map((s) => ({ s, at: withCoords(s.point) })) };
  }, [stops, origin, found]);
  const missing = pins.filter((p) => !p.at);

  useEffect(() => {
    const g = window.google?.maps;
    if (!ready || !g || !el.current) return;
    const map = new g.Map(el.current, { center: { lat: 40.73, lng: -74.0 }, zoom: 10, mapTypeControl: false, streetViewControl: false, fullscreenControl: true });
    const info = new g.InfoWindow();
    const overlays: GOverlay[] = [];
    const bounds = new g.LatLngBounds();
    const path: LatLng[] = [];
    if (start) {
      const m = new g.Marker({ position: start, map, title: 'Bakery (start)',
        icon: { path: g.SymbolPath.CIRCLE, scale: 9, fillColor: '#1e1915', fillOpacity: 1, strokeColor: '#ffffff', strokeWeight: 2 } });
      overlays.push(m); bounds.extend(start); path.push(start);
    }
    for (const { s, at } of pins) {
      if (!at) continue;
      const m = new g.Marker({ position: at, map, label: { text: String(s.stop_no), color: '#ffffff', fontSize: '12px', fontWeight: '600' },
        title: `${s.stop_no}. ${s.customer_name}` });
      m.addListener?.('click', () => {
        const div = document.createElement('div');
        div.style.font = '13px Inter, system-ui, sans-serif';
        const b = document.createElement('b'); b.textContent = `${s.stop_no}. ${s.customer_name}`; div.appendChild(b);
        const a = document.createElement('div'); a.style.whiteSpace = 'pre-line'; a.style.marginTop = '4px'; a.textContent = s.point?.address ?? ''; div.appendChild(a);
        info.setContent(div); info.open({ anchor: m, map });
      });
      overlays.push(m); bounds.extend(at); path.push(at);
    }
    if (path.length > 1) overlays.push(new g.Polyline({ path, map, strokeColor: '#a3451c', strokeOpacity: 0.8, strokeWeight: 3 }));
    if (path.length > 1) map.fitBounds(bounds, 48);
    else if (path.length === 1) { map.setCenter(path[0]); map.setZoom(14); }
    return () => { overlays.forEach((o) => o.setMap(null)); };
  }, [ready, start, pins]);

  if (!KEY) {
    return (
      <section className="rounded-lg border border-border bg-card p-4 text-sm text-muted-foreground shadow-sm">
        The route map needs a Google Maps key. Add <code>NEXT_PUBLIC_GOOGLE_MAPS_KEY</code> (and <code>GOOGLE_GEOCODING_KEY</code> for address lookup) to the server settings.
      </section>
    );
  }
  return (
    <section aria-label="Route map" className="overflow-hidden rounded-lg border border-border bg-card shadow-sm">
      <div className="flex min-h-[40px] flex-wrap items-center gap-x-3 gap-y-1 border-b border-border px-3 py-1.5">
        <h2 className="text-sm font-semibold">Map</h2>
        <span className="text-xs text-muted-foreground">Stops in order{start ? ', starting at the bakery' : ''}</span>
      </div>
      {loadError ? <p className="p-4 text-sm text-destructive">{loadError}</p>
        : <div ref={el} className="h-[420px] w-full bg-muted/40" role="region" aria-label="Map of the route's stops" />}
      {(missing.length > 0 || !start || lookupNote) && (
        <div className="space-y-1 border-t border-border px-3 py-2 text-xs text-muted-foreground">
          {lookupNote && <p className="text-destructive">{lookupNote}</p>}
          {!start && <p>No start point: add the bakery&apos;s address to show where the route begins.</p>}
          {missing.length > 0 && (
            <p>Not on the map ({missing.length}): {missing.map(({ s }) => `${s.stop_no}. ${s.customer_name}${s.point ? (s.point.geocode_status === 'ZERO_RESULTS' ? ' (address not found)' : ' (looking up…)') : ' (no address)'}`).join(' · ')}</p>
          )}
        </div>
      )}
    </section>
  );
}
