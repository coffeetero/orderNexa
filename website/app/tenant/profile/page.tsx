'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { createClient } from '@/lib/supabase/client';

interface UserPreferences {
  time_zone: string;
  language: string;
  number_format: string;
  currency_format: string;
  date_format: string;
  time_format: string;
}

const fallbackPreferences: UserPreferences = {
  time_zone: '',
  language: '',
  number_format: '',
  currency_format: '',
  date_format: 'MM/dd/yyyy',
  time_format: 'h:mm a',
};

function browserPreferences(): UserPreferences {
  if (typeof window === 'undefined') return fallbackPreferences;
  const resolved = Intl.DateTimeFormat().resolvedOptions();
  const language = navigator.language || resolved.locale || '';
  return {
    time_zone: resolved.timeZone || '',
    language,
    number_format: language,
    currency_format: resolved.locale || language,
    date_format: fallbackPreferences.date_format,
    time_format: fallbackPreferences.time_format,
  };
}

export default function TenantProfilePage() {
  const [preferences, setPreferences] = useState<UserPreferences>(fallbackPreferences);
  const [authUserId, setAuthUserId] = useState<string | null>(null);
  const [statusMessage, setStatusMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    const defaults = browserPreferences();
    setPreferences(defaults);

    supabase.auth.getUser().then(async ({ data }) => {
      const userId = data.user?.id ?? null;
      setAuthUserId(userId);
      if (!userId) return;

      const { data: profile } = await supabase
        .from('fnd_users')
        .select('time_zone, language, number_format, currency_format, date_format, time_format')
        .eq('auth_user_id', userId)
        .maybeSingle();

      if (profile) {
        setPreferences({
          time_zone: profile.time_zone || defaults.time_zone,
          language: profile.language || defaults.language,
          number_format: profile.number_format || defaults.number_format,
          currency_format: profile.currency_format || defaults.currency_format,
          date_format: profile.date_format || defaults.date_format,
          time_format: profile.time_format || defaults.time_format,
        });
      }
    });
  }, []);

  const setField = useCallback(
    (field: keyof UserPreferences, value: string) => {
      setPreferences((current) => ({ ...current, [field]: value }));
    },
    [],
  );

  const handleSave = useCallback(async () => {
    if (!authUserId) {
      setStatusMessage({ text: 'User session was not found.', type: 'error' });
      return;
    }

    setIsSaving(true);
    setStatusMessage(null);
    const supabase = createClient();
    const { error } = await supabase
      .from('fnd_users')
      .update(preferences)
      .eq('auth_user_id', authUserId);

    setIsSaving(false);
    if (error) {
      setStatusMessage({ text: error.message, type: 'error' });
      return;
    }
    setStatusMessage({ text: 'Profile preferences saved.', type: 'success' });
  }, [authUserId, preferences]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">User Profile</h1>
          <p className="text-sm text-muted-foreground">Locale and formatting preferences.</p>
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
        <CardContent className="grid gap-4 p-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="time-zone">Time Zone</Label>
            <Input id="time-zone" value={preferences.time_zone} onChange={(e) => setField('time_zone', e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="language">Language</Label>
            <Input id="language" value={preferences.language} onChange={(e) => setField('language', e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="number-format">Number Format</Label>
            <Input id="number-format" value={preferences.number_format} onChange={(e) => setField('number_format', e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="currency-format">Currency Format</Label>
            <Input id="currency-format" value={preferences.currency_format} onChange={(e) => setField('currency_format', e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="date-format">Date Format</Label>
            <Input id="date-format" value={preferences.date_format} onChange={(e) => setField('date_format', e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="time-format">Time Format</Label>
            <Input id="time-format" value={preferences.time_format} onChange={(e) => setField('time_format', e.target.value)} />
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
