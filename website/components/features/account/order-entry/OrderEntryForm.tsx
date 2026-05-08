'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Save, Trash2, RotateCcw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { createClient } from '@/lib/supabase/client';
import { OrderHeaderRow, type CustomerOption } from './OrderHeaderRow';
import { ItemEntryRow } from './ItemEntryRow';
import { OrderLineGrid } from './OrderLineGrid';
import { useOrderEntryState } from './useOrderEntryState';
import { useOrderFocus } from './useOrderFocus';
import type {
  OrderEntryDraft,
  OrderEntryItem,
  OrderHeaderListRow,
  OrderSavePayload,
  OrderSaveResult,
} from '@/lib/types';
import { OrderPickSheet } from './OrderPickSheet';

function normalizeOrderHeaderRow(raw: Record<string, unknown>): OrderHeaderListRow | null {
  const order_id = Number(raw.order_id);
  if (!Number.isFinite(order_id)) return null;
  return {
    order_id,
    order_number: String(raw.order_number ?? ''),
    production_date: String(raw.production_date ?? ''),
    production_code: String(raw.production_code ?? ''),
    department_event:
      raw.department_event !== undefined && raw.department_event !== null
        ? String(raw.department_event)
        : undefined,
    amount: Number(raw.amount ?? 0),
    customer_id: Number(raw.customer_id ?? 0),
    customer_number:
      raw.customer_number !== undefined && raw.customer_number !== null
        ? String(raw.customer_number)
        : undefined,
    customer_name:
      raw.customer_name !== undefined && raw.customer_name !== null
        ? String(raw.customer_name)
        : undefined,
    top_customer_id:
      raw.top_customer_id !== undefined && raw.top_customer_id !== null
        ? Number(raw.top_customer_id)
        : undefined,
    top_customer_name:
      raw.top_customer_name !== undefined && raw.top_customer_name !== null
        ? String(raw.top_customer_name)
        : undefined,
    order_date:
      raw.order_date !== undefined && raw.order_date !== null
        ? String(raw.order_date)
        : undefined,
  };
}

function getErrorMessage(error: unknown, fallback: string): string {
  return typeof error === 'string' && error.trim().length > 0 ? error : fallback;
}

type OrderPickMode = 'customer-scoped' | 'global-search';

function localToday(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function daysAfterToday(dateValue: string): number | null {
  const [year, month, day] = dateValue.split('-').map(Number);
  if (!year || !month || !day) return null;
  const today = localToday().split('-').map(Number);
  const targetDate = new Date(year, month - 1, day);
  const todayDate = new Date(today[0], today[1] - 1, today[2]);
  return Math.round((targetDate.getTime() - todayDate.getTime()) / 86_400_000);
}

function isDepartmentEventCustomer(customer: CustomerOption): boolean {
  const type = customer.customer_type?.trim().toUpperCase();
  return type === 'LOCATION' || type === 'EVENT';
}

interface OrderEntryFormProps {
  mode: 'new' | 'edit';
  /** Provided in edit mode — the form fetches the order on mount. */
  orderId?: number;
  /** Pre-loaded initial draft — can be supplied by a server component to skip the first fetch. */
  initialData?: OrderEntryDraft;
  /** Tenant id pre-resolved server-side via fnd_tenants_get. */
  serverTenantId?: number;
  /** Customer list pre-loaded server-side. When non-empty, the client-side customer fetch is skipped. */
  serverCustomers?: CustomerOption[];
}

export function OrderEntryForm({
  mode,
  orderId,
  initialData,
  serverTenantId,
  serverCustomers,
}: OrderEntryFormProps) {
  const router = useRouter();

  // ── Session / tenant ───────────────────────────────────────────────────
  // Initialise directly from the server-passed value when available.
  const [tenantId, setTenantId] = useState<number | null>(serverTenantId ?? null);

  useEffect(() => {
    // Only run the client-side resolution if the server didn't supply a tenantId.
    if (serverTenantId !== undefined) return;
    const supabase = createClient();
    supabase.auth.getSession().then(({ data }) => {
      const tid = data.session?.user?.app_metadata?.tenant_id;
      if (typeof tid === 'number') {
        setTenantId(tid);
      } else if (typeof tid === 'string') {
        const parsed = parseInt(tid, 10);
        if (!isNaN(parsed)) setTenantId(parsed);
      }
    });
  }, [serverTenantId]);

  // ── Data loading ───────────────────────────────────────────────────────
  // Initialise customers directly when pre-loaded by the server.
  const [customers, setCustomers] = useState<CustomerOption[]>(serverCustomers ?? []);
  const [items, setItems] = useState<OrderEntryItem[]>([]);
  const [orderPickOpen, setOrderPickOpen] = useState(false);
  const [orderPickMode, setOrderPickMode] = useState<OrderPickMode>('customer-scoped');
  const [orderPickCandidates, setOrderPickCandidates] = useState<OrderHeaderListRow[]>([]);
  const [isLoadingCustomers, setIsLoadingCustomers] = useState(false);
  const [isLoadingItems, setIsLoadingItems] = useState(false);
  const [itemsError, setItemsError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [statusMessage, setStatusMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const [shouldFocusItemWhenReady, setShouldFocusItemWhenReady] = useState(false);

  // ── State & focus ──────────────────────────────────────────────────────
  const {
    draft,
    setCustomer,
    setField,
    reset,
    loadOrder,
    addOrUpdateLine,
    updateLine,
    removeLine,
    getLineQty,
  } = useOrderEntryState(initialData);

  const {
    customerInputRef,
    itemInputRef,
    qtyRef,
    focusCustomer,
    focusItem,
    focusQty,
    focusGridCell,
    registerGridCell,
  } = useOrderFocus();

  const [activeLineIndex, setActiveLineIndex] = useState<number | null>(null);

  const mapOrderToDraft = useCallback((data: Record<string, unknown>): OrderEntryDraft => {
    const lines = (Array.isArray(data.lines) ? data.lines : []).map((l: Record<string, unknown>) => ({
      tempId: String(l.order_line_id ?? crypto.randomUUID()),
      order_id: l.order_id as number,
      order_line_id: l.order_line_id as number,
      item_id: l.item_id as number,
      item_number: (l.item_number as string) ?? '',
      item_description: (l.item_description as string) ?? '',
      is_sliced: Boolean(l.is_sliced),
      is_wrapped: Boolean(l.is_wrapped),
      is_covered: Boolean(l.is_covered),
      is_scored: Boolean(l.is_scored),
      can_slice: Boolean(l.can_slice),
      can_wrap: Boolean(l.can_wrap),
      can_cover: Boolean(l.can_cover),
      can_score: Boolean(l.can_score),
      quantity: Number(l.quantity ?? 0),
      unit_price: Number(l.unit_price ?? 0),
      unit_discount: Number(l.unit_discount ?? 0),
      extended_amount: Number(l.extended_amount ?? 0),
    }));
    const totalAmount = lines.reduce(
      (s: number, l: { extended_amount: number }) => s + l.extended_amount,
      0,
    );
    return {
      order_id: data.order_id as number,
      order_number: (data.order_number as string) ?? '',
      customer_id: (data.customer_id as number) ?? null,
      customer_name: (data.customer_name as string) ?? '',
      department_event: (data.department_event as string) ?? '',
      customer_credit: 0,
      order_date: (data.order_date as string) ?? new Date().toISOString().slice(0, 10),
      production_date: (data.production_date as string) ?? new Date().toISOString().slice(0, 10),
      production_code: (data.production_code as 'AM' | 'PM' | 'SPECIAL') ?? 'AM',
      delivery_amount: Number(data.delivery_amount ?? 0),
      total_amount: totalAmount,
      lines,
    };
  }, []);

  /** Serializes slot lookups so rapid header changes don't apply stale results. */
  const slotLookupGenerationRef = useRef(0);
  const suppressNextSlotLookupRef = useRef(false);

  const getDefaultDepartmentEvent = useCallback(
    (customerId: number | null): string => {
      if (customerId == null) return '';
      const customer = customers.find((candidate) => candidate.customer_id === customerId);
      if (!customer) return draft.customer_name;

      return isDepartmentEventCustomer(customer) ? customer.customer_name : customer.customer_name;
    },
    [customers, draft.customer_name],
  );

  const loadOrderById = useCallback(
    async (
      targetOrderId: number,
      opts?: { generation?: number; preserveSelectedCustomer?: boolean },
    ) => {
      if (!tenantId || !targetOrderId) return;
      const gen = opts?.generation;
      const selectedCustomerId = draft.customer_id;
      const selectedCustomerName = draft.customer_name;
      setStatusMessage(null);
      let response: Response;
      try {
        response = await fetch(
          `/api/orders?tenant_id=${tenantId}&order_id=${targetOrderId}&headers_only=false`,
        );
      } catch {
        setStatusMessage({ text: 'Could not load order lines. Network request failed.', type: 'error' });
        return;
      }

      const json = (await response.json().catch(() => ({}))) as {
        data?: Record<string, unknown> | null;
        error?: unknown;
      };
      if (!response.ok || json.error) {
        setStatusMessage({
          text: getErrorMessage(json.error, 'Could not load order lines.'),
          type: 'error',
        });
        return;
      }
      if (!json.data || typeof json.data !== 'object') {
        setStatusMessage({ text: 'Order detail was empty; no lines were loaded.', type: 'error' });
        return;
      }
      if (gen !== undefined && gen !== slotLookupGenerationRef.current) return;
      const loadedDraft = mapOrderToDraft(json.data);
      if (opts?.preserveSelectedCustomer && selectedCustomerId !== null) {
        loadedDraft.customer_id = selectedCustomerId;
        loadedDraft.customer_name = selectedCustomerName;
      }
      loadOrder(loadedDraft);
      setActiveLineIndex(null);
      setShouldFocusItemWhenReady(true);
    },
    [tenantId, draft.customer_id, draft.customer_name, loadOrder, mapOrderToDraft],
  );

  // ── Fetch customers when tenantId is ready ─────────────────────────────
  // Skip only if the server already returned a non-empty list; an empty array may mean the RSC
  // fetch failed (e.g. host/cookie) and the browser can still call the same API with session cookies.
  useEffect(() => {
    if (serverCustomers !== undefined && serverCustomers.length > 0) return;
    if (tenantId === null) return;
    setIsLoadingCustomers(true);
    fetch(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then((r) => r.json())
      .then(({ data }) => {
        if (Array.isArray(data)) setCustomers(data as CustomerOption[]);
      })
      .finally(() => setIsLoadingCustomers(false));
  }, [tenantId, serverCustomers]);

  // ── Fetch items when customer changes ──────────────────────────────────
  useEffect(() => {
    if (tenantId === null) return;
    const customerIdForRequest = draft.customer_id;
    setIsLoadingItems(true);
    setItemsError(null);
    const qs = customerIdForRequest
      ? `tenant_id=${tenantId}&customer_id=${customerIdForRequest}`
      : `tenant_id=${tenantId}`;
    fetch(`/api/items?${qs}`)
      .then((r) => r.json())
      .then(({ data, error }) => {
        if (error) {
          setItemsError(error as string);
          return;
        }
        if (Array.isArray(data)) setItems(data as OrderEntryItem[]);
      })
      .finally(() => {
        setIsLoadingItems(false);
      });
  }, [tenantId, draft.customer_id]);

  useEffect(() => {
    if (!shouldFocusItemWhenReady || isLoadingItems || orderPickOpen) return;
    if (draft.customer_id == null || !draft.order_number) return;
    setShouldFocusItemWhenReady(false);
    requestAnimationFrame(() => focusItem());
  }, [
    shouldFocusItemWhenReady,
    isLoadingItems,
    orderPickOpen,
    draft.customer_id,
    draft.order_number,
    focusItem,
  ]);

  const fetchOrderHeaders = useCallback(
    async (customerId: number | null): Promise<OrderHeaderListRow[]> => {
      if (!tenantId || !draft.production_date) return [];

      const qs = new URLSearchParams({
        tenant_id: String(tenantId),
        production_date: draft.production_date,
        production_code: draft.production_code,
        headers_only: 'true',
      });
      if (customerId !== null) {
        qs.set('customer_id', String(customerId));
      }

      const response = await fetch(`/api/orders?${qs}`);
      const ordJson = (await response.json()) as { data: unknown; error?: string };
      if (!response.ok || ordJson.error) {
        throw new Error(getErrorMessage(ordJson.error, 'Could not find existing orders.'));
      }

      const rawRows = Array.isArray(ordJson.data) ? ordJson.data : [];
      const rows: OrderHeaderListRow[] = [];
      for (const item of rawRows) {
        if (item && typeof item === 'object') {
          const row = normalizeOrderHeaderRow(item as Record<string, unknown>);
          if (row) rows.push(row);
        }
      }
      return rows;
    },
    [tenantId, draft.production_date, draft.production_code],
  );

  // ── Existing orders: headers-only list for slot, then detail fetch with lines ─
  useEffect(() => {
    if (!tenantId || !draft.customer_id) {
      setField('order_number', '');
      setOrderPickCandidates([]);
      setOrderPickOpen(false);
      return;
    }
    if (!draft.production_date) return;
    if (mode === 'edit' && orderId != null) return;
    if (suppressNextSlotLookupRef.current) {
      suppressNextSlotLookupRef.current = false;
      return;
    }

    const generation = ++slotLookupGenerationRef.current;

    const applyOrderHeaders = (rows: OrderHeaderListRow[]) => {
      if (generation !== slotLookupGenerationRef.current) return;

      const matching = [...rows].sort((a, b) => b.order_id - a.order_id);

      if (matching.length === 0) {
        setField('order_number', 'New Order');
        setField('order_ref', 'New Order');
        setField('order_id', undefined);
        setField('department_event', getDefaultDepartmentEvent(draft.customer_id));
        setField('lines', []);
        setField('total_amount', 0);
        setOrderPickCandidates([]);
        setOrderPickOpen(false);
        setShouldFocusItemWhenReady(true);
        return;
      }

      setField('order_number', 'New Order');
      setField('order_ref', 'New Order');
      setField('order_id', undefined);
      setField('department_event', '');
      setField('lines', []);
      setField('total_amount', 0);
      setOrderPickMode('customer-scoped');
      setOrderPickCandidates(matching);
      setOrderPickOpen(true);
    };

    fetchOrderHeaders(draft.customer_id)
      .then(applyOrderHeaders)
      .catch(() => {
        setStatusMessage({
          text: 'Could not find existing orders. Network request failed.',
          type: 'error',
        });
      });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    tenantId,
    draft.customer_id,
    draft.customer_name,
    draft.production_date,
    draft.production_code,
    getDefaultDepartmentEvent,
    fetchOrderHeaders,
    mode,
    orderId,
  ]);

  // ── Load existing order in edit mode ──────────────────────────────────
  useEffect(() => {
    if (mode !== 'edit' || !orderId || !tenantId || initialData) return;
    fetch(`/api/orders?tenant_id=${tenantId}&order_id=${orderId}&headers_only=false`)
      .then((r) => r.json())
      .then(({ data, error }) => {
        if (error) {
          setStatusMessage({
            text: getErrorMessage(error, 'Could not load order lines.'),
            type: 'error',
          });
          return;
        }
        if (!data || typeof data !== 'object') {
          setStatusMessage({ text: 'Order detail was empty; no lines were loaded.', type: 'error' });
          return;
        }
        loadOrder(mapOrderToDraft(data as Record<string, unknown>));
      })
      .catch(() => {
        setStatusMessage({ text: 'Could not load order lines. Network request failed.', type: 'error' });
      });
  }, [mode, orderId, tenantId, initialData, loadOrder, mapOrderToDraft]);

  // ── Focus on initial load ──────────────────────────────────────────────
  useEffect(() => {
    if (mode === 'new') {
      focusCustomer();
    } else {
      focusItem();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Event handlers ─────────────────────────────────────────────────────

  const handleSearchExistingOrders = useCallback(async () => {
    if (!tenantId || !draft.production_date) return;
    setStatusMessage(null);
    try {
      const rows = await fetchOrderHeaders(draft.customer_id);
      if (rows.length === 0) {
        setOrderPickCandidates([]);
        setOrderPickOpen(false);
        setStatusMessage({ text: 'No existing orders found for this production slot.', type: 'error' });
        return;
      }

      setOrderPickMode(draft.customer_id === null ? 'global-search' : 'customer-scoped');
      setOrderPickCandidates(rows);
      setOrderPickOpen(true);
    } catch (error) {
      setStatusMessage({
        text: error instanceof Error ? error.message : 'Could not find existing orders.',
        type: 'error',
      });
    }
  }, [tenantId, draft.production_date, draft.customer_id, fetchOrderHeaders]);

  const handleCustomerChange = useCallback(
    (customer: CustomerOption | null) => {
      const previousCustomerId = draft.customer_id;
      setShouldFocusItemWhenReady(false);
      setCustomer(customer?.customer_id ?? null, customer?.customer_name ?? '');
      setField('department_event', '');
      setField('order_number', '');
      setField('order_ref', '');
      setField('order_id', undefined);
      setField('lines', []);
      setField('total_amount', 0);
      if (customer && customer.customer_id === previousCustomerId) {
        void handleSearchExistingOrders();
      }
    },
    [draft.customer_id, handleSearchExistingOrders, setCustomer, setField],
  );

  const handleProductionDateChange = useCallback(
    (value: string) => {
      const daysAhead = daysAfterToday(value);
      if (
        daysAhead !== null &&
        daysAhead > 5 &&
        !window.confirm('This production date is more than 5 days in the future. Continue?')
      ) {
        return;
      }
      setField('production_date', value);
    },
    [setField],
  );

  const handleItemCommit = useCallback(
    (item: OrderEntryItem, quantity: number) => {
      const tempId = addOrUpdateLine(item, quantity);
      const lineIndex = draft.lines.findIndex((l) => l.item_id === item.item_id);
      const nextIndex = lineIndex >= 0 ? lineIndex : draft.lines.length;
      setActiveLineIndex(nextIndex);
      // Return focus to item search for the next entry
      focusItem();
      // Small delay to let state update first
      requestAnimationFrame(() => {
        const updatedIndex = nextIndex;
        // If new line, it's appended; highlight it for a moment
        setActiveLineIndex(updatedIndex);
      });
    },
    [addOrUpdateLine, draft.lines, focusItem],
  );

  const handleDiscountEnter = useCallback(() => {
    focusItem();
  }, [focusItem]);

  const handleClear = useCallback(() => {
    reset();
    focusCustomer();
  }, [reset, focusCustomer]);

  const handleOrderPickNew = useCallback(() => {
    setOrderPickOpen(false);
    setField('order_id', undefined);
    setField('order_number', 'New Order');
    setField('order_ref', 'New Order');
    setField('department_event', getDefaultDepartmentEvent(draft.customer_id));
    setField('lines', []);
    setField('total_amount', 0);
    setShouldFocusItemWhenReady(true);
  }, [draft.customer_id, getDefaultDepartmentEvent, setField]);

  const handleOrderPickSelect = useCallback(
    (row: OrderHeaderListRow) => {
      setOrderPickOpen(false);
      suppressNextSlotLookupRef.current = true;
      setField('order_id', row.order_id);
      setField('order_number', row.order_number);
      setField('order_ref', row.order_number);
      void loadOrderById(row.order_id, {
        preserveSelectedCustomer: orderPickMode === 'customer-scoped',
      });
    },
    [loadOrderById, orderPickMode, setField],
  );

  // ── Save ───────────────────────────────────────────────────────────────

  const handleSave = useCallback(async () => {
    if (!tenantId) return;

    const isExistingOrder = !!draft.order_id;
    const visibleOrderNumber = draft.order_number.trim();
    const orderNumber =
      visibleOrderNumber === 'New Order'
        ? (!isExistingOrder ? 'New Order' : '')
        : visibleOrderNumber || (!isExistingOrder ? 'New Order' : '');
    if (!orderNumber.trim()) {
      setStatusMessage({ text: 'Order number is missing for this order.', type: 'error' });
      return;
    }

    setIsSaving(true);
    setStatusMessage(null);
    try {
      const payload: OrderSavePayload = {
        customer_id: draft.customer_id,
        order_number: orderNumber,
        order_date: draft.order_date,
        production_date: draft.production_date,
        production_code: draft.production_code,
        department_event: draft.department_event,
        delivery_amount: draft.delivery_amount,
        lines: draft.lines.map((l) => ({
          client_temp_id: l.tempId,
          order_line_id: l.order_line_id,
          item_id: l.item_id,
          item_description: l.item_description,
          quantity: l.quantity,
          unit_price: l.unit_price,
          unit_discount: l.unit_discount,
          is_sliced: l.is_sliced,
          is_wrapped: l.is_wrapped,
          is_covered: l.is_covered,
          is_scored: l.is_scored,
        })),
      };

      const res = await fetch('/api/orders/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          p_tenant_id: tenantId,
          p_order_id: draft.order_id ?? null,
          p_payload: payload,
        }),
      });

      const json = (await res.json()) as { data?: OrderSaveResult; error?: string };
      if (!res.ok || json.error) {
        setStatusMessage({ text: json.error ?? 'Save failed.', type: 'error' });
        return;
      }
      const resolvedOrderId = json.data?.order_id;
      if (!resolvedOrderId) {
        setStatusMessage({ text: 'Order saved but order id was not returned.', type: 'error' });
        return;
      }

      const refs =
        json.data && Array.isArray(json.data.line_refs) ? json.data.line_refs : [];
      if (refs.length > 0) {
        const refMap = new Map<string, number>();
        for (const ref of refs) {
          if (ref.client_temp_id && typeof ref.order_line_id === 'number') {
            refMap.set(ref.client_temp_id, ref.order_line_id);
          }
        }
        const updatedLines = draft.lines.map((line) => ({
          ...line,
          order_id: resolvedOrderId,
          order_line_id: refMap.get(line.tempId) ?? line.order_line_id,
          tempId: refMap.get(line.tempId) ? String(refMap.get(line.tempId)) : line.tempId,
        }));
        setField('lines', updatedLines);
      }

      setStatusMessage({
        text: json.data?.message ?? 'Order saved.',
        type: 'success',
      });
      reset();
      requestAnimationFrame(() => focusCustomer());
    } finally {
      setIsSaving(false);
    }
  }, [tenantId, draft, mode, reset, setField, focusCustomer]);

  // ── Delete ─────────────────────────────────────────────────────────────

  const handleDelete = useCallback(async () => {
    if (!tenantId || !draft.order_id) return;
    if (!window.confirm(`Delete order ${draft.order_number}?`)) return;

    setIsSaving(true);
    try {
      const res = await fetch('/api/orders/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          p_tenant_id: tenantId,
          p_action: 'delete',
          p_order_id: draft.order_id,
        }),
      });
      const json = await res.json();
      if (!res.ok || json.error) {
        setStatusMessage({ text: json.error ?? 'Delete failed.', type: 'error' });
        return;
      }
      router.push('/manage-orders');
    } finally {
      setIsSaving(false);
    }
  }, [tenantId, draft.order_id, draft.order_number, router]);

  return (
    <div className="flex flex-col h-full bg-background overflow-hidden">
      {/* ── Title bar ─────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-border/60 bg-card shrink-0">
        <div>
          <h2 className="text-base font-semibold text-foreground">
            {mode === 'edit'
              ? 'Edit Order'
              : `Enter Orders - ${draft.customer_name || ''}`}
          </h2>
        </div>
        {/* Status message inline */}
        {statusMessage && (
          <span
            className={
              statusMessage.type === 'success'
                ? 'text-xs text-emerald-600 dark:text-emerald-400 font-medium'
                : 'text-xs text-destructive font-medium'
            }
          >
            {statusMessage.text}
          </span>
        )}
        {/* Header action buttons: Cancel then Save */}
        <div className="flex items-center gap-1.5 shrink-0">
          <Button
            variant="outline"
            size="sm"
            className="h-7 text-xs"
            onClick={handleClear}
            disabled={isSaving}
          >
            Cancel
          </Button>
          <Button
            size="sm"
            className="h-7 text-xs gap-1"
            onClick={handleSave}
            disabled={isSaving || !tenantId}
          >
            <Save className="h-3 w-3" />
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
        </div>
      </div>

      {/* ── ROW 1: Order Header ───────────────────────────────────────── */}
      <div className="shrink-0">
        <OrderHeaderRow
          draft={draft}
          customers={customers}
          isLoadingCustomers={isLoadingCustomers}
          customerInputRef={customerInputRef}
          onCustomerChange={handleCustomerChange}
          onSearchExistingOrders={handleSearchExistingOrders}
          onProductionDateChange={handleProductionDateChange}
          onFieldChange={setField}
        />
      </div>

      {/* ── ROW 2: Item Entry Loop ────────────────────────────────────── */}
      <div className="shrink-0">
        <ItemEntryRow
          items={items}
          isLoadingItems={isLoadingItems}
          disabled={(!draft.customer_id && customers.length > 0) || orderPickOpen || !draft.order_number}
          itemInputRef={itemInputRef}
          qtyRef={qtyRef}
          onCommit={handleItemCommit}
          orderTotal={draft.total_amount + draft.delivery_amount}
          entryToolbar={
            <>
              <Button
                variant="outline"
                size="sm"
                className="h-9 px-3 text-xs"
                disabled
                title="Load a sample order (coming soon)"
              >
                Sample
              </Button>
              <Button
                variant="outline"
                size="sm"
                className="h-9 gap-1 px-3 text-xs"
                onClick={handleClear}
                title="Clear form"
              >
                <RotateCcw className="h-3 w-3" />
                Clear
              </Button>
            </>
          }
        />
        {itemsError && (
          <p className="px-3 pb-1 text-xs text-destructive">
            Item search error: {itemsError}
          </p>
        )}
      </div>

      {/* ── ROW 3: Order Lines Grid ───────────────────────────────────── */}
      <div className="flex-1 overflow-auto px-2 py-2 min-h-0">
        <OrderLineGrid
          lines={draft.lines}
          activeLineIndex={activeLineIndex}
          onLineUpdate={updateLine}
          onLineRemove={removeLine}
          registerGridCell={registerGridCell}
          onDiscountEnter={handleDiscountEnter}
        />
      </div>

      {/* ── Footer: Delete (edit) ──────────────────────────────────────── */}
      <div className="shrink-0 flex items-center justify-between gap-2 px-3 py-2 border-t border-border/60 bg-card">
        <div />

        {mode === 'edit' && draft.order_id && (
          <Button
            variant="destructive"
            size="sm"
            className="h-7 text-xs gap-1"
            onClick={handleDelete}
            disabled={isSaving}
          >
            <Trash2 className="h-3 w-3" />
            Delete
          </Button>
        )}
      </div>

      <OrderPickSheet
        open={orderPickOpen}
        onOpenChange={setOrderPickOpen}
        candidates={orderPickCandidates}
        onNewOrder={handleOrderPickNew}
        onSelect={handleOrderPickSelect}
      />
    </div>
  );
}
