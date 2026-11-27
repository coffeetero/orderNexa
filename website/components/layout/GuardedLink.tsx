'use client';

import * as React from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useNav } from '@/components/layout/nav-context';

/**
 * next/link that first asks the current page whether it has unsaved changes (see useNavGuard).
 * Modified clicks (new tab/window) are not intercepted. Outside a NavProvider it behaves like a plain Link.
 */
export const GuardedLink = React.forwardRef<HTMLAnchorElement, React.ComponentProps<typeof Link>>(
  function GuardedLink({ onClick, ...props }, ref) {
    const { confirmLeave } = useNav();
    const router = useRouter();
    return (
      <Link
        ref={ref}
        {...props}
        onClick={(e) => {
          onClick?.(e);
          if (e.defaultPrevented) return;
          if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
          const href = typeof props.href === 'string' ? props.href : null;
          if (!confirmLeave(href ? () => router.push(href) : undefined)) e.preventDefault();
        }}
      />
    );
  },
);
