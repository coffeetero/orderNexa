'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Save, Plus, Printer, X, RotateCcw } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { cn } from '@/lib/utils';

type PrepCode = 'SLICED' | 'WRAPPED' | 'COVERED';

interface PrepValue {
  value: PrepCode;
  label: string;
  display_order?: number;
}

interface ItemProfile {
  tenant_id: number;
  item_id: number | null;
  item_number: string;
  item_name: string;
  item_description: string | null;
  category: string | null;
  unit_of_sale: string;
  item_weight: number | null;
  weight_uom: string | null;
  box_qty_per_box: number | null;
  box_capacity_weight: number | null;
  box_capacity_optimal: number | null;
  sales_terms_apply: boolean;
  is_active: boolean;
  allowed_prep_options: PrepCode[];
  default_prep_options: PrepCode[];
  dough_type: string | null;
  shape: string | null;
  packing: string | null;
  machine_setting: string | null;
  sheeter_setting: string | null;
  weight_adjuster: number;
  scale_weight: number;
  scale_qty: number;
}

interface ItemProfilePageProps {
  tenantId?: number;
}

const EMPTY_ITEM: ItemProfile = {
  tenant_id: 0,
  item_id: null,
  item_number: '',
  item_name: '',
  item_description: '',
  category: '',
  unit_of_sale: 'PCS',
  item_weight: null,
  weight_uom: 'LB',
  box_qty_per_box: null,
  box_capacity_weight: null,
  box_capacity_optimal: null,
  sales_terms_apply: true,
  is_active: true,
  allowed_prep_options: [],
  default_prep_options: [],
  dough_type: '',
  shape: '',
  packing: '',
  machine_setting: '',
  sheeter_setting: '',
  weight_adjuster: 0,
  scale_weight: 0,
  scale_qty: 0,
};

const ALLOWED_PREP_LABELS: Record<PrepCode, string> = {
  SLICED: 'Sliceable',
  WRAPPED: 'Wrappable',
  COVERED: 'Coverable',
};

function normalizePrepCodes(raw: unknown): PrepCode[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((value) => String(value).trim().toUpperCase())
    .filter((value): value is PrepCode => (
      value === 'SLICED' || value === 'WRAPPED' || value === 'COVERED'
    ));
}

function normalizeItem(raw: Record<string, unknown>, tenantId: number): ItemProfile {
  return {
    ...EMPTY_ITEM,
    tenant_id: tenantId,
    item_id: typeof raw.item_id === 'number' ? raw.item_id : Number(raw.item_id),
    item_number: String(raw.item_number ?? ''),
    item_name: String(raw.item_name ?? ''),
    item_description: raw.item_description == null ? '' : String(raw.item_description),
    category: raw.category == null ? '' : String(raw.category),
    unit_of_sale: String(raw.unit_of_sale ?? 'PCS'),
    item_weight: raw.item_weight == null ? null : Number(raw.item_weight),
    weight_uom: raw.weight_uom == null ? 'LB' : String(raw.weight_uom),
    box_qty_per_box: raw.box_qty_per_box == null ? null : Number(raw.box_qty_per_box),
    box_capacity_weight: raw.box_capacity_weight == null ? null : Number(raw.box_capacity_weight),
    box_capacity_optimal: raw.box_capacity_optimal == null ? null : Number(raw.box_capacity_optimal),
    sales_terms_apply: raw.sales_terms_apply !== false,
    is_active: raw.is_active !== false,
    allowed_prep_options: normalizePrepCodes(raw.allowed_prep_options),
    default_prep_options: normalizePrepCodes(raw.default_prep_options),
    dough_type: raw.dough_type == null ? '' : String(raw.dough_type),
    shape: raw.shape == null ? '' : String(raw.shape),
    packing: raw.packing == null ? '' : String(raw.packing),
    machine_setting: raw.machine_setting == null ? '' : String(raw.machine_setting),
    sheeter_setting: raw.sheeter_setting == null ? '' : String(raw.sheeter_setting),
    weight_adjuster: raw.weight_adjuster == null ? 0 : Number(raw.weight_adjuster),
    scale_weight: raw.scale_weight == null ? 0 : Number(raw.scale_weight),
    scale_qty: raw.scale_qty == null ? 0 : Number(raw.scale_qty),
  };
}

function uniqueValues(items: ItemProfile[], selector: (item: ItemProfile) => string | null) {
  return Array.from(
    new Set(items.map(selector).filter((value): value is string => Boolean(value?.trim()))),
  ).sort((a, b) => a.localeCompare(b));
}

function FieldLabel({ children }: { children: React.ReactNode }) {
  return <label className="w-24 shrink-0 text-right text-xs font-medium text-foreground">{children}</label>;
}

function TextField({
  label,
  value,
  onChange,
  type = 'text',
  className,
}: {
  label: string;
  value: string | number | null;
  onChange: (value: string) => void;
  type?: string;
  className?: string;
}) {
  return (
    <div className="flex items-center gap-2">
      <FieldLabel>{label}</FieldLabel>
      <Input
        type={type}
        value={value ?? ''}
        onChange={(event) => onChange(event.target.value)}
        className={cn('h-7 rounded-none px-2 py-1 text-xs', className)}
      />
    </div>
  );
}

function ComboField({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string | null;
  options: string[];
  onChange: (value: string) => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <FieldLabel>{label}</FieldLabel>
      <Select value={value || undefined} onValueChange={onChange}>
        <SelectTrigger className="h-7 w-36 rounded-none px-2 py-1 text-xs">
          <SelectValue placeholder="" />
        </SelectTrigger>
        <SelectContent>
          {options.map((option) => (
            <SelectItem key={option} value={option}>{option}</SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}

function PrepCheckbox({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="flex items-center justify-between gap-3 text-xs text-foreground">
      <span>{label}</span>
      <Checkbox checked={checked} onCheckedChange={(value) => onChange(Boolean(value))} className="h-3.5 w-3.5" />
    </label>
  );
}

export function ItemProfilePage({ tenantId }: ItemProfilePageProps) {
  const [items, setItems] = useState<ItemProfile[]>([]);
  const [prepValues, setPrepValues] = useState<PrepValue[]>([]);
  const [selectedItemId, setSelectedItemId] = useState<number | null>(null);
  const [draft, setDraft] = useState<ItemProfile | null>(null);
  const [inactiveOnly, setInactiveOnly] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  const loadItems = useCallback(async () => {
    if (!tenantId) return;
    setIsLoading(true);
    try {
      const response = await fetch(`/api/items/profile?tenant_id=${tenantId}&inactive_only=${inactiveOnly}`);
      const json = (await response.json()) as {
        data?: Record<string, unknown>[];
        prepValues?: PrepValue[];
        error?: string;
      };
      if (!response.ok || json.error) {
        toast.error(json.error ?? 'Could not load item profiles.');
        return;
      }
      const rows = Array.isArray(json.data)
        ? json.data.map((item) => normalizeItem(item, tenantId))
        : [];
      setItems(rows);
      setPrepValues(Array.isArray(json.prepValues) ? json.prepValues : []);
      const preferred = selectedItemId
        ? rows.find((item) => item.item_id === selectedItemId)
        : rows[0];
      setSelectedItemId(preferred?.item_id ?? null);
      setDraft(preferred ? { ...preferred } : null);
    } finally {
      setIsLoading(false);
    }
  }, [inactiveOnly, selectedItemId, tenantId]);

  useEffect(() => {
    void loadItems();
  }, [loadItems]);

  const lists = useMemo(() => ({
    doughTypes: uniqueValues(items, (item) => item.dough_type),
    categories: uniqueValues(items, (item) => item.category),
    shapes: uniqueValues(items, (item) => item.shape),
    packings: uniqueValues(items, (item) => item.packing),
    units: uniqueValues(items, (item) => item.unit_of_sale),
  }), [items]);

  const selectedItem = draft;

  const setDraftField = <K extends keyof ItemProfile>(field: K, value: ItemProfile[K]) => {
    setDraft((prev) => (prev ? { ...prev, [field]: value } : prev));
  };

  const selectItem = (itemId: string | number | null) => {
    if (itemId === '' || itemId === null) {
      setSelectedItemId(null);
      setDraft(null);
      return;
    }
    const numericId = Number(itemId);
    const item = items.find((candidate) => candidate.item_id === numericId) ?? null;
    setSelectedItemId(item?.item_id ?? null);
    setDraft(item ? { ...item } : null);
  };

  const startNewItem = () => {
    const next = { ...EMPTY_ITEM, tenant_id: tenantId ?? 0 };
    setSelectedItemId(null);
    setDraft(next);
  };

  const togglePrep = (code: PrepCode, checked: boolean, mode: 'allowed' | 'default') => {
    setDraft((prev) => {
      if (!prev) return prev;
      const field = mode === 'allowed' ? 'allowed_prep_options' : 'default_prep_options';
      const nextCodes = checked
        ? Array.from(new Set([...prev[field], code]))
        : prev[field].filter((value) => value !== code);
      const next = { ...prev, [field]: nextCodes };
      if (mode === 'allowed' && !checked) {
        next.default_prep_options = next.default_prep_options.filter((value) => value !== code);
      }
      if (mode === 'default' && checked) {
        next.allowed_prep_options = Array.from(new Set([...next.allowed_prep_options, code]));
      }
      return next;
    });
  };

  const saveItem = async () => {
    if (!tenantId || !draft) return;
    setIsSaving(true);
    try {
      const response = await fetch('/api/items/profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...draft, tenant_id: tenantId }),
      });
      const json = (await response.json()) as { data?: { item_id?: number }; error?: string };
      if (!response.ok || json.error) {
        toast.error(json.error ?? 'Could not save item.');
        return;
      }
      toast.success('Item saved.');
      setSelectedItemId(json.data?.item_id ?? draft.item_id);
      await loadItems();
    } finally {
      setIsSaving(false);
    }
  };

  if (!tenantId) {
    return <div className="p-4 text-sm text-muted-foreground">Tenant context is unavailable.</div>;
  }

  return (
    <div className="h-full overflow-hidden bg-background text-foreground">
      <div className="flex h-full flex-col border border-border bg-card">
        <div className="border-b border-border bg-muted/30 px-2 py-1">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0 flex-1">
              <div className="text-xs font-semibold text-foreground">Items</div>
              <div className="flex items-center gap-1">
                <EntityComboBox<ItemProfile>
                  items={items}
                  value={selectedItemId}
                  onChange={(item) => selectItem(item?.item_id ?? null)}
                  getId={(item) => item.item_id ?? 0}
                  getLabel={(item) => `${item.item_number} - ${item.item_name}`}
                  getSearchText={(item) => `${item.item_number} ${item.item_name} ${item.category ?? ''}`}
                  getParentId={() => null}
                  getSortKey={(item) => item.item_number}
                  placeholder={isLoading ? 'Loading items...' : 'Search items…'}
                  disabled={isLoading}
                  loading={isLoading}
                  emptyText="No items found."
                  clearable
                  alwaysOpen
                  collapseOnSelect
                  className="flex-1"
                  triggerClassName="h-7 rounded-none bg-background px-2 py-1 text-xs"
                />
              </div>
            </div>
            <label className="flex shrink-0 items-center gap-2 text-xs">
              <Checkbox checked={inactiveOnly} onCheckedChange={(value) => setInactiveOnly(Boolean(value))} />
              Show Inactives Only
            </label>
          </div>
        </div>

        <div className="flex min-h-0 flex-1">
          <div className="min-w-0 flex-1 overflow-auto px-2 py-2">
            <Tabs defaultValue="item" className="h-full">
              <TabsList className="h-8 rounded-none bg-muted/50 p-0">
                <TabsTrigger value="item" className="h-8 rounded-none px-4 text-xs">Item</TabsTrigger>
                <TabsTrigger value="prices" className="h-8 rounded-none px-4 text-xs">Prices</TabsTrigger>
                <TabsTrigger value="sub-items" className="h-8 rounded-none px-4 text-xs">Sub Items</TabsTrigger>
                <TabsTrigger value="ingredients" className="h-8 rounded-none px-4 text-xs">Ingredients</TabsTrigger>
                <TabsTrigger value="recipe" disabled className="h-8 rounded-none px-4 text-xs">Recipe</TabsTrigger>
                <TabsTrigger value="notes" className="h-8 rounded-none px-4 text-xs">Notes</TabsTrigger>
              </TabsList>

              <TabsContent value="item" className="mt-0 border border-border bg-background p-2">
                {selectedItem ? (
                  <div className="space-y-3">
                    <div className="grid grid-cols-[5rem_minmax(12rem,1fr)_7rem] gap-1">
                      <div>
                        <div className="border border-border bg-yellow-50 px-1 py-0.5 text-center text-xs font-medium text-black">Item No.</div>
                        <Input
                          value={selectedItem.item_number}
                          onChange={(event) => setDraftField('item_number', event.target.value)}
                          className="h-7 rounded-none px-2 py-1 text-xs"
                        />
                      </div>
                      <div>
                        <div className="border border-border bg-yellow-50 px-1 py-0.5 text-xs font-medium text-black">Item Description</div>
                        <Input
                          value={selectedItem.item_name}
                          onChange={(event) => setDraftField('item_name', event.target.value)}
                          className="h-7 rounded-none px-2 py-1 text-xs"
                        />
                      </div>
                      <div>
                        <div className="border border-border bg-yellow-50 px-1 py-0.5 text-center text-xs font-medium text-black">Item Status</div>
                        <Select
                          value={selectedItem.is_active ? 'active' : 'inactive'}
                          onValueChange={(value) => setDraftField('is_active', value === 'active')}
                        >
                          <SelectTrigger className="h-7 rounded-none px-2 py-1 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="active">Active</SelectItem>
                            <SelectItem value="inactive">Inactive</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </div>

                    <div className="grid gap-4 lg:grid-cols-[minmax(15rem,1fr)_minmax(15rem,1fr)_7.5rem]">
                      <div className="space-y-2">
                        <ComboField label="Dough" value={selectedItem.dough_type} options={lists.doughTypes} onChange={(value) => setDraftField('dough_type', value)} />
                        <ComboField label="Ctgry" value={selectedItem.category} options={lists.categories} onChange={(value) => setDraftField('category', value)} />
                        <ComboField label="Shape" value={selectedItem.shape} options={lists.shapes} onChange={(value) => setDraftField('shape', value)} />
                        <ComboField label="Packing" value={selectedItem.packing} options={lists.packings} onChange={(value) => setDraftField('packing', value)} />

                        <fieldset className="mt-3 border border-border p-2">
                          <legend className="px-1 text-xs font-semibold">Box Type</legend>
                          <TextField label="Box Type" value="" onChange={() => {}} className="w-24" />
                          <TextField label="Qty/Size" type="number" value={selectedItem.box_qty_per_box} onChange={(value) => setDraftField('box_qty_per_box', value === '' ? null : Number(value))} className="w-24 text-right" />
                          <TextField label="Qty/Weight" type="number" value={selectedItem.box_capacity_weight} onChange={(value) => setDraftField('box_capacity_weight', value === '' ? null : Number(value))} className="w-24 text-right" />
                          <TextField label="Qty/Optimal" type="number" value={selectedItem.box_capacity_optimal} onChange={(value) => setDraftField('box_capacity_optimal', value === '' ? null : Number(value))} className="w-24 text-right" />
                        </fieldset>
                      </div>

                      <div className="space-y-2">
                        <ComboField label="Units" value={selectedItem.unit_of_sale} options={lists.units.length ? lists.units : ['PCS']} onChange={(value) => setDraftField('unit_of_sale', value)} />
                        <TextField label="Weight" type="number" value={selectedItem.item_weight} onChange={(value) => setDraftField('item_weight', value === '' ? null : Number(value))} className="w-24 text-right" />
                        <TextField label="Wt Adjust" type="number" value={selectedItem.weight_adjuster} onChange={(value) => setDraftField('weight_adjuster', Number(value || 0))} className="w-24 text-right" />
                        <Select
                          value={selectedItem.sales_terms_apply ? 'yes' : 'no'}
                          onValueChange={(value) => setDraftField('sales_terms_apply', value === 'yes')}
                        >
                          <div className="flex items-center gap-2">
                            <FieldLabel>Dscntable</FieldLabel>
                            <SelectTrigger className="h-7 w-24 rounded-none px-2 py-1 text-xs">
                              <SelectValue />
                            </SelectTrigger>
                          </div>
                          <SelectContent>
                            <SelectItem value="yes">Yes</SelectItem>
                            <SelectItem value="no">No</SelectItem>
                          </SelectContent>
                        </Select>
                        <TextField label="Machine Setting" value={selectedItem.machine_setting} onChange={(value) => setDraftField('machine_setting', value)} className="w-28" />
                        <TextField label="Scale Weight" type="number" value={selectedItem.scale_weight} onChange={(value) => setDraftField('scale_weight', Number(value || 0))} className="w-24 text-right" />
                        <TextField label="Qty/Weight" type="number" value={selectedItem.scale_qty} onChange={(value) => setDraftField('scale_qty', Number(value || 0))} className="w-24 text-right" />
                        <TextField label="Sheeter" value={selectedItem.sheeter_setting} onChange={(value) => setDraftField('sheeter_setting', value)} className="w-28" />
                        <label className="flex items-center justify-end gap-2 text-xs">
                          Compound Item
                          <Checkbox disabled className="h-3.5 w-3.5" />
                        </label>
                      </div>

                      <div className="space-y-2 pt-1">
                        {prepValues.map((option) => (
                          <PrepCheckbox
                            key={`allowed-${option.value}`}
                            label={ALLOWED_PREP_LABELS[option.value] ?? option.label}
                            checked={selectedItem.allowed_prep_options.includes(option.value)}
                            onChange={(checked) => togglePrep(option.value, checked, 'allowed')}
                          />
                        ))}
                        <div className="h-2" />
                        {prepValues.map((option) => (
                          <PrepCheckbox
                            key={`default-${option.value}`}
                            label={option.label}
                            checked={selectedItem.default_prep_options.includes(option.value)}
                            onChange={(checked) => togglePrep(option.value, checked, 'default')}
                          />
                        ))}
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="py-12 text-center text-sm text-muted-foreground">
                    {isLoading ? 'Loading items...' : 'No items found.'}
                  </div>
                )}
              </TabsContent>

              {['prices', 'sub-items', 'ingredients', 'notes'].map((tab) => (
                <TabsContent key={tab} value={tab} className="mt-0 border border-border bg-background p-6 text-sm text-muted-foreground">
                  This tab will be connected after the item master profile is in place.
                </TabsContent>
              ))}
            </Tabs>
          </div>

          <div className="w-24 shrink-0 border-l border-border bg-muted/20 px-2 py-7">
            <div className="space-y-2">
              <Button className="h-8 w-full justify-start gap-2 px-2 text-xs" onClick={startNewItem}>
                <Plus className="h-3.5 w-3.5" />
                New
              </Button>
              <Button variant="outline" className="h-8 w-full justify-start gap-2 px-2 text-xs" disabled>
                <Printer className="h-3.5 w-3.5" />
                Print
              </Button>
              <Button variant="outline" className="h-8 w-full justify-start gap-2 px-2 text-xs" disabled={!selectedItem}>
                Delete
              </Button>
              <Button className="h-8 w-full justify-start gap-2 px-2 text-xs" disabled={!selectedItem || isSaving} onClick={saveItem}>
                <Save className="h-3.5 w-3.5" />
                Save
              </Button>
              <Button variant="outline" className="h-8 w-full justify-start gap-2 px-2 text-xs" disabled={!selectedItem} onClick={() => selectedItemId && selectItem(String(selectedItemId))}>
                <RotateCcw className="h-3.5 w-3.5" />
                Cancel
              </Button>
              <Button variant="outline" className="h-8 w-full justify-start gap-2 px-2 text-xs" onClick={() => window.history.back()}>
                <X className="h-3.5 w-3.5" />
                Close
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
