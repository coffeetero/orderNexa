'use client';

import { useEffect, useState } from 'react';
import { Moon, Sun } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { chooseAppearance, nextQuickMode, useAppearanceState } from '@/components/theme/AppearanceProvider';

/** Quick light/dark switch. It writes the same setting as Admin › Appearance (this device's override, else the account). */
export function ThemeToggle() {
  const state = useAppearanceState();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return (
      <Button variant="ghost" size="icon" className="h-9 w-9 opacity-0">
        <Sun className="h-4 w-4" />
      </Button>
    );
  }

  const dark = state.mode === 'dark';
  return (
    <Button
      variant="ghost"
      size="icon"
      className="h-9 w-9 text-foreground/70 hover:text-foreground hover:bg-secondary"
      onClick={() => void chooseAppearance({ mode: nextQuickMode(state.mode), theme: state.current.theme }, state)}
      aria-label={dark ? 'Switch to light mode' : 'Switch to dark mode'}
    >
      {dark ? <Sun className="h-4 w-4 transition-all" /> : <Moon className="h-4 w-4 transition-all" />}
    </Button>
  );
}
