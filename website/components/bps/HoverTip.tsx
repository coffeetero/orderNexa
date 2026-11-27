'use client';

import type { ReactNode } from 'react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';

/**
 * Quick hover label for icon buttons (shows after 200 ms instead of the browser's ~1 s `title`).
 * Wraps the child in a span so it also shows on a disabled button. Give the button an aria-label and no `title`.
 */
export function HoverTip({ label, children }: { label: string; children: ReactNode }) {
  return (
    <TooltipProvider delayDuration={200}>
      <Tooltip>
        <TooltipTrigger asChild>
          <span className="inline-flex">{children}</span>
        </TooltipTrigger>
        <TooltipContent className="px-2 py-1 text-xs">{label}</TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
