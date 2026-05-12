'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { formatDistanceToNow } from 'date-fns';
import { Pin, Star, Lock, Globe, Pencil, Trash2 } from 'lucide-react';
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

const EMPTY_FORM: NoteForm = {
  note_id:      null,
  note_title:   '',
  note_text:    '',
  is_important: false,
  is_pinned:    false,
  visibility:   'tenant_only',
};

interface ItemNotesTabProps {
  tenantId: number;
  itemId: number | null;
}

function initials(name: string): string {
  return name.split(/\s+/).filter(Boolean).map((w) => w[0]).join('').toUpperCase().slice(0, 2) || '?';
}

function AutoTextarea({
  value,
  onChange,
  placeholder,
  className,
  autoFocus,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  className?: string;
  autoFocus?: boolean;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (ref.current) {
      ref.current.style.height = 'auto';
      ref.current.style.height = `${ref.current.scrollHeight}px`;
    }
  }, [value]);

  return (
    <textarea
      ref={ref}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      autoFocus={autoFocus}
      rows={3}
      className={cn(
        'w-full resize-none overflow-hidden rounded-md border border-input bg-transparent px-3 py-2 text-sm',
        'placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring',
        'transition-shadow',
        className,
      )}
    />
  );
}

function ToggleIconBtn({
  active,
  onClick,
  activeClass,
  title,
  children,
}: {
  active: boolean;
  onClick: () => void;
  activeClass: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={title}
      className={cn(
        'flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium transition-colors',
        active ? activeClass : 'text-muted-foreground hover:bg-muted hover:text-foreground',
      )}
    >
      {children}
    </button>
  );
}

function NoteFormPanel({
  form,
  setForm,
  onSave,
  onCancel,
  isSaving,
  saveLabel = 'Add Note',
}: {
  form: NoteForm;
  setForm: (f: NoteForm) => void;
  onSave: () => void;
  onCancel?: () => void;
  isSaving: boolean;
  saveLabel?: string;
}) {
  const set = <K extends keyof NoteForm>(k: K, v: NoteForm[K]) =>
    setForm({ ...form, [k]: v });

  return (
    <div className="space-y-2 rounded-xl border border-border/70 bg-card p-4 shadow-sm">
      <Input
        placeholder="Title (optional)"
        value={form.note_title}
        onChange={(e) => set('note_title', e.target.value)}
        className="h-8 border-0 border-b border-border/40 rounded-none bg-transparent px-0 text-sm font-medium shadow-none focus-visible:ring-0 focus-visible:border-primary"
      />
      <AutoTextarea
        value={form.note_text}
        onChange={(v) => set('note_text', v)}
        placeholder="Write a note…"
        autoFocus
      />
      <div className="flex items-center gap-1 pt-1">
        {/* Visibility */}
        <ToggleIconBtn
          active={form.visibility === 'shared'}
          onClick={() => set('visibility', form.visibility === 'shared' ? 'tenant_only' : 'shared')}
          activeClass="bg-green-50 text-green-700 dark:bg-green-950/40 dark:text-green-400"
          title={form.visibility === 'shared' ? 'Shared with customer — click to make internal' : 'Internal only — click to share with customer'}
        >
          {form.visibility === 'shared'
            ? <><Globe className="h-3.5 w-3.5" /> Shared</>
            : <><Lock className="h-3.5 w-3.5" /> Internal</>
          }
        </ToggleIconBtn>

        {/* Important */}
        <ToggleIconBtn
          active={form.is_important}
          onClick={() => set('is_important', !form.is_important)}
          activeClass="bg-amber-50 text-amber-600 dark:bg-amber-950/40 dark:text-amber-400"
          title="Mark as important"
        >
          <Star className="h-3.5 w-3.5" fill={form.is_important ? 'currentColor' : 'none'} />
          Important
        </ToggleIconBtn>

        {/* Pin */}
        <ToggleIconBtn
          active={form.is_pinned}
          onClick={() => set('is_pinned', !form.is_pinned)}
          activeClass="bg-sky-50 text-sky-600 dark:bg-sky-950/40 dark:text-sky-400"
          title="Pin to top"
        >
          <Pin className="h-3.5 w-3.5" fill={form.is_pinned ? 'currentColor' : 'none'} />
          Pin
        </ToggleIconBtn>

        <div className="flex-1" />

        {onCancel && (
          <Button type="button" variant="ghost" size="sm" onClick={onCancel} disabled={isSaving}>
            Cancel
          </Button>
        )}
        <Button
          type="button"
          size="sm"
          onClick={onSave}
          disabled={isSaving || form.note_text.trim() === ''}
        >
          {isSaving ? 'Saving…' : saveLabel}
        </Button>
      </div>
    </div>
  );
}

function NoteCard({
  note,
  onEdit,
  onDelete,
  onTogglePin,
}: {
  note: Note;
  onEdit: () => void;
  onDelete: () => void;
  onTogglePin: () => void;
}) {
  return (
    <div
      className={cn(
        'group relative rounded-xl border bg-card p-4 shadow-sm transition-shadow hover:shadow-md',
        note.is_important
          ? 'border-l-[3px] border-l-amber-400'
          : note.is_pinned
            ? 'border-l-[3px] border-l-sky-400'
            : '',
      )}
    >
      {/* Hover actions */}
      <div className="absolute right-3 top-3 flex items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
        <button
          type="button"
          onClick={onTogglePin}
          title={note.is_pinned ? 'Unpin' : 'Pin to top'}
          className={cn(
            'rounded-md p-1.5 transition-colors',
            note.is_pinned
              ? 'text-sky-500 hover:bg-sky-50 dark:hover:bg-sky-950/30'
              : 'text-muted-foreground/40 hover:bg-muted hover:text-sky-500',
          )}
        >
          <Pin className="h-3.5 w-3.5" fill={note.is_pinned ? 'currentColor' : 'none'} />
        </button>
        <button
          type="button"
          onClick={onEdit}
          title="Edit note"
          className="rounded-md p-1.5 text-muted-foreground/40 transition-colors hover:bg-muted hover:text-foreground"
        >
          <Pencil className="h-3.5 w-3.5" />
        </button>
        <button
          type="button"
          onClick={onDelete}
          title="Delete note"
          className="rounded-md p-1.5 text-muted-foreground/40 transition-colors hover:bg-destructive/10 hover:text-destructive"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>

      {/* Content */}
      {note.note_title && (
        <p className="mb-1 pr-20 text-sm font-semibold">{note.note_title}</p>
      )}
      <p className="whitespace-pre-wrap pr-20 text-sm text-foreground/80 leading-relaxed">
        {note.note_text}
      </p>

      {/* Footer */}
      <div className="mt-3 flex items-center gap-2 text-xs text-muted-foreground">
        <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-muted text-[10px] font-semibold">
          {initials(note.author_name)}
        </span>
        <span className="truncate">{note.author_name}</span>
        <span>·</span>
        <span
          className="shrink-0"
          title={new Date(note.created_at).toLocaleString()}
        >
          {formatDistanceToNow(new Date(note.created_at), { addSuffix: true })}
        </span>
        <span>·</span>
        {note.visibility === 'shared' ? (
          <span className="flex shrink-0 items-center gap-0.5 text-green-600 dark:text-green-400">
            <Globe className="h-3 w-3" />
            Shared
          </span>
        ) : (
          <span className="flex shrink-0 items-center gap-0.5">
            <Lock className="h-3 w-3" />
            Internal
          </span>
        )}
        {note.is_important && (
          <>
            <span>·</span>
            <span className="flex shrink-0 items-center gap-0.5 text-amber-500">
              <Star className="h-3 w-3" fill="currentColor" />
              Important
            </span>
          </>
        )}
      </div>
    </div>
  );
}

export function ItemNotesTab({ tenantId, itemId }: ItemNotesTabProps) {
  const [notes, setNotes]           = useState<Note[]>([]);
  const [isLoading, setIsLoading]   = useState(false);
  const [composeForm, setComposeForm] = useState<NoteForm>(EMPTY_FORM);
  const [isAdding, setIsAdding]     = useState(false);
  const [editingId, setEditingId]   = useState<number | null>(null);
  const [editForm, setEditForm]     = useState<NoteForm>(EMPTY_FORM);
  const [isSavingEdit, setIsSavingEdit] = useState(false);
  const loadedItemId = useRef<number | null | undefined>(undefined);

  const load = useCallback(async () => {
    if (!itemId) return;
    setIsLoading(true);
    try {
      const res  = await fetch(`/api/items/notes?tenant_id=${tenantId}&item_id=${itemId}`);
      const json = await res.json() as { data?: Note[]; error?: string };
      if (!res.ok || json.error) {
        toast.error(json.error ?? 'Could not load notes.', { duration: Infinity });
        return;
      }
      setNotes(json.data ?? []);
      loadedItemId.current = itemId;
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, itemId]);

  useEffect(() => {
    if (itemId !== loadedItemId.current) {
      setNotes([]);
      setEditingId(null);
      setComposeForm(EMPTY_FORM);
      void load();
    }
  }, [itemId, load]);

  const addNote = async () => {
    if (!itemId || composeForm.note_text.trim() === '') return;
    setIsAdding(true);
    try {
      const res  = await fetch('/api/items/notes', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({
          tenant_id: tenantId,
          entry: { ...composeForm, entity_id: itemId, source_table: 'fnd_items' },
        }),
      });
      const json = await res.json() as { data?: unknown; error?: string };
      if (!res.ok || json.error) {
        toast.error(json.error ?? 'Could not save note.', { duration: Infinity });
        return;
      }
      setComposeForm(EMPTY_FORM);
      await load();
    } finally {
      setIsAdding(false);
    }
  };

  const saveEdit = async () => {
    if (editForm.note_text.trim() === '') return;
    setIsSavingEdit(true);
    try {
      const res  = await fetch('/api/items/notes', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({
          tenant_id: tenantId,
          entry: { ...editForm, entity_id: itemId, source_table: 'fnd_items' },
        }),
      });
      const json = await res.json() as { data?: unknown; error?: string };
      if (!res.ok || json.error) {
        toast.error(json.error ?? 'Could not save note.', { duration: Infinity });
        return;
      }
      setEditingId(null);
      await load();
    } finally {
      setIsSavingEdit(false);
    }
  };

  const deleteNote = async (noteId: number) => {
    const res  = await fetch(`/api/items/notes?tenant_id=${tenantId}&note_id=${noteId}`, {
      method: 'DELETE',
    });
    const json = await res.json() as { data?: unknown; error?: string };
    if (!res.ok || json.error) {
      toast.error(json.error ?? 'Could not delete note.', { duration: Infinity });
      return;
    }
    setNotes((prev) => prev.filter((n) => n.note_id !== noteId));
  };

  const togglePin = async (note: Note) => {
    const res  = await fetch('/api/items/notes', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({
        tenant_id: tenantId,
        entry: {
          note_id:      note.note_id,
          entity_id:    itemId,
          source_table: 'fnd_items',
          note_title:   note.note_title ?? '',
          note_text:    note.note_text,
          is_important: note.is_important,
          is_pinned:    !note.is_pinned,
          visibility:   note.visibility,
        },
      }),
    });
    const json = await res.json() as { data?: unknown; error?: string };
    if (!res.ok || json.error) {
      toast.error(json.error ?? 'Could not update note.', { duration: Infinity });
      return;
    }
    await load();
  };

  const startEdit = (note: Note) => {
    setEditingId(note.note_id);
    setEditForm({
      note_id:      note.note_id,
      note_title:   note.note_title ?? '',
      note_text:    note.note_text,
      is_important: note.is_important,
      is_pinned:    note.is_pinned,
      visibility:   note.visibility,
    });
  };

  if (!itemId) {
    return <p className="py-4 text-sm text-muted-foreground">Select an item to view notes.</p>;
  }

  return (
    <div className="space-y-4">
      {/* Compose */}
      <NoteFormPanel
        form={composeForm}
        setForm={setComposeForm}
        onSave={addNote}
        isSaving={isAdding}
        saveLabel="Add Note"
      />

      {/* Feed */}
      {isLoading ? (
        <p className="py-4 text-center text-sm text-muted-foreground">Loading…</p>
      ) : notes.length === 0 ? (
        <p className="py-8 text-center text-sm text-muted-foreground">No notes yet.</p>
      ) : (
        <div className="space-y-3">
          {notes.map((note) =>
            editingId === note.note_id ? (
              <NoteFormPanel
                key={note.note_id}
                form={editForm}
                setForm={setEditForm}
                onSave={saveEdit}
                onCancel={() => setEditingId(null)}
                isSaving={isSavingEdit}
                saveLabel="Save"
              />
            ) : (
              <NoteCard
                key={note.note_id}
                note={note}
                onEdit={() => startEdit(note)}
                onDelete={() => void deleteNote(note.note_id)}
                onTogglePin={() => void togglePin(note)}
              />
            ),
          )}
        </div>
      )}
    </div>
  );
}
