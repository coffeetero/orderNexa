'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Save, Trash2, RotateCcw } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { createClient } from '@/lib/supabase/client';
import {
  OrderHeaderRow,
  type CustomerOption,
  type DepartmentEventOption,
} from './OrderHeaderRow';
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
  PrepOption,
  ProductionCode,
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
    total_quantity: Number(raw.total_quantity ?? 0),
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
  return type === 'DEPARTMENT' || type === 'LOCATION';
}

function normalizeDepartmentEventText(value: string): string {
  return value.trim().toUpperCase();
}

function normalizePrepOptions(raw: unknown): PrepOption[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((option): option is Record<string, unknown> => (
      option !== null
      && typeof option === 'object'
      && typeof (option as Record<string, unknown>).value === 'string'
    ))
    .map((option) => {
      const value = String(option.value).trim();
      const label = typeof option.label === 'string' && option.label.trim()
        ? option.label.trim()
        : value;
      return { value, label };
    })
    .filter((option) => option.value.length > 0);
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
  const [isLoadingOrderPickCandidates, setIsLoadingOrderPickCandidates] = useState(false);
  const [departmentEventOptions, setDepartmentEventOptions] = useState<DepartmentEventOption[]>([]);
  const [selectedDepartmentEventId, setSelectedDepartmentEventId] = useState<string | null>(null);
  const [isLoadingDepartmentEvents, setIsLoadingDepartmentEvents] = useState(false);
  const [productionCodes, setProductionCodes] = useState<{ value: string; label: string }[]>([]);
  const [isLoadingCustomers, setIsLoadingCustomers] = useState(false);
  const [isLoadingItems, setIsLoadingItems] = useState(false);
  const [itemsError, setItemsError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [productionDateBlockedOpen, setProductionDateBlockedOpen] = useState(false);
  const [shouldFocusItemWhenReady, setShouldFocusItemWhenReady] = useState(false);
  const productionDateBlockedOkRef = useRef<HTMLButtonElement | null>(null);

  const showStatusMessage = useCallback(
    (message: { text: string; type: 'success' | 'error' } | null) => {
      if (!message) {
        toast.dismiss();
        return;
      }

      if (message.type === 'success') {
        toast.success(message.text);
      } else {
        toast.error(message.text);
      }
    },
    [],
  );

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
    zeroLinePrices,
    getLineQty,
  } = useOrderEntryState(initialData);

  const {
    customerInputRef,
    departmentEventInputRef,
    productionDateInputRef,
    productionCodeTriggerRef,
    itemInputRef,
    qtyRef,
    focusCustomer,
    focusDepartmentEvent,
    focusProductionCode,
    focusItem,
    focusQty,
    focusGridCell,
    registerGridCell,
  } = useOrderFocus();

  const [activeLineIndex, setActiveLineIndex] = useState<number | null>(null);

  useEffect(() => {
    focusCustomer();
  }, [focusCustomer]);

  const mapOrderToDraft = useCallback((data: Record<string, unknown>): OrderEntryDraft => {
    const lines = (Array.isArray(data.lines) ? data.lines : []).map((l: Record<string, unknown>) => ({
      tempId: String(l.order_line_id ?? crypto.randomUUID()),
      order_id: l.order_id as number,
      order_line_id: l.order_line_id as number,
      item_id: l.item_id as number,
      item_number: (l.item_number as string) ?? '',
      item_description: (l.item_description as string) ?? '',
      allowed_prep_options: normalizePrepOptions(l.allowed_prep_options),
      prep_options: normalizePrepOptions(l.prep_options),
      is_scored: Boolean(l.is_scored),
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
      production_code: (data.production_code as string) ?? '',
      delivery_amount: Number(data.delivery_amount ?? 0),
      total_amount: totalAmount,
      lines,
    };
  }, []);

  /** Serializes slot lookups so rapid header changes don't apply stale results. */
  const slotLookupGenerationRef = useRef(0);
  const orderPickLookupGenerationRef = useRef(0);
  const suppressNextSlotLookupRef = useRef(false);

  const getDefaultDepartmentEvent = useCallback(
    (customerId: number | null): string => {
      if (customerId == null) return '';
      const customer = customers.find((candidate) => candidate.customer_id === customerId);
      if (!customer) return '';

      return isDepartmentEventCustomer(customer) ? customer.customer_name.toUpperCase() : 'ORDER';
    },
    [customers],
  );

  const buildDepartmentEventOptions = useCallback(
    (customerId: number | null): DepartmentEventOption[] => {
      if (customerId === null) return [];

      const selectedCustomer = customers.find((customer) => customer.customer_id === customerId);
      if (!selectedCustomer) return [];

      const customersById = new Map(
        customers.map((customer) => [customer.customer_id, customer]),
      );
      const hasAncestor = (customer: CustomerOption, ancestorId: number): boolean => {
        let currentParentId = customer.customer_parent_id;
        const seen = new Set<number>();
        while (currentParentId !== null && !seen.has(currentParentId)) {
          if (currentParentId === ancestorId) return true;
          seen.add(currentParentId);
          currentParentId = customersById.get(currentParentId)?.customer_parent_id ?? null;
        }
        return false;
      };

      const optionValues: string[] = [];
      if (isDepartmentEventCustomer(selectedCustomer)) {
        const rootCustomerId = selectedCustomer.customer_parent_id ?? selectedCustomer.customer_id;
        const departmentCustomers = customers
          .filter((customer) => (
            isDepartmentEventCustomer(customer)
            && (
              customer.customer_id === rootCustomerId
              || hasAncestor(customer, rootCustomerId)
            )
          ))
          .sort((a, b) => a.sort_path.localeCompare(b.sort_path));
        optionValues.push(...departmentCustomers.map((customer) => customer.customer_name));
      } else {
        optionValues.push('ORDER');
        const departmentChildren = customers
          .filter((customer) => (
            isDepartmentEventCustomer(customer)
            && hasAncestor(customer, selectedCustomer.customer_id)
          ))
          .sort((a, b) => a.sort_path.localeCompare(b.sort_path));
        optionValues.push(...departmentChildren.map((customer) => customer.customer_name));
      }

      const options: DepartmentEventOption[] = [];
      const seen = new Set<string>();
      for (const value of optionValues) {
        const departmentEvent = normalizeDepartmentEventText(value);
        if (!departmentEvent || seen.has(departmentEvent)) continue;
        seen.add(departmentEvent);
        options.push({
          id: `new:${departmentEvent}`,
          order_id: null,
          order_number: null,
          department_event: departmentEvent,
          total_quantity: 0,
          amount: 0,
          is_new: true,
        });
      }
      return options;
    },
    [customers],
  );

  const departmentEventListRequestKey = [
    draft.customer_id ?? 'none',
    draft.production_date,
    draft.production_code,
  ].join('|');

  const loadOrderById = useCallback(
    async (
      targetOrderId: number,
      opts?: { generation?: number; preserveSelectedCustomer?: boolean },
    ) => {
      if (!tenantId || !targetOrderId) return;
      const gen = opts?.generation;
      const selectedCustomerId = draft.customer_id;
      const selectedCustomerName = draft.customer_name;
      showStatusMessage(null);
      let response: Response;
      try {
        response = await fetch(
          `/api/orders?tenant_id=${tenantId}&order_id=${targetOrderId}&headers_only=false`,
        );
      } catch {
        showStatusMessage({ text: 'Could not load order lines. Network request failed.', type: 'error' });
        return;
      }

      const json = (await response.json().catch(() => ({}))) as {
        data?: Record<string, unknown> | null;
        error?: unknown;
      };
      if (!response.ok || json.error) {
        showStatusMessage({
          text: getErrorMessage(json.error, 'Could not load order lines.'),
          type: 'error',
        });
        return;
      }
      if (!json.data || typeof json.data !== 'object') {
        showStatusMessage({ text: 'Order detail was empty; no lines were loaded.', type: 'error' });
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
    [tenantId, draft.customer_id, draft.customer_name, loadOrder, mapOrderToDraft, showStatusMessage],
  );

  // ── Load PRODUCTIONCODE valueset, default draft.production_code ───────────
  useEffect(() => {
    if (tenantId === null) return;
    fetch(`/api/valuesets?tenant_id=${tenantId}&code=PRODUCTIONCODE`)
      .then((r) => r.json())
      .then(({ data }: { data?: { value: string; label: string }[] }) => {
        const codes = data ?? [];
        setProductionCodes(codes);
        if (codes.length > 0) {
          setField('production_code', codes[0].value);
        }
      })
      .catch(() => {});
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId]);

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

  const handleDepartmentEventListRequest = useCallback(() => {
    if (!tenantId || !draft.customer_id || !draft.production_date) {
      setDepartmentEventOptions([]);
      setSelectedDepartmentEventId(null);
      return;
    }
    if (mode === 'edit' && orderId != null) return;
    if (suppressNextSlotLookupRef.current) {
      suppressNextSlotLookupRef.current = false;
      return;
    }

    const generation = ++slotLookupGenerationRef.current;
    setIsLoadingDepartmentEvents(true);
    showStatusMessage(null);

    const options = buildDepartmentEventOptions(draft.customer_id);
    if (generation !== slotLookupGenerationRef.current) return;

    setDepartmentEventOptions(options);
    setSelectedDepartmentEventId(null);
    setField('order_number', 'New Order');
    setField('order_ref', 'New Order');
    setField('order_id', undefined);
    setField('lines', []);
    setField('total_amount', 0);
    setOrderPickOpen(false);
    setIsLoadingDepartmentEvents(false);
  }, [
    tenantId,
    draft.customer_id,
    draft.production_date,
    buildDepartmentEventOptions,
    mode,
    orderId,
    setField,
    showStatusMessage,
  ]);

  // ── Load existing order in edit mode ──────────────────────────────────
  useEffect(() => {
    if (mode !== 'edit' || !orderId || !tenantId || initialData) return;
    fetch(`/api/orders?tenant_id=${tenantId}&order_id=${orderId}&headers_only=false`)
      .then((r) => r.json())
      .then(({ data, error }) => {
        if (error) {
          showStatusMessage({
            text: getErrorMessage(error, 'Could not load order lines.'),
            type: 'error',
          });
          return;
        }
        if (!data || typeof data !== 'object') {
          showStatusMessage({ text: 'Order detail was empty; no lines were loaded.', type: 'error' });
          return;
        }
        loadOrder(mapOrderToDraft(data as Record<string, unknown>));
      })
      .catch(() => {
        showStatusMessage({ text: 'Could not load order lines. Network request failed.', type: 'error' });
      });
  }, [mode, orderId, tenantId, initialData, loadOrder, mapOrderToDraft, showStatusMessage]);

  // ── Focus on initial load ──────────────────────────────────────────────
  useEffect(() => {
    if (mode === 'new') {
      focusCustomer();
    } else {
      focusItem();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!productionDateBlockedOpen) return;
    requestAnimationFrame(() => productionDateBlockedOkRef.current?.focus());
  }, [productionDateBlockedOpen]);

  // ── Event handlers ─────────────────────────────────────────────────────

  const handleSearchExistingOrders = useCallback(async () => {
    if (!tenantId || !draft.production_date) return;
    const generation = ++orderPickLookupGenerationRef.current;
    showStatusMessage(null);
    setOrderPickCandidates([]);
    setOrderPickMode(draft.customer_id === null ? 'global-search' : 'customer-scoped');
    setOrderPickOpen(true);
    setIsLoadingOrderPickCandidates(true);
    try {
      const rows = await fetchOrderHeaders(draft.customer_id);
      if (generation !== orderPickLookupGenerationRef.current) return;
      if (rows.length === 0) {
        setOrderPickCandidates([]);
        setOrderPickOpen(false);
        showStatusMessage({ text: 'No existing orders found for this production slot.', type: 'error' });
        return;
      }

      setOrderPickMode(draft.customer_id === null ? 'global-search' : 'customer-scoped');
      setOrderPickCandidates(rows);
      setOrderPickOpen(true);
    } catch (error) {
      if (generation !== orderPickLookupGenerationRef.current) return;
      setOrderPickOpen(false);
      showStatusMessage({
        text: error instanceof Error ? error.message : 'Could not find existing orders.',
        type: 'error',
      });
    } finally {
      if (generation === orderPickLookupGenerationRef.current) {
        setIsLoadingOrderPickCandidates(false);
      }
    }
  }, [tenantId, draft.production_date, draft.customer_id, fetchOrderHeaders, showStatusMessage]);

  const handleOrderPickOpenChange = useCallback((nextOpen: boolean) => {
    if (!nextOpen) {
      orderPickLookupGenerationRef.current += 1;
      setIsLoadingOrderPickCandidates(false);
      requestAnimationFrame(() => focusCustomer());
    }
    setOrderPickOpen(nextOpen);
  }, [focusCustomer]);

  const handleCustomerChange = useCallback(
    (customer: CustomerOption | null) => {
      setShouldFocusItemWhenReady(false);
      setCustomer(customer?.customer_id ?? null, customer?.customer_name ?? '');
      setField('department_event', getDefaultDepartmentEvent(customer?.customer_id ?? null));
      setDepartmentEventOptions([]);
      setSelectedDepartmentEventId(null);
      setIsLoadingDepartmentEvents(false);
      setField('order_number', '');
      setField('order_ref', '');
      setField('order_id', undefined);
      setField('lines', []);
      setField('total_amount', 0);
    },
    [getDefaultDepartmentEvent, setCustomer, setField],
  );

  const warnIfExistingOrderLoaded = useCallback(() => {
    if (!draft.order_id) return false;
    window.alert('Save any changes before changing production date or production code.');
    return true;
  }, [draft.order_id]);

  const handleProductionDateChange = useCallback(
    (value: string) => {
      const daysAhead = daysAfterToday(value);
      if (daysAhead !== null && daysAhead > 7) {
        setProductionDateBlockedOpen(true);
        return;
      }
      if (warnIfExistingOrderLoaded()) return;
      setDepartmentEventOptions([]);
      setSelectedDepartmentEventId(null);
      setIsLoadingDepartmentEvents(false);
      setField('production_date', value);
    },
    [setField, warnIfExistingOrderLoaded],
  );

  const handleProductionCodeChange = useCallback(
    (value: ProductionCode) => {
      if (warnIfExistingOrderLoaded()) return;
      setDepartmentEventOptions([]);
      setSelectedDepartmentEventId(null);
      setIsLoadingDepartmentEvents(false);
      setField('production_code', value);
    },
    [setField, warnIfExistingOrderLoaded],
  );

  const handleDepartmentEventInputChange = useCallback(
    (value: string) => {
      setSelectedDepartmentEventId(null);
      setField('department_event', value.toUpperCase());
    },
    [setField],
  );

  const handleDepartmentEventCommit = useCallback(
    (value: string) => {
      setSelectedDepartmentEventId(null);
      setField('department_event', value.toUpperCase());
      setField('order_id', undefined);
      setField('order_number', 'New Order');
      setField('order_ref', 'New Order');
      setShouldFocusItemWhenReady(true);
    },
    [setField],
  );

  const handleDepartmentEventSelect = useCallback(
    (option: DepartmentEventOption | null) => {
      if (!option) {
        setSelectedDepartmentEventId(null);
        setField('department_event', '');
        setField('order_id', undefined);
        setField('order_number', 'New Order');
        setField('order_ref', 'New Order');
        setField('lines', []);
        setField('total_amount', 0);
        return;
      }

      setSelectedDepartmentEventId(option.id);
      setField('department_event', option.department_event.toUpperCase());

      if (option.is_new || option.order_id === null) {
        setField('order_id', undefined);
        setField('order_number', 'New Order');
        setField('order_ref', 'New Order');
        setField('lines', []);
        setField('total_amount', 0);
        setShouldFocusItemWhenReady(true);
        return;
      }

      suppressNextSlotLookupRef.current = true;
      setField('order_id', option.order_id);
      setField('order_number', option.order_number ?? '');
      setField('order_ref', option.order_number ?? '');
      void loadOrderById(option.order_id, {
        preserveSelectedCustomer: true,
      });
    },
    [loadOrderById, setField],
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
    reset({ preserveProductionSlot: true });
    setDepartmentEventOptions([]);
    setSelectedDepartmentEventId(null);
    focusCustomer();
  }, [reset, focusCustomer]);

  const handleSample = useCallback(() => {
    zeroLinePrices();
  }, [zeroLinePrices]);

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

  const canSave = Boolean(tenantId) && draft.lines.length > 0;

  const handleSave = useCallback(async () => {
    if (!canSave || !tenantId || isSaving) return;

    const isExistingOrder = !!draft.order_id;
    const visibleOrderNumber = draft.order_number.trim();
    const orderNumber =
      visibleOrderNumber === 'New Order'
        ? (!isExistingOrder ? 'New Order' : '')
        : visibleOrderNumber || (!isExistingOrder ? 'New Order' : '');
    if (!orderNumber.trim()) {
      showStatusMessage({ text: 'Order number is missing for this order.', type: 'error' });
      return;
    }

    setIsSaving(true);
    showStatusMessage(null);
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
          prep_options: l.prep_options,
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
        showStatusMessage({ text: json.error ?? 'Save failed.', type: 'error' });
        return;
      }
      const resolvedOrderId = json.data?.order_id;
      if (!resolvedOrderId) {
        showStatusMessage({ text: 'Order saved but order id was not returned.', type: 'error' });
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

      showStatusMessage({
        text: json.data?.message ?? 'Order saved.',
        type: 'success',
      });
      reset({ preserveProductionSlot: true });
      setDepartmentEventOptions([]);
      setSelectedDepartmentEventId(null);
      requestAnimationFrame(() => focusCustomer());
    } finally {
      setIsSaving(false);
    }
  }, [canSave, tenantId, isSaving, draft, reset, setField, focusCustomer, showStatusMessage]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (isSaving) return;

      if (event.code === 'NumpadSubtract') {
        event.preventDefault();
        handleClear();
        return;
      }

      if (event.code === 'NumpadDivide') {
        event.preventDefault();
        void handleSearchExistingOrders();
        return;
      }

      if (event.code !== 'NumpadMultiply') return;
      event.preventDefault();
      if (document.activeElement instanceof HTMLElement) {
        document.activeElement.blur();
      }
      void handleSave();
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleClear, handleSave, handleSearchExistingOrders, isSaving]);

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
        showStatusMessage({ text: json.error ?? 'Delete failed.', type: 'error' });
        return;
      }
      router.push('/manage-orders');
    } finally {
      setIsSaving(false);
    }
  }, [tenantId, draft.order_id, draft.order_number, router, showStatusMessage]);

  return (
    <div className="flex h-full bg-background overflow-hidden">
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        {/* ── Title bar ─────────────────────────────────────────────────── */}
        <div className="flex items-center justify-between px-3 py-2 border-b border-border/60 bg-card shrink-0">
          <div>
            <h2 className="text-base font-semibold text-foreground">
              {mode === 'edit'
                ? 'Edit Order'
                : `Enter Orders - ${draft.customer_name || ''}`}
            </h2>
          </div>
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
              disabled={isSaving || !canSave}
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
            productionCodes={productionCodes}
            customerInputRef={customerInputRef}
            departmentEventInputRef={departmentEventInputRef}
            productionDateInputRef={productionDateInputRef}
            productionCodeTriggerRef={productionCodeTriggerRef}
            departmentEventOptions={departmentEventOptions}
            selectedDepartmentEventId={selectedDepartmentEventId}
            isLoadingDepartmentEvents={isLoadingDepartmentEvents}
            onCustomerChange={handleCustomerChange}
            onCustomerAfterSelect={focusDepartmentEvent}
            onSearchExistingOrders={handleSearchExistingOrders}
            onDepartmentEventInputChange={handleDepartmentEventInputChange}
            onDepartmentEventSelect={handleDepartmentEventSelect}
            onDepartmentEventCommit={handleDepartmentEventCommit}
            onDepartmentEventListRequest={handleDepartmentEventListRequest}
            departmentEventListRequestKey={departmentEventListRequestKey}
            onProductionDateChange={handleProductionDateChange}
            onProductionCodeChange={handleProductionCodeChange}
            onProductionDateEnter={focusProductionCode}
            onProductionCodeEnter={focusCustomer}
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
                  onClick={handleSample}
                  disabled={isSaving || draft.lines.length === 0}
                  title="Zero line prices for a sample order"
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
      </div>

      <OrderPickSheet
        open={orderPickOpen}
        onOpenChange={handleOrderPickOpenChange}
        candidates={orderPickCandidates}
        loading={isLoadingOrderPickCandidates}
        onNewOrder={handleOrderPickNew}
        onSelect={handleOrderPickSelect}
      />
      <AlertDialog open={productionDateBlockedOpen} onOpenChange={setProductionDateBlockedOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Production Date</AlertDialogTitle>
            <AlertDialogDescription>
              Future orders are limited to a 7-day window
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogAction ref={productionDateBlockedOkRef}>OK</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

