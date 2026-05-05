# Cursor UI Design Guidelines

Purpose: define the current application look-and-feel so future pages/components match existing behavior and styling.

Scope source: existing implementation in `website/app` and `website/components` (layout shells, header/sidebar, customer management page, table/list components, and shared UI primitives).

---

## 1) Layout and Structure

- Global app shell uses:
  - top header (`DashboardHeader`) with utility actions
  - left navigation sidebar (`TenantSidebar` or `CustomerSidebar`)
  - scrollable content area (`main`)
- Route page files should stay thin and pass normalized data into feature components.
- Primary shell patterns:
  - `TenantLayoutShell`: `h-screen`, sidebar + header + scrollable content
  - `CustomerLayoutShell`: header on top, sidebar + scrollable content below
- Content areas are scroll containers (`overflow-y-auto`) and use background token `bg-background`.
- Main page composition follows sections/panels:
  - high-level page wrapper with vertical rhythm (`space-y-*`)
  - cards as bounded sections (`Card`, `CardContent`)
  - form regions organized into grids (e.g., `sm:grid-cols-2`)

---

## 2) Component Usage Rules

Use existing components first; avoid creating parallel variants unless required by a new capability.

### Header and Navigation

- Use `DashboardHeader` for authenticated dashboard surfaces.
- Use `TenantSidebar` for account routes (`/account/*`) and `CustomerSidebar` for customer routes (`/customer/*`).
- Keep mobile behavior consistent:
  - sidebar hidden on small screens
  - header menu button opens sidebar overlay

### Cards and Panels

- Use `Card` as the default container for bounded functional regions.
- Use `CardContent` for interior layout and spacing.
- Keep card borders muted (`border-border/60` common pattern).

### Forms

- Use existing primitives:
  - `Label` + `Input`
  - `Select`, `SelectTrigger`, `SelectContent`, `SelectItem`
  - `Checkbox`
  - `Button`
- For hierarchical customer selection, use `EntityComboBox` with:
  - `getParentId` for tree structure
  - `getSortKey` for deterministic ordering
  - keyboard-friendly behavior (`alwaysOpen`, `collapseOnSelect`, etc.) where appropriate

### Tables and Lists

- Use shared table primitives (`Table`, `TableHeader`, `TableRow`, etc.).
- Existing data tables (`OrdersTable`, `CustomersTable`) should be treated as style references:
  - rounded bordered wrapper
  - muted table header row
  - hover state on rows
  - badges for status semantics

### Buttons

- Use standard variants only: `default`, `outline`, `secondary`, `ghost`, `destructive`, `link`.
- Use `size="sm"` for inline actions in dense forms/toolbars.
- Keep action grouping consistent (related actions aligned together).

---

## 3) Typography

- Base body font: `Inter` (configured in `globals.css`).
- Brand accents/logotype in header/sidebar use serif style (Playfair/serif).
- Typical hierarchy in current app:
  - page-level/section titles: `text-base` to `text-xl` depending context
  - card/form titles: commonly `text-base font-semibold tracking-tight`
  - labels: default label styles with compact vertical spacing (`space-y-1.5`)
  - body and control text: mostly `text-sm`
  - helper/meta text: `text-xs` / `text-[10px]` with `text-muted-foreground`
- Keep hierarchy subtle and information-dense; avoid oversized headings in dashboard surfaces.

---

## 4) Spacing and Layout Rules

- Page-level vertical rhythm commonly `space-y-6`.
- Common grid/flex spacing:
  - section grids: `gap-3`, `gap-4`, or `gap-6`
  - form control stacks: `space-y-1.5`
  - compact nested lists in sidebars: `space-y-0.5` to `space-y-1`
- Content area padding is context-specific and should follow shell:
  - dashboard content uses shell-defined horizontal/vertical padding
  - card interiors typically `p-4` for dense controls or `p-6` for standard sections
- Preserve consistent alignment:
  - labels above inputs
  - action buttons aligned at row end when in toolbars
  - avoid arbitrary one-off spacing utilities when an existing pattern fits

---

## 5) Forms and Interaction Patterns

- Label-first inputs: place `Label` directly above each control.
- Placeholders are supportive only; they do not replace labels.
- Validation behavior:
  - required fields checked before save
  - show inline page status message for failures/success where current page does so
- Save/create action pattern (as implemented):
  - primary `Save` action near top-right of work area
  - secondary create/reset action adjacent (`outline` style)
- Customer management behavior pattern:
  - tenant selection gates customer data loading
  - selecting customer loads full record before form fill
  - save refreshes list and reselects saved record when possible

---

## 6) Tables and Data Display

- Table wrappers: rounded border container (`rounded-xl border border-border/60 overflow-hidden`).
- Header row style:
  - muted background (`bg-muted/40`)
  - compact, semibold header text (`text-xs font-semibold text-muted-foreground`)
- Row style:
  - subtle separators and hover state
  - pointer cursor when row is actionable
- Numeric values:
  - use tabular alignment style where applicable (`tabular-nums`)
  - right-align totals/amounts
- Lists vs tables:
  - use tables for multi-column record comparison
  - use hierarchical list/combobox for parent-child entity navigation

---

## 7) Navigation

- Sidebar-first navigation for authenticated app sections.
- Breadcrumbs are rendered in `DashboardHeader` as compact, muted metadata.
- No global breadcrumb component beyond header pattern currently.
- Mobile navigation:
  - overlay backdrop + slide-in sidebar
  - close on backdrop tap or close control
- Keep route group behavior unchanged:
  - marketing/public navbar hidden for `/account/*` and `/customer/*`

---

## 8) State and Feedback

- Loading:
  - disable controls while request in progress (`isSaving`, `isLoadingCustomers`)
  - show loading labels in buttons where applicable (e.g., `Saving...`)
- Empty states:
  - explicit empty text in selectors/lists (`No customers found.`, `Select a tenant first.`)
- Error states:
  - surface server/RPC errors in user-visible status message region
- Success states:
  - confirm save with status message (`Saved successfully.` or server message)
- Session/auth state:
  - layout shells block rendering until auth is checked
  - redirect unauthenticated users to `/login`

---

## 9) Styling Rules

- Use existing design tokens from `globals.css`:
  - semantic colors: `background`, `foreground`, `card`, `muted`, `primary`, `border`, etc.
  - radius token maps to standard rounded components
- Keep card styling consistent:
  - `rounded-lg`/`rounded-xl`, light border, subtle elevation (`shadow-sm` where inherited)
- Use muted surfaces for secondary structure:
  - table headers, inactive text, separators
- Use primary color for active emphasis only:
  - active nav items
  - selected states
  - primary actions
- Do not introduce new visual paradigms (new color systems, shadows, spacing scales) without explicit alignment.

---

## 10) Do / Don't

### Do

- Reuse `DashboardHeader`, sidebars, `Card`, table primitives, and form primitives.
- Follow existing spacing rhythm (`space-y-*`, `gap-*`, compact label/control stacks).
- Keep pages thin and feature components responsible for interaction logic.
- Keep SQL/RPC-backed flows explicit and user-feedback aware.

### Don't

- Do not introduce alternate layout shells when `TenantLayoutShell` / `CustomerLayoutShell` fit.
- Do not create ad-hoc component variants that duplicate existing primitives.
- Do not break established auth/session UX (silent null render until auth check, redirect on sign-out).
- Do not deviate from token-based styling with hardcoded one-off colors unless required by an existing pattern.

---

## Implementation Note for Cursor

When generating new UI, match these patterns exactly before proposing new abstractions. Prefer extending existing components over introducing new ones.
