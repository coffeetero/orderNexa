'use client';

/**
 * BPS: Hierarchical entity combobox — Popover + trigger, or **alwaysOpen** inline search + list.
 */

import * as React from 'react';
import { Check, ChevronsUpDown, Loader2, X } from 'lucide-react';

import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';

function idKey(id: string | number): string {
  return String(id);
}

export type EntityComboBoxProps<T> = {
  items: T[];
  /** Current selection id, or null. */
  value: string | number | null;
  onChange: (item: T | null) => void;
  getId: (item: T) => string | number;
  /** Single-line display for the trigger (popover mode) and list rows. */
  getLabel: (item: T) => string;
  getParentId: (item: T) => string | number | null;
  /** Text used for substring search; defaults to getLabel. */
  getSearchText?: (item: T) => string;
  /** Sort visible rows; defaults to stable order by getId. */
  getSortKey?: (item: T) => string;
  placeholder?: string;
  disabled?: boolean;
  loading?: boolean;
  /** When true (default), a direct search match also includes all descendants in the result set. */
  includeChildren?: boolean;
  /** When false, rows included only as ancestors of a match (not a direct hit) cannot be selected. */
  contextParentsSelectable?: boolean;
  maxResults?: number;
  emptyText?: string;
  clearable?: boolean;
  className?: string;
  triggerClassName?: string;
  contentClassName?: string;
  /** Popover trigger / alwaysOpen search input id (label `htmlFor`). */
  triggerId?: string;

  /** Inline layout: no trigger button; search + list always visible (list may collapse after select). */
  alwaysOpen?: boolean;
  /** When `alwaysOpen`, hide the list after selection until the user focuses search or types again. */
  collapseOnSelect?: boolean;
  /**
   * When `alwaysOpen`, focusing the search field clears it and expands the list.
   * On blur, if the field is still empty and there is a selection, the label is restored.
   */
  clearSearchOnFocus?: boolean;
  /** Called after `onChange` when a row is chosen (keyboard, click, or Enter). */
  onAfterSelect?: (item: T) => void;
};

type RowModel<T> = {
  item: T;
  idStr: string;
  level: number;
  contextOnly: boolean;
};

function highlightMatches(text: string, queryLower: string): React.ReactNode {
  if (!queryLower.trim()) return text;
  const q = queryLower.trim();
  const lower = text.toLowerCase();
  const out: React.ReactNode[] = [];
  let pos = 0;
  let key = 0;
  while (pos < text.length) {
    const idx = lower.indexOf(q, pos);
    if (idx === -1) {
      out.push(text.slice(pos));
      break;
    }
    if (idx > pos) out.push(text.slice(pos, idx));
    out.push(
      <mark
        key={key++}
        className="rounded bg-accent px-0.5 text-accent-foreground [text-decoration:inherit]"
      >
        {text.slice(idx, idx + q.length)}
      </mark>
    );
    pos = idx + q.length;
  }
  return out;
}

function itemLevel<T>(
  item: T,
  byId: Map<string, T>,
  getId: (item: T) => string | number,
  getParentId: (item: T) => string | number | null
): number {
  let depth = 0;
  let current: T | undefined = item;
  const visited = new Set<string>();
  for (;;) {
    const pid = getParentId(current);
    if (pid === null) break;
    const pk = idKey(pid);
    if (visited.has(pk)) break;
    visited.add(pk);
    const parent = byId.get(pk);
    if (!parent) break;
    depth++;
    current = parent;
  }
  return depth;
}

function computeFilter<T>(
  items: T[],
  searchRaw: string,
  getId: (item: T) => string | number,
  getParentId: (item: T) => string | number | null,
  getSearchText: (item: T) => string,
  includeChildren: boolean
): { included: Set<string>; matched: Set<string> } {
  const searchLower = searchRaw.trim().toLowerCase();
  const included = new Set<string>();
  const matched = new Set<string>();
  const byId = new Map<string, T>();
  items.forEach((it) => byId.set(idKey(getId(it)), it));

  const childrenByParent = new Map<string | null, string[]>();
  items.forEach((item) => {
    const pid = getParentId(item);
    const key = pid === null ? null : idKey(pid);
    const cid = idKey(getId(item));
    const list = childrenByParent.get(key) ?? [];
    list.push(cid);
    childrenByParent.set(key, list);
  });

  const includeAncestors = (startId: string) => {
    let currentId: string | null = startId;
    const seen = new Set<string>();
    while (currentId !== null) {
      if (seen.has(currentId)) break;
      seen.add(currentId);
      const node = byId.get(currentId);
      if (!node) break;
      included.add(currentId);
      const pid = getParentId(node);
      if (pid === null) break;
      currentId = idKey(pid);
    }
  };

  const includeDescendants = (startId: string) => {
    const queue = [...(childrenByParent.get(startId) ?? [])];
    const seen = new Set<string>();
    while (queue.length > 0) {
      const cid = queue.shift()!;
      if (seen.has(cid)) continue;
      seen.add(cid);
      included.add(cid);
      const next = childrenByParent.get(cid) ?? [];
      queue.push(...next);
    }
  };

  if (!searchLower) {
    items.forEach((item) => included.add(idKey(getId(item))));
    included.forEach((id) => matched.add(id));
    return { included, matched };
  }

  items.forEach((item) => {
    const idStr = idKey(getId(item));
    const hay = getSearchText(item).toLowerCase();
    if (hay.includes(searchLower)) {
      matched.add(idStr);
      includeAncestors(idStr);
      if (includeChildren) {
        includeDescendants(idStr);
      }
      included.add(idStr);
    }
  });

  return { included, matched };
}

export function EntityComboBox<T>({
  items,
  value,
  onChange,
  getId,
  getLabel,
  getParentId,
  getSearchText: getSearchTextProp,
  getSortKey,
  placeholder = 'Select…',
  disabled,
  loading,
  includeChildren = true,
  contextParentsSelectable = true,
  maxResults = 2000,
  emptyText = 'No results.',
  clearable,
  className,
  triggerClassName,
  contentClassName,
  triggerId,
  alwaysOpen = false,
  collapseOnSelect = false,
  clearSearchOnFocus = false,
  onAfterSelect,
}: EntityComboBoxProps<T>) {
  const [open, setOpen] = React.useState(false);
  const [query, setQuery] = React.useState('');
  const [listCollapsed, setListCollapsed] = React.useState(false);
  const searchInputRef = React.useRef<HTMLInputElement | null>(null);
  const prevValueRef = React.useRef(value);
  const blurRestoreTimerRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  const cancelBlurRestoreTimer = React.useCallback(() => {
    if (blurRestoreTimerRef.current !== null) {
      clearTimeout(blurRestoreTimerRef.current);
      blurRestoreTimerRef.current = null;
    }
  }, []);

  const getSearchText = getSearchTextProp ?? getLabel;

  const selectedItem = React.useMemo(() => {
    if (value === null || value === undefined) return undefined;
    const vk = idKey(value);
    return items.find((item) => idKey(getId(item)) === vk);
  }, [getId, items, value]);

  const byId = React.useMemo(() => {
    const m = new Map<string, T>();
    items.forEach((it) => m.set(idKey(getId(it)), it));
    return m;
  }, [getId, items]);

  const { rows, truncated } = React.useMemo(() => {
    const { included, matched } = computeFilter(
      items,
      query,
      getId,
      getParentId,
      getSearchText,
      includeChildren
    );

    const filtered = items.filter((item) => included.has(idKey(getId(item))));

    const sortKeyFn = getSortKey ?? ((item: T) => idKey(getId(item)));
    filtered.sort((a, b) => sortKeyFn(a).localeCompare(sortKeyFn(b)));

    const q = query.trim().toLowerCase();
    const list: RowModel<T>[] = [];
    for (const item of filtered) {
      const idStr = idKey(getId(item));
      const contextOnly = Boolean(q) && !matched.has(idStr);
      list.push({
        item,
        idStr,
        level: itemLevel(item, byId, getId, getParentId),
        contextOnly,
      });
      if (list.length >= maxResults) break;
    }

    return {
      rows: list,
      truncated: filtered.length > maxResults,
    };
  }, [
    byId,
    getId,
    getParentId,
    getSearchText,
    getSortKey,
    includeChildren,
    items,
    maxResults,
    query,
  ]);

  React.useEffect(() => {
    if (alwaysOpen) return;
    if (!open) {
      setQuery('');
    }
  }, [alwaysOpen, open]);

  /** Keep search text aligned with `value` when it changes externally (not while the user is typing). */
  React.useEffect(() => {
    if (!alwaysOpen) return;
    if (prevValueRef.current !== value) {
      prevValueRef.current = value;
      if (selectedItem) {
        setQuery(getLabel(selectedItem));
      } else {
        setQuery('');
      }
    }
  }, [alwaysOpen, getLabel, selectedItem, value]);

  React.useEffect(() => {
    if (!alwaysOpen) return;
    const id = requestAnimationFrame(() => {
      searchInputRef.current?.focus();
    });
    return () => cancelAnimationFrame(id);
  }, [alwaysOpen]);

  React.useEffect(() => {
    return () => {
      if (blurRestoreTimerRef.current !== null) {
        clearTimeout(blurRestoreTimerRef.current);
      }
    };
  }, []);

  const commitSelection = React.useCallback(
    (item: T) => {
      cancelBlurRestoreTimer();
      const label = getLabel(item);
      // In alwaysOpen + collapse mode, keep query cleared so reopening shows full list.
      if (alwaysOpen && collapseOnSelect) {
        setQuery('');
      } else {
        setQuery(label);
      }
      onChange(item);
      onAfterSelect?.(item);
      if (alwaysOpen && collapseOnSelect) {
        setListCollapsed(true);
        // Prevent immediate re-open loops when cmdk keeps focus on the input.
        requestAnimationFrame(() => {
          searchInputRef.current?.blur();
        });
      }
      if (!alwaysOpen) {
        setOpen(false);
      }
    },
    [
      alwaysOpen,
      cancelBlurRestoreTimer,
      collapseOnSelect,
      getLabel,
      onAfterSelect,
      onChange,
    ]
  );

  const handleQueryChange = React.useCallback(
    (next: string) => {
      cancelBlurRestoreTimer();
      setQuery(next);
      if (alwaysOpen && collapseOnSelect && listCollapsed) {
        setListCollapsed(false);
      }
    },
    [alwaysOpen, cancelBlurRestoreTimer, collapseOnSelect, listCollapsed]
  );

  const handleSearchBlur = React.useCallback(() => {
    if (!alwaysOpen || !clearSearchOnFocus) return;
    cancelBlurRestoreTimer();
    blurRestoreTimerRef.current = setTimeout(() => {
      blurRestoreTimerRef.current = null;
      setQuery((q) => {
        if (q.trim() !== '') return q;
        if (selectedItem) return getLabel(selectedItem);
        return q;
      });
    }, 150);
  }, [
    alwaysOpen,
    cancelBlurRestoreTimer,
    clearSearchOnFocus,
    getLabel,
    selectedItem,
  ]);

  const handleSearchFocus = React.useCallback(() => {
    cancelBlurRestoreTimer();
    if (alwaysOpen && clearSearchOnFocus) {
      setQuery('');
      setListCollapsed(false);
      return;
    }
    if (alwaysOpen && collapseOnSelect && listCollapsed) {
      setListCollapsed(false);
    }
  }, [
    alwaysOpen,
    cancelBlurRestoreTimer,
    clearSearchOnFocus,
    collapseOnSelect,
    listCollapsed,
  ]);

  const triggerLabel = selectedItem ? getLabel(selectedItem) : null;

  const rowIsDisabled = (contextOnly: boolean) =>
    Boolean(contextOnly) && !contextParentsSelectable;

  const listSection =
    loading ? (
      <div className="flex items-center justify-center gap-2 py-6 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" />
        Loading…
      </div>
    ) : rows.length === 0 ? (
      <CommandEmpty>{emptyText}</CommandEmpty>
    ) : (
      <CommandGroup>
        {rows.map(({ item, idStr, level, contextOnly }) => {
          const selected = value !== null && idKey(value) === idStr;
          const rowDisabled = rowIsDisabled(contextOnly);
          const label = getLabel(item);
          const display = highlightMatches(label, query.trim().toLowerCase());

          return (
            <CommandItem
              key={idStr}
              value={idStr}
              disabled={rowDisabled}
              onSelect={() => {
                if (rowDisabled) return;
                commitSelection(item);
              }}
              className="cursor-pointer data-[disabled=true]:cursor-not-allowed"
            >
              <Check
                className={cn(
                  'mr-2 h-4 w-4 shrink-0',
                  selected ? 'opacity-100' : 'opacity-0'
                )}
              />
              <span
                className="min-w-0 flex-1 truncate font-mono text-xs leading-snug"
                style={{ paddingLeft: level * 10 }}
              >
                {display}
              </span>
            </CommandItem>
          );
        })}
        {truncated ? (
          <div className="px-2 py-1.5 text-center text-[11px] text-muted-foreground">
            Showing first {maxResults} matches. Refine search to see more.
          </div>
        ) : null}
      </CommandGroup>
    );

  if (alwaysOpen) {
    return (
      <div
        className={cn(
          listCollapsed ? 'flex flex-col' : 'flex min-h-0 flex-1 flex-col',
          className
        )}
      >
        <div
          className={cn(
            listCollapsed
              ? 'relative flex flex-col overflow-visible rounded-md border border-input bg-background'
              : 'relative flex min-h-0 flex-1 flex-col overflow-visible rounded-md border border-input bg-background',
            triggerClassName
          )}
        >
          <Command
            shouldFilter={false}
            className={cn(
              listCollapsed
                ? 'flex flex-col overflow-visible rounded-md bg-popover text-popover-foreground'
                : 'flex min-h-0 flex-1 flex-col overflow-visible rounded-md bg-popover text-popover-foreground'
            )}
          >
            <div className="flex gap-1 px-1 pt-1 [&_[cmdk-input-wrapper]]:min-h-0 [&_[cmdk-input-wrapper]]:flex-1 [&_[cmdk-input-wrapper]]:border-0 [&_[cmdk-input-wrapper]]:px-2">
              <CommandInput
                ref={searchInputRef}
                id={triggerId}
                placeholder={placeholder}
                value={query}
                onValueChange={handleQueryChange}
                onFocus={handleSearchFocus}
                onBlur={handleSearchBlur}
                disabled={loading || disabled}
                className="h-9 py-2"
              />
              {clearable && selectedItem ? (
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="h-9 w-9 shrink-0 self-center"
                  disabled={disabled}
                  onClick={(event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    cancelBlurRestoreTimer();
                    onChange(null);
                    setQuery('');
                    setListCollapsed(false);
                  }}
                  aria-label="Clear selection"
                >
                  <X className="h-4 w-4 opacity-60" />
                </Button>
              ) : null}
            </div>
            {/* Always mount CommandList: cmdk keeps listInnerRef on it — unmounting caused Array.from(null) in cmdk. */}
            <CommandList
              hidden={listCollapsed}
              className={cn(
                'absolute left-0 right-0 top-full z-50 mt-1 max-h-[600px] overflow-y-auto overflow-x-hidden rounded-md border border-input bg-popover shadow-md',
                listCollapsed && 'pointer-events-none',
                contentClassName
              )}
            >
              {listSection}
            </CommandList>
          </Command>
        </div>
      </div>
    );
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <div className={cn('flex w-full gap-1', className)}>
        <PopoverTrigger asChild>
          <Button
            id={triggerId}
            type="button"
            variant="outline"
            role="combobox"
            aria-expanded={open}
            disabled={disabled}
            className={cn(
              'h-9 min-w-0 flex-1 justify-between font-normal',
              !triggerLabel && 'text-muted-foreground',
              triggerClassName
            )}
            onKeyDown={(event) => {
              if (!open || event.key !== 'Enter') return;
              event.preventDefault();
              searchInputRef.current?.focus();
            }}
          >
            <span className="truncate text-left">{triggerLabel ?? placeholder}</span>
            <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
          </Button>
        </PopoverTrigger>
        {clearable && selectedItem ? (
          <Button
            type="button"
            variant="outline"
            size="icon"
            className="h-9 w-9 shrink-0"
            disabled={disabled}
            onClick={(event) => {
              event.preventDefault();
              event.stopPropagation();
              onChange(null);
            }}
            aria-label="Clear selection"
          >
            <X className="h-4 w-4 opacity-60" />
          </Button>
        ) : null}
      </div>
      <PopoverContent
        className={cn(
          'w-[var(--radix-popover-trigger-width)] min-w-[260px] p-0',
          contentClassName
        )}
        align="start"
        onOpenAutoFocus={(event) => {
          event.preventDefault();
          requestAnimationFrame(() => searchInputRef.current?.focus());
        }}
        onCloseAutoFocus={(event) => event.preventDefault()}
      >
        <Command shouldFilter={false}>
          <CommandInput
            ref={searchInputRef}
            placeholder="Search…"
            value={query}
            onValueChange={setQuery}
            disabled={loading}
          />
          <CommandList className="max-h-[min(320px,calc(100vh-12rem))]">
            {listSection}
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
