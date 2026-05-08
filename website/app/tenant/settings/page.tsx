'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { createClient } from '@/lib/supabase/client';

type ResetPeriod = 'NEVER' | 'DAILY' | 'MONTHLY' | 'YEARLY';

interface SequenceSettings {
  start_value: number;
  next_value: number;
  increment_by: number;
  mask: string;
  reset_period: ResetPeriod;
  requires_gapless: boolean;
}

const defaultOrderSequence: SequenceSettings = {
  start_value: 1000,
  next_value: 1000,
  increment_by: 1,
  mask: 'ORD[YYYYMMDD]##.OP202',
  reset_period: 'DAILY',
  requires_gapless: false,
};

export default function TenantSettingsPage() {
  const [tenantId, setTenantId] = useState<number | null>(null);
  const [orderSequence, setOrderSequence] = useState<SequenceSettings>(defaultOrderSequence);
  const [statusMessage, setStatusMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getSession().then(async ({ data }) => {
      const tid = data.session?.user?.app_metadata?.tenant_id;
      const parsedTenantId =
        typeof tid === 'number' ? tid : typeof tid === 'string' ? Number.parseInt(tid, 10) : null;
      if (!parsedTenantId || Number.isNaN(parsedTenantId)) return;
      setTenantId(parsedTenantId);

      const { data: sequence } = await supabase
        .from('fnd_tenant_sequences')
        .select('start_value, next_value, increment_by, mask, reset_period, requires_gapless')
        .eq('tenant_id', parsedTenantId)
        .eq('sequence_name', 'order_number')
        .maybeSingle();

      if (sequence) {
        setOrderSequence({
          start_value: Number(sequence.start_value ?? defaultOrderSequence.start_value),
          next_value: Number(sequence.next_value ?? defaultOrderSequence.next_value),
          increment_by: Number(sequence.increment_by ?? defaultOrderSequence.increment_by),
          mask: String(sequence.mask ?? defaultOrderSequence.mask),
          reset_period: (sequence.reset_period as ResetPeriod | null) ?? defaultOrderSequence.reset_period,
          requires_gapless: Boolean(sequence.requires_gapless),
        });
      }
    });
  }, []);

  const setNumberField = useCallback((field: 'start_value' | 'next_value' | 'increment_by', value: string) => {
    const parsed = Number.parseInt(value, 10);
    setOrderSequence((current) => ({
      ...current,
      [field]: Number.isFinite(parsed) ? parsed : 0,
    }));
  }, []);

  const handleSave = useCallback(async () => {
    if (!tenantId) {
      setStatusMessage({ text: 'Tenant context was not found.', type: 'error' });
      return;
    }

    setIsSaving(true);
    setStatusMessage(null);
    const supabase = createClient();
    const { error } = await supabase
      .from('fnd_tenant_sequences')
      .upsert({
        tenant_id: tenantId,
        sequence_name: 'order_number',
        ...orderSequence,
        is_active: true,
      });

    setIsSaving(false);
    if (error) {
      setStatusMessage({ text: error.message, type: 'error' });
      return;
    }
    setStatusMessage({ text: 'Order number sequence saved.', type: 'success' });
  }, [tenantId, orderSequence]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Account Settings</h1>
          <p className="text-sm text-muted-foreground">Tenant numbering and document settings.</p>
        </div>
        <Button size="sm" onClick={handleSave} disabled={isSaving}>
          {isSaving ? 'Saving...' : 'Save'}
        </Button>
      </div>

      {statusMessage && (
        <p className={statusMessage.type === 'success' ? 'text-sm text-emerald-600' : 'text-sm text-destructive'}>
          {statusMessage.text}
        </p>
      )}

      <Card className="border-border/60">
        <CardContent className="space-y-4 p-4">
          <div>
            <h2 className="text-base font-semibold tracking-tight">Order Number Sequence</h2>
            <p className="text-xs text-muted-foreground">
              Mask tokens include # for the number and date tokens such as [YYYYMMDD].
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <div className="space-y-1.5">
              <Label htmlFor="sequence-mask">Mask</Label>
              <Input
                id="sequence-mask"
                value={orderSequence.mask}
                onChange={(event) => setOrderSequence((current) => ({ ...current, mask: event.target.value }))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="start-value">Start Value</Label>
              <Input
                id="start-value"
                type="number"
                min={0}
                value={orderSequence.start_value}
                onChange={(event) => setNumberField('start_value', event.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="next-value">Next Value</Label>
              <Input
                id="next-value"
                type="number"
                min={0}
                value={orderSequence.next_value}
                onChange={(event) => setNumberField('next_value', event.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="increment-by">Increment By</Label>
              <Input
                id="increment-by"
                type="number"
                min={1}
                value={orderSequence.increment_by}
                onChange={(event) => setNumberField('increment_by', event.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Reset Period</Label>
              <Select
                value={orderSequence.reset_period}
                onValueChange={(value) =>
                  setOrderSequence((current) => ({ ...current, reset_period: value as ResetPeriod }))
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="NEVER">Never</SelectItem>
                  <SelectItem value="DAILY">Daily</SelectItem>
                  <SelectItem value="MONTHLY">Monthly</SelectItem>
                  <SelectItem value="YEARLY">Yearly</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-end gap-2 pb-2">
              <Checkbox
                id="requires-gapless"
                checked={orderSequence.requires_gapless}
                onCheckedChange={(checked) =>
                  setOrderSequence((current) => ({ ...current, requires_gapless: Boolean(checked) }))
                }
              />
              <Label htmlFor="requires-gapless">Requires gapless numbers</Label>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
