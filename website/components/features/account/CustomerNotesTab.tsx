'use client';

import { useState, useEffect, useCallback, useRef, forwardRef, useImperativeHandle } from 'react';
import { format } from 'date-fns';
import { Pin, Star, Lock, Globe, Trash2, Plus } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

interface Note {
  note_id: number;
  note_title: string | null;
  note_text: string;
  is_important: boolean;
  is_pinned: boolean;
  visibility: 'tenant_only' | 'shared';
  created_at: string;
  updated_at: string;
  author_name: string;
}

interface NoteForm {
  note_id: number | null;
  note_title: string;
  note_text: string;
  is_important: boolean;
  is_pinned: boolean;
  visibility: 'tenant_only' | 'shared';
}

export interface CustomerNotesTabHandle {
  save: () => Promise<void>;
  cancel: () => void;
}

interface CustomerNotesTabProps {
  tenantId: number;
  customerId: number | null;
  onDirtyChange: (dirty: boolean) => void;
}

const EMPTY_FORM: NoteForm = {
  note_id:      null,
  note_title:   '',
  note_text:    '',
  is_important: false,
  is_pinned:    false,
  visibility:   'tenant_only',
};

function noteToForm(note: Note): NoteForm {
  return {
    note_id:      note.note_id,
    note_title:   note.note_title ?? '',
    note_text:    note.note_text,
    is_important: note.is_important,
    is_pinned:    note.is_pinned,
    visibility:   note.visibility,
  };
}

function sortNotes(notes: Note[]): Note[] {
  return [...notes].sort((a, b) => {
    if (a.is_pinned !== b.is_pinned) return a.is_pinned ? -1 : 1;
    if (a.is_important !== b.is_important) return a.is_important ? -1 : 1;
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
  });
}

const thisYear = new Date().getFullYear();

function noteDate(iso: string) {
  const d = new Date(iso);
  return d.getFullYear() === thisYear ? format(d, 'MMM d') : format(d, 'MMM d, yyyy');
}

function ToggleBtn({
  active, onClick, activeClass, children,
}: {
  active: boolean;
  onClick: () => void;
  activeClass: string;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium transition-colors',
        active ? activeClass : 'text-muted-foreground hover:bg-muted hover:text-foreground',
      )}
    >
      {children}
    </button>
  );
}

const MIN_PANEL_WIDTH = 140;
const MAX_PANEL_WIDTH = 400;
const DEFAULT_PANEL_WIDTH = 208;

export const CustomerNotesTab = forwardRef<CustomerNotesTabHandle, CustomerNotesTabProps>(
  function CustomerNotesTab({ tenantId, customerId, onDirtyChange }, ref) {
    const [notes, setNotes]           = useState<Note[]>([]);
    const [isLoading, setIsLoading]   = useState(false);
    const [selection, setSelection]   = useState<number | 'new' | null>(null);
    const [form, setForm]             = useState<NoteForm>(EMPTY_FORM);
    const [isSaving, setIsSaving]     = useState(false);
    const [panelWidth, setPanelWidth] = useState(DEFAULT_PANEL_WIDTH);
    const savedFormRef                = useRef<NoteForm>(EMPTY_FORM);
    const loadedCustomerId            = useRef<number | null | undefined>(undefined);
    const titleInputRef               = useRef<HTMLInputElement>(null);
    const dragRef                     = useRef<{ startX: number; startWidth: number } | null>(null);
    const notesRef                    = useRef<Note[]>([]);

    const isDirty = JSON.stringify(form) !== JSON.stringify(savedFormRef.current);

    useEffect(() => { notesRef.current = notes; }, [notes]);
    useEffect(() => { onDirtyChange(isDirty); }, [isDirty, onDirtyChange]);

    const applySelection = (note: Note) => {
      const f = noteToForm(note);
      setSelection(note.note_id);
      setForm(f);
      savedFormRef.current = f;
    };

    const applyNew = () => {
      setSelection('new');
      setForm(EMPTY_FORM);
      savedFormRef.current = EMPTY_FORM;
      setTimeout(() => titleInputRef.current?.focus(), 50);
    };

    const load = useCallback(async (): Promise<Note[]> => {
      if (!customerId) return [];
      setIsLoading(true);
      try {
        const res  = await fetch(`/api/customers/notes?tenant_id=${tenantId}&customer_id=${customerId}`);
        const json = await res.json() as { data?: Note[]; error?: string };
        if (!res.ok || json.error) {
          toast.error(json.error ?? 'Could not load notes.', { duration: Infinity });
          return [];
        }
        const loaded = json.data ?? [];
        setNotes(loaded);
        loadedCustomerId.current = customerId;
        return loaded;
      } finally {
        setIsLoading(false);
      }
    }, [tenantId, customerId]);

    useEffect(() => {
      if (customerId !== loadedCustomerId.current) {
        setNotes([]);
        setSelection(null);
        setForm(EMPTY_FORM);
        savedFormRef.current = EMPTY_FORM;
        load().then((loaded) => {
          const sorted = sortNotes(loaded);
          if (sorted.length > 0) applySelection(sorted[0]);
        });
      }
    }, [customerId, load]);

    const onDragStart = (e: React.MouseEvent) => {
      e.preventDefault();
      dragRef.current = { startX: e.clientX, startWidth: panelWidth };
      const onMove = (ev: MouseEvent) => {
        if (!dragRef.current) return;
        const delta    = ev.clientX - dragRef.current.startX;
        const newWidth = Math.min(MAX_PANEL_WIDTH, Math.max(MIN_PANEL_WIDTH, dragRef.current.startWidth + delta));
        setPanelWidth(newWidth);
      };
      const onUp = () => {
        dragRef.current = null;
        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onUp);
      };
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
    };

    const save = useCallback(async () => {
      if (!customerId || form.note_text.trim() === '') return;
      setIsSaving(true);
      try {
        const res  = await fetch('/api/customers/notes', {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({
            tenant_id: tenantId,
            entry: { ...form, entity_id: customerId, source_table: 'fnd_customers' },
          }),
        });
        const json = await res.json() as { data?: { note_id?: number }; error?: string };
        if (!res.ok || json.error) {
          toast.error(json.error ?? 'Could not save note.', { duration: Infinity });
          return;
        }
        const savedId = json.data?.note_id ?? form.note_id;
        const loaded  = await load();
        const saved   = loaded.find((n) => n.note_id === savedId);
        if (saved) applySelection(saved);
      } finally {
        setIsSaving(false);
      }
    }, [customerId, form, load, tenantId]);

    const cancel = useCallback(() => {
      const f = savedFormRef.current;
      setForm(f);
      if (f.note_id !== null) {
        const note = notesRef.current.find((n) => n.note_id === f.note_id);
        if (note) { setSelection(note.note_id); return; }
      }
      const sorted = sortNotes(notesRef.current);
      if (sorted.length > 0) applySelection(sorted[0]);
      else { setSelection(null); setForm(EMPTY_FORM); savedFormRef.current = EMPTY_FORM; }
    }, []);

    useImperativeHandle(ref, () => ({ save, cancel }), [save, cancel]);

    const deleteNote = async () => {
      if (!form.note_id || !customerId) return;
      const noteId = form.note_id;
      const res    = await fetch(`/api/customers/notes?tenant_id=${tenantId}&note_id=${noteId}`, { method: 'DELETE' });
      const json   = await res.json() as { error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not delete note.', { duration: Infinity }); return; }
      const remaining = sortNotes(notes.filter((n) => n.note_id !== noteId));
      setNotes(remaining);
      if (remaining.length > 0) applySelection(remaining[0]);
      else applyNew();
    };

    if (!customerId) {
      return <p className="py-4 text-sm text-muted-foreground">Select a customer to view notes.</p>;
    }

    const sorted   = sortNotes(notes);
    const setField = <K extends keyof NoteForm>(k: K, v: NoteForm[K]) =>
      setForm((f) => ({ ...f, [k]: v }));

    return (
      <div className="flex flex-col overflow-hidden rounded-lg border border-border/60" style={{ height: '520px' }}>

        {/* ── Tab header ──────────────────────────────────── */}
        <div className="flex flex-wrap shrink-0 items-center gap-2 border-b border-border/60 px-3 py-1.5">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={applyNew}
            className="h-7 gap-1 px-2 text-xs"
          >
            <Plus className="h-3.5 w-3.5" />
            Note
          </Button>
          <div className="flex-1" />
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={cancel}
            disabled={!isDirty}
            className="h-7"
          >
            Cancel
          </Button>
          <Button
            type="button"
            size="sm"
            onClick={save}
            disabled={isSaving || form.note_text.trim() === '' || !isDirty || selection === null}
            className="h-7"
          >
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
        </div>

        {/* ── Body: left list + drag handle + right editor ─ */}
        <div className="flex flex-1 overflow-hidden divide-x divide-border/60">

          {/* Left panel */}
          <div className="flex shrink-0 flex-col overflow-hidden" style={{ width: panelWidth }}>
            <div className="flex-1 overflow-y-auto">
              {isLoading ? (
                <p className="p-3 text-xs text-muted-foreground">Loading…</p>
              ) : (
                sorted.map((note) => {
                  const title = note.note_title || note.note_text.slice(0, 38) + (note.note_text.length > 38 ? '…' : '');
                  return (
                    <button
                      key={note.note_id}
                      type="button"
                      onClick={() => applySelection(note)}
                      className={cn(
                        'w-full border-b border-border/40 px-3 py-2.5 text-left transition-colors',
                        selection === note.note_id ? 'bg-muted' : 'hover:bg-muted/50',
                      )}
                    >
                      <div className="mb-0.5 flex items-start gap-1.5">
                        {note.is_pinned && (
                          <Pin className="mt-0.5 h-3 w-3 shrink-0 text-sky-500" fill="currentColor" />
                        )}
                        {note.is_important && !note.is_pinned && (
                          <Star className="mt-0.5 h-3 w-3 shrink-0 text-amber-500" fill="currentColor" />
                        )}
                        <span className={cn(
                          'line-clamp-2 text-sm leading-snug',
                          !note.note_title && 'italic text-foreground/60',
                        )}>
                          {title}
                        </span>
                      </div>
                      <p className="text-xs text-muted-foreground">{noteDate(note.created_at)}</p>
                    </button>
                  );
                })
              )}
            </div>
          </div>

          {/* Drag handle */}
          <div
            onMouseDown={onDragStart}
            className="w-1 shrink-0 cursor-col-resize bg-border/60 hover:bg-primary/30 transition-colors"
          />

          {/* Right panel */}
          {selection === null ? (
            <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
              Select a note or click + Note
            </div>
          ) : (
            <div className="flex flex-1 flex-col overflow-hidden">
              <div className="shrink-0 border-b border-border/40 px-4 pb-2 pt-4">
                <Input
                  ref={titleInputRef}
                  value={form.note_title}
                  onChange={(e) => setField('note_title', e.target.value)}
                  placeholder="Title"
                  className="h-8 border-0 bg-transparent px-0 text-base font-semibold shadow-none focus-visible:ring-0"
                />
                {typeof selection === 'number' && (() => {
                  const n = notes.find((x) => x.note_id === selection);
                  return n ? (
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {n.author_name} · {noteDate(n.created_at)}
                      {n.updated_at !== n.created_at && ' · edited'}
                    </p>
                  ) : null;
                })()}
              </div>

              <textarea
                value={form.note_text}
                onChange={(e) => setField('note_text', e.target.value)}
                placeholder="Write your note…"
                className="flex-1 resize-none bg-transparent px-4 py-3 text-sm placeholder:text-muted-foreground/50 focus:outline-none"
              />

              <div className="flex shrink-0 items-center gap-1 border-t border-border/40 px-4 py-2">
                <ToggleBtn
                  active={form.visibility === 'shared'}
                  onClick={() => setField('visibility', form.visibility === 'shared' ? 'tenant_only' : 'shared')}
                  activeClass="bg-green-50 text-green-700 dark:bg-green-950/40 dark:text-green-400"
                >
                  {form.visibility === 'shared'
                    ? <><Globe className="h-3.5 w-3.5" />Shared</>
                    : <><Lock className="h-3.5 w-3.5" />Internal</>}
                </ToggleBtn>
                <ToggleBtn
                  active={form.is_important}
                  onClick={() => setField('is_important', !form.is_important)}
                  activeClass="bg-amber-50 text-amber-600 dark:bg-amber-950/40 dark:text-amber-400"
                >
                  <Star className="h-3.5 w-3.5" fill={form.is_important ? 'currentColor' : 'none'} />
                  Important
                </ToggleBtn>
                <ToggleBtn
                  active={form.is_pinned}
                  onClick={() => setField('is_pinned', !form.is_pinned)}
                  activeClass="bg-sky-50 text-sky-600 dark:bg-sky-950/40 dark:text-sky-400"
                >
                  <Pin className="h-3.5 w-3.5" fill={form.is_pinned ? 'currentColor' : 'none'} />
                  Pin
                </ToggleBtn>
                <div className="flex-1" />
                {form.note_id && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={deleteNote}
                    className="h-7 px-2 text-destructive hover:bg-destructive/10 hover:text-destructive"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    );
  }
);
