'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Copy, Save, Trash2, X, RotateCcw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { createClient } from '@/lib/supabase/client';
import { OrderHeaderRow, type CustomerOption } from './OrderHeaderRow';
import { ItemEntryRow } from './ItemEntryRow';
import { OrderLineGrid } from './OrderLineGrid';
import { useOrderEntryState } from './useOrderEntryState';
import { useOrderFocus } from './useOrderFocus';
import type { OrderEntryDraft, OrderEntryItem } from '@/lib/types';

interface OrderEntryFormProps {
  mode: 'new' | 'edit';
  /** Provided in edit mode — the form fetches the order on mount. */
  orderId?: number;
  /** Pre-loaded initial draft — can be supplied by a server component to skip the first fetch. */
  initialData?: OrderEntryDraft;
  /** Tenant id pre-resolved server-side via fnd_get_tenants. */
  serverTenantId?: number;
  /** Customer list pre-loaded server-side. When provided the client-side customer fetch is skipped. */
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
  const [isLoadingCustomers, setIsLoadingCustomers] = useState(false);
  const [isLoadingItems, setIsLoadingItems] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [statusMessage, setStatusMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);

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

  // ── Fetch customers when tenantId is ready ─────────────────────────────
  // Skip if the server already supplied the customer list.
  useEffect(() => {
    if (serverCustomers !== undefined) return;
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
    setIsLoadingItems(true);
    const qs = draft.customer_id
      ? `tenant_id=${tenantId}&customer_id=${draft.customer_id}`
      : `tenant_id=${tenantId}`;
    fetch(`/api/items?${qs}`)
      .then((r) => r.json())
      .then(({ data }) => {
        if (Array.isArray(data)) setItems(data as OrderEntryItem[]);
      })
      .finally(() => setIsLoadingItems(false));
  }, [tenantId, draft.customer_id]);

  // ── Load existing order in edit mode ──────────────────────────────────
  useEffect(() => {
    if (mode !== 'edit' || !orderId || !tenantId || initialData) return;
    fetch(`/api/orders?tenant_id=${tenantId}&order_id=${orderId}`)
      .then((r) => r.json())
      .then(({ data }) => {
        if (!data) return;
        // Map API response to OrderEntryDraft
        const lines = (data.lines ?? []).map((l: Record<string, unknown>) => ({
          tempId: String(l.order_line_id ?? crypto.randomUUID()),
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
        loadOrder({
          order_id: data.order_id as number,
          order_number: (data.order_number as string) ?? '',
          customer_id: (data.customer_id as number) ?? null,
          customer_name: (data.customer_name as string) ?? '',
          customer_credit: 0,
          order_date: (data.order_date as string) ?? new Date().toISOString().slice(0, 10),
          delivery_date: (data.delivery_date as string) ?? new Date().toISOString().slice(0, 10),
          delivery_window: (data.delivery_window as 'AM' | 'PM' | 'SPECIAL') ?? 'AM',
          delivery_amount: Number(data.delivery_amount ?? 0),
          total_amount: totalAmount,
          lines,
        });
      });
  }, [mode, orderId, tenantId, initialData, loadOrder]);

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

  const handleCustomerChange = useCallback(
    (customer: CustomerOption | null) => {
      setCustomer(customer?.customer_id ?? null, customer?.customer_name ?? '');
    },
    [setCustomer],
  );

  const handleCustomerAfterSelect = useCallback(() => {
    focusItem();
  }, [focusItem]);

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

  // ── Save ───────────────────────────────────────────────────────────────

  const handleSave = useCallback(async () => {
    if (!tenantId) return;
    if (!draft.order_number.trim()) {
      setStatusMessage({ text: 'Invoice No. is required.', type: 'error' });
      return;
    }

    setIsSaving(true);
    setStatusMessage(null);
    try {
      const payload = {
        customer_id: draft.customer_id,
        order_number: draft.order_number,
        order_date: draft.order_date,
        delivery_date: draft.delivery_date,
        delivery_window: draft.delivery_window,
        delivery_amount: draft.delivery_amount,
        lines: draft.lines.map((l) => ({
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

      const isEdit = mode === 'edit' && !!draft.order_id;
      const res = await fetch('/api/orders/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          p_tenant_id: tenantId,
          p_action: isEdit ? 'update' : 'create',
          p_order_id: isEdit ? draft.order_id : null,
          p_payload: payload,
        }),
      });

      const json = await res.json();
      if (!res.ok || json.error) {
        setStatusMessage({ text: json.error ?? 'Save failed.', type: 'error' });
        return;
      }
      setStatusMessage({ text: json.data?.message ?? 'Order saved.', type: 'success' });
      // Update order_id in draft state after create
      if (!isEdit && json.data?.order_id) {
        setField('order_id', json.data.order_id as number);
      }
    } finally {
      setIsSaving(false);
    }
  }, [tenantId, draft, mode, setField]);

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
      router.push('/account/orders');
    } finally {
      setIsSaving(false);
    }
  }, [tenantId, draft.order_id, draft.order_number, router]);

  const handleClose = useCallback(() => {
    router.push('/account/orders');
  }, [router]);

  // ── Today's date for the footer date display ───────────────────────────
  const todayLabel = new Date().toLocaleDateString('en-US', {
    month: '2-digit',
    day: '2-digit',
    year: '2-digit',
  });

  return (
    <div className="flex flex-col h-full bg-background overflow-hidden">
      {/* ── Title bar ─────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-border/60 bg-card shrink-0">
        <div>
          <h2
            className="text-base font-semibold text-foreground"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            {mode === 'edit' ? 'Edit Order' : 'New Order'} — Order Entry
          </h2>
          {draft.order_number && (
            <p className="text-xs text-muted-foreground">
              Invoice {draft.order_number}
              {draft.customer_name ? ` · ${draft.customer_name}` : ''}
            </p>
          )}
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
        {/* Header action buttons: Retrieve (stub), Sample (stub), Clear */}
        <div className="flex items-center gap-1.5">
          <Button
            variant="outline"
            size="sm"
            className="h-7 text-xs"
            disabled
            title="Retrieve order by invoice number (coming soon)"
          >
            Retrieve
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-7 text-xs"
            disabled
            title="Load a sample order (coming soon)"
          >
            Sample
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-7 text-xs gap-1"
            onClick={handleClear}
            title="Clear form"
          >
            <RotateCcw className="h-3 w-3" />
            Clear
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
          onCustomerAfterSelect={handleCustomerAfterSelect}
          onFieldChange={setField}
        />
      </div>

      {/* ── ROW 2: Item Entry Loop ────────────────────────────────────── */}
      <div className="shrink-0">
        <ItemEntryRow
          items={items}
          isLoadingItems={isLoadingItems}
          disabled={!draft.customer_id && customers.length > 0}
          itemInputRef={itemInputRef}
          qtyRef={qtyRef}
          onCommit={handleItemCommit}
        />
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

      {/* ── Footer: Action Buttons ────────────────────────────────────── */}
      <div className="shrink-0 flex items-center justify-between gap-2 px-3 py-2 border-t border-border/60 bg-card">
        {/* Left: date + Copy From (stub) */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted-foreground tabular-nums">{todayLabel}</span>
          <Button
            variant="outline"
            size="sm"
            className="h-7 text-xs gap-1"
            disabled
            title="Copy from another order (coming soon)"
          >
            <Copy className="h-3 w-3" />
            Copy From
          </Button>
        </div>

        {/* Right: Delete / Save / Cancel / Close */}
        <div className="flex items-center gap-1.5">
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
          <Button
            size="sm"
            className="h-7 text-xs gap-1"
            onClick={handleSave}
            disabled={isSaving || !tenantId}
          >
            <Save className="h-3 w-3" />
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
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
            variant="ghost"
            size="sm"
            className="h-7 text-xs gap-1"
            onClick={handleClose}
            disabled={isSaving}
          >
            <X className="h-3 w-3" />
            Close
          </Button>
        </div>
      </div>
    </div>
  );
}
