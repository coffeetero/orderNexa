'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Save, Plus } from 'lucide-react';
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

export function ItemProfilePage({ tenantId }: ItemProfilePageProps) {
  const [items, setItems] = useState<ItemProfile[]>([]);
  const [prepValues, setPrepValues] = useState<PrepValue[]>([]);
  const [selectedItemId, setSelectedItemId] = useState<number | null>(null);
  const [draft, setDraft] = useState<ItemProfile | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  const loadItems = useCallback(async () => {
    if (!tenantId) return;
    setIsLoading(true);
    try {
      const response = await fetch(`/api/items/profile?tenant_id=${tenantId}&inactive_only=false`);
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
  }, [selectedItemId, tenantId]);

  useEffect(() => {
    void loadItems();
  }, [loadItems]);

  const filteredItems = useMemo(() => {
    if (!searchQuery.trim()) return items;
    const q = searchQuery.toLowerCase();
    return items.filter((item) =>
      item.item_number.toLowerCase().includes(q) ||
      item.item_name.toLowerCase().includes(q)
    );
  }, [items, searchQuery]);

  const lists = useMemo(() => ({
    doughTypes: uniqueValues(items, (item) => item.dough_type),
    categories: uniqueValues(items, (item) => item.category),
    shapes: uniqueValues(items, (item) => item.shape),
    packings: uniqueValues(items, (item) => item.packing),
    units: uniqueValues(items, (item) => item.unit_of_sale),
  }), [items]);

  const setDraftField = <K extends keyof ItemProfile>(field: K, value: ItemProfile[K]) => {
    setDraft((prev) => (prev ? { ...prev, [field]: value } : prev));
  };

  const selectItem = (item: ItemProfile | null) => {
    if (!item) {
      setSelectedItemId(null);
      setDraft(null);
      return;
    }
    setSelectedItemId(item.item_id);
    setDraft({ ...item });
  };

  const startNewItem = () => {
    const next = { ...EMPTY_ITEM, tenant_id: tenantId ?? 0 };
    setSelectedItemId(null);
    setDraft(next);
    setSearchQuery('');
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
    <div className="flex h-full bg-background overflow-hidden">
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        {/* ── Title Bar ─────────────────────────────────────────────────── */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-border/60 bg-card shrink-0">
          <h2 className="text-base font-semibold text-foreground">Item Master</h2>
          <div className="flex items-center gap-1.5 shrink-0">
            <Button
              variant="outline"
              size="sm"
              className="h-8 text-xs gap-1"
              onClick={startNewItem}
              disabled={isSaving}
            >
              <Plus className="h-3.5 w-3.5" />
              New
            </Button>
            <Button
              size="sm"
              className="h-8 text-xs gap-1"
              onClick={saveItem}
              disabled={isSaving || !draft}
            >
              <Save className="h-3.5 w-3.5" />
              {isSaving ? 'Saving…' : 'Save'}
            </Button>
          </div>
        </div>

        {/* ── EntityComboBox for Item Selection ──────────────────────── */}
        <div className="shrink-0 px-4 py-3 border-b border-border/60 bg-muted/30">
          <EntityComboBox
            items={items}
            value={selectedItemId}
            onChange={selectItem}
            getId={(item) => item.item_id ?? 0}
            getLabel={(item) => `${item.item_number} — ${item.item_name}`}
            getParentId={() => null}
            getSearchText={(item) => `${item.item_number} ${item.item_name}`}
            inputValue={searchQuery}
            onInputValueChange={setSearchQuery}
            placeholder="Search or select item..."
            alwaysOpen={true}
            collapseOnSelect={true}
            clearSearchOnFocus={true}
            disabled={isLoading}
            loading={isLoading}
            clearable={true}
          />
        </div>

        {/* ── Main Form Area ────────────────────────────────────────── */}
        <div className="flex-1 overflow-auto flex flex-col">
            {draft ? (
              <>
                <Tabs defaultValue="profile" className="flex-1 flex flex-col overflow-hidden">
                  <TabsList className="shrink-0 h-10 rounded-none border-b border-border/60 bg-muted/50 p-0 justify-start px-4">
                    <TabsTrigger value="profile" className="h-10 rounded-none px-4 text-xs">Profile</TabsTrigger>
                    <TabsTrigger value="dimensions" className="h-10 rounded-none px-4 text-xs">Dimensions</TabsTrigger>
                    <TabsTrigger value="production" className="h-10 rounded-none px-4 text-xs">Production</TabsTrigger>
                    <TabsTrigger value="pricing" disabled className="h-10 rounded-none px-4 text-xs">Pricing</TabsTrigger>
                    <TabsTrigger value="notes" className="h-10 rounded-none px-4 text-xs">Notes</TabsTrigger>
                  </TabsList>

                  {/* Profile Tab */}
                  <TabsContent value="profile" className="flex-1 overflow-auto p-6">
                    <div className="space-y-6 max-w-4xl">
                      <div className="grid grid-cols-3 gap-4">
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Item Number</label>
                          <Input
                            value={draft.item_number}
                            onChange={(e) => setDraftField('item_number', e.target.value)}
                            className="text-sm"
                            placeholder="SKU or item code"
                          />
                        </div>
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Description</label>
                          <Input
                            value={draft.item_name}
                            onChange={(e) => setDraftField('item_name', e.target.value)}
                            className="text-sm"
                            placeholder="Item description"
                          />
                        </div>
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Status</label>
                          <Select value={draft.is_active ? 'active' : 'inactive'} onValueChange={(v) => setDraftField('is_active', v === 'active')}>
                            <SelectTrigger className="text-sm">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="active">Active</SelectItem>
                              <SelectItem value="inactive">Inactive</SelectItem>
                            </SelectContent>
                          </Select>
                        </div>
                      </div>

                      <div>
                        <div className="grid grid-cols-4 gap-4">
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Category</label>
                            <Select value={draft.category || ''} onValueChange={(v) => setDraftField('category', v)}>
                              <SelectTrigger className="text-sm">
                                <SelectValue placeholder="Select..." />
                              </SelectTrigger>
                              <SelectContent>
                                {lists.categories.map((cat) => (
                                  <SelectItem key={cat} value={cat}>{cat}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Dough Type</label>
                            <Select value={draft.dough_type || ''} onValueChange={(v) => setDraftField('dough_type', v)}>
                              <SelectTrigger className="text-sm">
                                <SelectValue placeholder="Select..." />
                              </SelectTrigger>
                              <SelectContent>
                                {lists.doughTypes.map((dt) => (
                                  <SelectItem key={dt} value={dt}>{dt}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Shape</label>
                            <Select value={draft.shape || ''} onValueChange={(v) => setDraftField('shape', v)}>
                              <SelectTrigger className="text-sm">
                                <SelectValue placeholder="Select..." />
                              </SelectTrigger>
                              <SelectContent>
                                {lists.shapes.map((shape) => (
                                  <SelectItem key={shape} value={shape}>{shape}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Unit of Sale</label>
                            <Select value={draft.unit_of_sale || 'PCS'} onValueChange={(v) => setDraftField('unit_of_sale', v)}>
                              <SelectTrigger className="text-sm">
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                {(lists.units.length ? lists.units : ['PCS']).map((unit) => (
                                  <SelectItem key={unit} value={unit}>{unit}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>
                      </div>

                      <div>
                        <div className="grid grid-cols-2 gap-6">
                          <div>
                            <p className="text-xs font-medium text-muted-foreground mb-2">Allowed Prep Options</p>
                            <div className="space-y-2">
                              {prepValues.map((option) => (
                                <label key={`allowed-${option.value}`} className="flex items-center gap-2 text-sm cursor-pointer">
                                  <Checkbox
                                    checked={draft.allowed_prep_options.includes(option.value)}
                                    onCheckedChange={(checked) => togglePrep(option.value, Boolean(checked), 'allowed')}
                                  />
                                  <span>{option.label}</span>
                                </label>
                              ))}
                            </div>
                          </div>
                          <div>
                            <p className="text-xs font-medium text-muted-foreground mb-2">Default Prep Options</p>
                            <div className="space-y-2">
                              {prepValues.map((option) => (
                                <label key={`default-${option.value}`} className="flex items-center gap-2 text-sm cursor-pointer">
                                  <Checkbox
                                    checked={draft.default_prep_options.includes(option.value)}
                                    onCheckedChange={(checked) => togglePrep(option.value, Boolean(checked), 'default')}
                                  />
                                  <span>{option.label}</span>
                                </label>
                              ))}
                            </div>
                          </div>
                        </div>
                      </div>

                      <label className="flex items-center gap-2 text-sm cursor-pointer">
                        <Checkbox
                          checked={draft.sales_terms_apply}
                          onCheckedChange={(v) => setDraftField('sales_terms_apply', Boolean(v))}
                        />
                        <span>Eligible for discount</span>
                      </label>
                    </div>
                  </TabsContent>

                  {/* Dimensions Tab */}
                  <TabsContent value="dimensions" className="flex-1 overflow-auto p-6">
                    <div className="space-y-6 max-w-4xl">
                      <div>
                        <h3 className="text-sm font-semibold mb-4">Item Weight</h3>
                        <div className="grid grid-cols-2 gap-4">
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Weight</label>
                            <Input
                              type="number"
                              value={draft.item_weight ?? ''}
                              onChange={(e) => setDraftField('item_weight', e.target.value === '' ? null : Number(e.target.value))}
                              className="text-sm"
                              placeholder="0"
                            />
                          </div>
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Unit</label>
                            <Input
                              value={draft.weight_uom ?? ''}
                              onChange={(e) => setDraftField('weight_uom', e.target.value)}
                              className="text-sm"
                              placeholder="LB"
                            />
                          </div>
                        </div>
                      </div>

                      <div>
                        <h3 className="text-sm font-semibold mb-4">Box Capacity</h3>
                        <div className="grid grid-cols-3 gap-4">
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Qty per Box</label>
                            <Input
                              type="number"
                              value={draft.box_qty_per_box ?? ''}
                              onChange={(e) => setDraftField('box_qty_per_box', e.target.value === '' ? null : Number(e.target.value))}
                              className="text-sm"
                              placeholder="0"
                            />
                          </div>
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Weight Capacity</label>
                            <Input
                              type="number"
                              value={draft.box_capacity_weight ?? ''}
                              onChange={(e) => setDraftField('box_capacity_weight', e.target.value === '' ? null : Number(e.target.value))}
                              className="text-sm"
                              placeholder="0"
                            />
                          </div>
                          <div>
                            <label className="text-xs font-medium text-muted-foreground mb-1 block">Optimal Capacity</label>
                            <Input
                              type="number"
                              value={draft.box_capacity_optimal ?? ''}
                              onChange={(e) => setDraftField('box_capacity_optimal', e.target.value === '' ? null : Number(e.target.value))}
                              className="text-sm"
                              placeholder="0"
                            />
                          </div>
                        </div>
                      </div>
                    </div>
                  </TabsContent>

                  {/* Production Tab */}
                  <TabsContent value="production" className="flex-1 overflow-auto p-6">
                    <div className="space-y-6 max-w-4xl">
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Packing</label>
                          <Select value={draft.packing || ''} onValueChange={(v) => setDraftField('packing', v)}>
                            <SelectTrigger className="text-sm">
                              <SelectValue placeholder="Select..." />
                            </SelectTrigger>
                            <SelectContent>
                              {lists.packings.map((pack) => (
                                <SelectItem key={pack} value={pack}>{pack}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Machine Setting</label>
                          <Input
                            value={draft.machine_setting ?? ''}
                            onChange={(e) => setDraftField('machine_setting', e.target.value)}
                            className="text-sm"
                            placeholder="Machine setting code"
                          />
                        </div>
                      </div>

                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Weight Adjuster</label>
                          <Input
                            type="number"
                            value={draft.weight_adjuster ?? 0}
                            onChange={(e) => setDraftField('weight_adjuster', Number(e.target.value || 0))}
                            className="text-sm"
                            placeholder="0"
                          />
                        </div>
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Sheeter Setting</label>
                          <Input
                            value={draft.sheeter_setting ?? ''}
                            onChange={(e) => setDraftField('sheeter_setting', e.target.value)}
                            className="text-sm"
                            placeholder="Sheeter setting code"
                          />
                        </div>
                      </div>

                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Scale Weight</label>
                          <Input
                            type="number"
                            value={draft.scale_weight ?? 0}
                            onChange={(e) => setDraftField('scale_weight', Number(e.target.value || 0))}
                            className="text-sm"
                            placeholder="0"
                          />
                        </div>
                        <div>
                          <label className="text-xs font-medium text-muted-foreground mb-1 block">Scale Quantity</label>
                          <Input
                            type="number"
                            value={draft.scale_qty ?? 0}
                            onChange={(e) => setDraftField('scale_qty', Number(e.target.value || 0))}
                            className="text-sm"
                            placeholder="0"
                          />
                        </div>
                      </div>
                    </div>
                  </TabsContent>

                  {/* Pricing Tab (placeholder) */}
                  <TabsContent value="pricing" className="flex-1 p-6">
                    <div className="text-sm text-muted-foreground">Pricing integration coming soon.</div>
                  </TabsContent>

                  {/* Notes Tab (placeholder) */}
                  <TabsContent value="notes" className="flex-1 overflow-auto p-6">
                    <div className="text-sm text-muted-foreground">Notes section coming soon.</div>
                  </TabsContent>
                </Tabs>
              </>
            ) : (
              <div className="flex-1 flex items-center justify-center text-muted-foreground">
                <div className="text-center">
                  <p className="text-sm mb-3">No item selected</p>
                  <Button onClick={startNewItem} size="sm">
                    <Plus className="h-3.5 w-3.5 mr-2" />
                    Create New Item
                  </Button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
