'use client';

/**
 * BPS: Hierarchical entity combobox — Popover + trigger, or **alwaysOpen** inline search + list.
 */

import * as React from 'react';
import { Check, ChevronDown, ChevronsUpDown, Loader2, X } from 'lucide-react';

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
  /** Text shown in the inline search input after selection; defaults to getLabel. */
  getInputLabel?: (item: T) => string;
  getParentId: (item: T) => string | number | null;
  /** Text used for substring search; defaults to getLabel. */
  getSearchText?: (item: T) => string;
  /** Controlled text for alwaysOpen input. */
  inputValue?: string;
  /** Called when the alwaysOpen input text changes. */
  onInputValueChange?: (value: string) => void;
  /** Called when Enter is pressed while no selectable row is available. */
  onInputCommit?: (value: string) => void;
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
  /** Initial collapsed state for `alwaysOpen`; defaults to `collapseOnSelect`. */
  initialListCollapsed?: boolean;
  /**
   * When `alwaysOpen`, focusing the search field clears it and expands the list.
   * On blur, if the field is still empty and there is a selection, the label is restored.
   */
  clearSearchOnFocus?: boolean;
  /** Called after `onChange` when a row is chosen (keyboard, click, or Enter). */
  onAfterSelect?: (item: T) => void;

  /**
   * External ref that will be populated with the internal search <input>.
   * Works in both popover and alwaysOpen modes.
   * Use this to imperatively focus the search field from parent components.
   */
  inputRef?: React.RefObject<HTMLInputElement>;

  /**
   * External ref populated with the popover trigger <button>.
   * Only used in popover mode (alwaysOpen = false).
   */
  triggerRef?: React.RefObject<HTMLButtonElement>;
};

type RowModel<T> = {
  item: T;
  idStr: string;
  level: number;
  contextOnly: boolean;
};

type PreparedItem<T> = {
  item: T;
  idStr: string;
  parentIdStr: string | null;
  searchTextLower: string;
  sortKey: string;
  level: number;
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

export function EntityComboBox<T>({
  items,
  value,
  onChange,
  getId,
  getLabel,
  getInputLabel,
  getParentId,
  getSearchText: getSearchTextProp,
  inputValue,
  onInputValueChange,
  onInputCommit,
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
  initialListCollapsed,
  clearSearchOnFocus = false,
  onAfterSelect,
  inputRef,
  triggerRef,
}: EntityComboBoxProps<T>) {
  const [open, setOpen] = React.useState(false);
  const [query, setQuery] = React.useState('');
  const [filterQuery, setFilterQuery] = React.useState('');
  const [listCollapsed, setListCollapsed] = React.useState(
    initialListCollapsed ?? collapseOnSelect
  );
  const searchInputRef = React.useRef<HTMLInputElement | null>(null);
  const listRef = React.useRef<HTMLDivElement | null>(null);
  const prevValueRef = React.useRef(value);
  const blurRestoreTimerRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const pointerDownOnListRef = React.useRef(false);
  const isInputControlled = inputValue !== undefined;
  const currentInputValue = isInputControlled ? inputValue : query;

  React.useEffect(() => {
    if (!alwaysOpen) return;
    setListCollapsed(initialListCollapsed ?? collapseOnSelect);
  }, [alwaysOpen, collapseOnSelect, initialListCollapsed]);

  // Sync external refs on every render so callers always have the current element.
  React.useEffect(() => {
    if (inputRef) {
      (inputRef as React.MutableRefObject<HTMLInputElement | null>).current =
        searchInputRef.current;
    }
  });

  const cancelBlurRestoreTimer = React.useCallback(() => {
    if (blurRestoreTimerRef.current !== null) {
      clearTimeout(blurRestoreTimerRef.current);
      blurRestoreTimerRef.current = null;
    }
  }, []);

  const getSearchText = getSearchTextProp ?? getLabel;

  const prepared = React.useMemo(() => {
    const byId = new Map<string, T>();
    const parentById = new Map<string, string | null>();
    const childrenByParent = new Map<string | null, string[]>();

    for (const item of items) {
      const idStr = idKey(getId(item));
      byId.set(idStr, item);
      const parentIdRaw = getParentId(item);
      const parentIdStr = parentIdRaw === null ? null : idKey(parentIdRaw);
      parentById.set(idStr, parentIdStr);
      const children = childrenByParent.get(parentIdStr) ?? [];
      children.push(idStr);
      childrenByParent.set(parentIdStr, children);
    }

    const levelCache = new Map<string, number>();
    const computeLevel = (startId: string): number => {
      const cached = levelCache.get(startId);
      if (cached !== undefined) return cached;
      const path: string[] = [];
      const seen = new Set<string>();
      let currentId: string | null = startId;
      while (currentId !== null && !seen.has(currentId)) {
        const existing = levelCache.get(currentId);
        if (existing !== undefined) {
          let depth = existing;
          for (let i = path.length - 1; i >= 0; i -= 1) {
            depth += 1;
            levelCache.set(path[i], depth);
          }
          return levelCache.get(startId) ?? 0;
        }
        seen.add(currentId);
        path.push(currentId);
        currentId = parentById.get(currentId) ?? null;
      }
      let depth = 0;
      for (let i = path.length - 1; i >= 0; i -= 1) {
        levelCache.set(path[i], depth);
        depth += 1;
      }
      return levelCache.get(startId) ?? 0;
    };

    const sortKeyFn = getSortKey ?? ((item: T) => idKey(getId(item)));
    const preparedItems: PreparedItem<T>[] = items.map((item) => {
      const idStr = idKey(getId(item));
      return {
        item,
        idStr,
        parentIdStr: parentById.get(idStr) ?? null,
        searchTextLower: getSearchText(item).toLowerCase(),
        sortKey: sortKeyFn(item),
        level: computeLevel(idStr),
      };
    });

    preparedItems.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
    return { byId, parentById, childrenByParent, items: preparedItems };
  }, [getId, getParentId, getSearchText, getSortKey, items]);

  const selectedItem = React.useMemo(() => {
    if (value === null || value === undefined) return undefined;
    return prepared.byId.get(idKey(value));
  }, [prepared.byId, value]);

  const { rows, truncated } = React.useMemo(() => {
    const queryLower = filterQuery.trim().toLowerCase();

    if (!queryLower) {
      const list = prepared.items.slice(0, maxResults).map((entry) => ({
        item: entry.item,
        idStr: entry.idStr,
        level: entry.level,
        contextOnly: false,
      }));
      return {
        rows: list,
        truncated: prepared.items.length > maxResults,
      };
    }

    const included = new Set<string>();
    const matched = new Set<string>();
    const descendantIncluded = new Set<string>();

    const includeAncestors = (startId: string) => {
      let currentId: string | null = startId;
      const seen = new Set<string>();
      while (currentId !== null) {
        if (seen.has(currentId)) break;
        seen.add(currentId);
        included.add(currentId);
        currentId = prepared.parentById.get(currentId) ?? null;
      }
    };

    const includeDescendants = (startId: string) => {
      const queue = [...(prepared.childrenByParent.get(startId) ?? [])];
      const seen = new Set<string>();
      while (queue.length > 0) {
        const id = queue.shift()!;
        if (seen.has(id)) continue;
        seen.add(id);
        included.add(id);
        descendantIncluded.add(id);
        const next = prepared.childrenByParent.get(id) ?? [];
        queue.push(...next);
      }
    };

    for (const entry of prepared.items) {
      if (!entry.searchTextLower.includes(queryLower)) continue;
      matched.add(entry.idStr);
      included.add(entry.idStr);
      includeAncestors(entry.idStr);
      if (includeChildren) includeDescendants(entry.idStr);
    }

    const list: RowModel<T>[] = [];
    for (const entry of prepared.items) {
      if (!included.has(entry.idStr)) continue;
      list.push({
        item: entry.item,
        idStr: entry.idStr,
        level: entry.level,
        contextOnly: !matched.has(entry.idStr) && !descendantIncluded.has(entry.idStr),
      });
      if (list.length >= maxResults) break;
    }

    return {
      rows: list,
      truncated: included.size > maxResults,
    };
  }, [
    includeChildren,
    maxResults,
    prepared,
    filterQuery,
  ]);

  React.useEffect(() => {
    if (alwaysOpen) return;
    if (!open) {
      if (!isInputControlled) setQuery('');
      setFilterQuery('');
    }
  }, [alwaysOpen, isInputControlled, open]);

  /** Keep search text aligned with `value` when it changes externally (not while the user is typing). */
  React.useEffect(() => {
    if (!alwaysOpen) return;
    if (prevValueRef.current !== value) {
      prevValueRef.current = value;
      if (selectedItem) {
        const label = (getInputLabel ?? getLabel)(selectedItem);
        if (isInputControlled) {
          onInputValueChange?.(label);
        } else {
          setQuery(label);
        }
        setFilterQuery('');
      } else {
        if (!isInputControlled) {
          setQuery('');
        }
        setFilterQuery('');
      }
    }
  }, [
    alwaysOpen,
    getInputLabel,
    getLabel,
    isInputControlled,
    onInputValueChange,
    selectedItem,
    value,
  ]);

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
      const label = (getInputLabel ?? getLabel)(item);
      if (isInputControlled) {
        onInputValueChange?.(label);
      } else {
        setQuery(label);
      }
      setFilterQuery('');
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
      getInputLabel,
      getLabel,
      isInputControlled,
      onAfterSelect,
      onChange,
      onInputValueChange,
    ]
  );

  const handleQueryChange = React.useCallback(
    (next: string) => {
      cancelBlurRestoreTimer();
      if (isInputControlled) {
        onInputValueChange?.(next);
      } else {
        setQuery(next);
      }
      setFilterQuery(next);
      if (alwaysOpen && listCollapsed) {
        setListCollapsed(false);
      }
    },
    [alwaysOpen, cancelBlurRestoreTimer, isInputControlled, listCollapsed, onInputValueChange]
  );

  const handleSearchBlur = React.useCallback(() => {
    if (!alwaysOpen) return;

    // Let list item click/select finish without pre-emptive collapse.
    if (pointerDownOnListRef.current) {
      pointerDownOnListRef.current = false;
      return;
    }

    if (collapseOnSelect) {
      setListCollapsed(true);
    }

    if (!clearSearchOnFocus) return;
    cancelBlurRestoreTimer();
    blurRestoreTimerRef.current = setTimeout(() => {
      blurRestoreTimerRef.current = null;
      if (isInputControlled) {
        if (currentInputValue.trim() === '' && selectedItem) {
          onInputValueChange?.((getInputLabel ?? getLabel)(selectedItem));
        }
      } else {
        setQuery((q) => {
          if (q.trim() !== '') return q;
          if (selectedItem) return (getInputLabel ?? getLabel)(selectedItem);
          return q;
        });
      }
      setFilterQuery('');
    }, 150);
  }, [
    alwaysOpen,
    cancelBlurRestoreTimer,
    clearSearchOnFocus,
    collapseOnSelect,
    getInputLabel,
    getLabel,
    currentInputValue,
    isInputControlled,
    onInputValueChange,
    selectedItem,
  ]);

  const handleSearchFocus = React.useCallback(() => {
    cancelBlurRestoreTimer();
    if (alwaysOpen && clearSearchOnFocus) {
      if (currentInputValue !== '') {
        requestAnimationFrame(() => {
          if (isInputControlled) {
            onInputValueChange?.('');
          } else {
            setQuery('');
          }
          setFilterQuery('');
        });
      }
      return;
    }
    if (alwaysOpen && !collapseOnSelect && listCollapsed) {
      setListCollapsed(false);
    }
  }, [
    alwaysOpen,
    cancelBlurRestoreTimer,
    clearSearchOnFocus,
    collapseOnSelect,
    currentInputValue,
    isInputControlled,
    listCollapsed,
    onInputValueChange,
  ]);

  const handleAlwaysOpenKeyDown = React.useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      if (!alwaysOpen) return;

      if (event.key === 'Escape') {
        event.preventDefault();
        if (isInputControlled) {
          onInputValueChange?.('');
        } else {
          setQuery('');
        }
        setFilterQuery('');
        setListCollapsed(true);
        return;
      }

      if (event.key === 'Enter' && rows.length === 0) {
        event.preventDefault();
        onInputCommit?.(currentInputValue);
        return;
      }

      if (event.key === 'ArrowDown' && listCollapsed) {
        event.preventDefault();
        setListCollapsed(false);
        return;
      }

      if (event.key === 'ArrowUp' && !listCollapsed) {
        const selected = listRef.current?.querySelector('[cmdk-item][data-selected="true"]');
        const first = listRef.current?.querySelector('[cmdk-item]:not([aria-disabled="true"])');
        if (!selected || selected === first) {
          event.preventDefault();
          setListCollapsed(true);
        }
      }
    },
    [alwaysOpen, currentInputValue, isInputControlled, listCollapsed, onInputCommit, onInputValueChange, rows.length],
  );

  const handleAlwaysOpenToggle = React.useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      event.preventDefault();
      event.stopPropagation();
      cancelBlurRestoreTimer();
      if (!isInputControlled) {
        setQuery('');
        setFilterQuery('');
      }
      setListCollapsed((current) => !current);
      requestAnimationFrame(() => searchInputRef.current?.focus());
    },
    [cancelBlurRestoreTimer, isInputControlled, onInputValueChange],
  );

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
      <CommandGroup className="p-0 [&_[cmdk-group-items]]:space-y-0">
        {rows.map(({ item, idStr, level, contextOnly }) => {
          const selected = value !== null && idKey(value) === idStr;
          const rowDisabled = rowIsDisabled(contextOnly);
          const label = getLabel(item);
          const display = highlightMatches(label, currentInputValue.trim().toLowerCase());

          return (
            <CommandItem
              key={idStr}
              value={idStr}
              disabled={rowDisabled}
              onSelect={() => {
                if (rowDisabled) return;
                commitSelection(item);
              }}
              className="my-0 h-5 min-h-0 cursor-pointer py-0 text-xs leading-none data-[disabled=true]:cursor-not-allowed"
            >
              <Check
                className={cn(
                  'mr-2 h-3 w-3 shrink-0',
                  selected ? 'opacity-100' : 'opacity-0'
                )}
              />
              <span
                className="min-w-0 flex-1 truncate font-mono text-xs leading-none"
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
            <div className="flex h-9 shrink-0 items-center gap-1 px-1 [&_[cmdk-input-wrapper]]:h-full [&_[cmdk-input-wrapper]]:min-h-0 [&_[cmdk-input-wrapper]]:flex-1 [&_[cmdk-input-wrapper]]:items-center [&_[cmdk-input-wrapper]]:border-0 [&_[cmdk-input-wrapper]]:px-2 [&_[cmdk-input-wrapper]]:py-0">
              <CommandInput
                ref={searchInputRef}
                id={triggerId}
                placeholder={placeholder}
                value={currentInputValue}
                onValueChange={handleQueryChange}
                onFocus={handleSearchFocus}
                onBlur={handleSearchBlur}
                onKeyDown={handleAlwaysOpenKeyDown}
                disabled={loading || disabled}
                className="h-9 min-h-0 border-0 py-0 text-sm leading-none shadow-none focus-visible:ring-0"
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
                    if (isInputControlled) {
                      onInputValueChange?.('');
                    } else {
                      setQuery('');
                    }
                    setFilterQuery('');
                    setListCollapsed(true);
                    requestAnimationFrame(() => searchInputRef.current?.focus());
                  }}
                  aria-label="Clear selection"
                >
                  <X className="h-4 w-4 opacity-60" />
                </Button>
              ) : null}
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="h-9 w-9 shrink-0 self-center"
                disabled={disabled || loading}
                onMouseDown={(event) => event.preventDefault()}
                onClick={handleAlwaysOpenToggle}
                aria-label={listCollapsed ? 'Show options' : 'Hide options'}
                aria-expanded={!listCollapsed}
              >
                <ChevronDown
                  className={cn(
                    'h-4 w-4 opacity-60 transition-transform',
                    !listCollapsed && 'rotate-180',
                  )}
                />
              </Button>
            </div>
            {/* Always mount CommandList: cmdk keeps listInnerRef on it — unmounting caused Array.from(null) in cmdk. */}
            <CommandList
              ref={listRef}
              hidden={listCollapsed}
              onMouseDown={() => {
                pointerDownOnListRef.current = true;
              }}
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
            ref={triggerRef}
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
            value={currentInputValue}
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
