# BPS UI/UX Guidelines

The living design standard for the BPS website (`website/`). Update this file whenever a design decision is approved, and add a line to the decision log at the end. Coding agents: the `bps-ui-design` skill (`.claude/skills/bps-ui-design/SKILL.md`) points here; read this file before changing any screen.

## 1. Philosophy and users

BPS is a data-heavy business application used all day by office staff, production teams, managers and owners. The goal is the polish of a modern SaaS product with the information density of professional desktop software.

- Modern does not mean large type, big cards, wide whitespace or extra scrolling.
- Every screen should show as much useful information as it can while staying easy to read.
- One coherent look across the whole application matters more than any single attractive screen.
- Existing business logic, calculations, permissions, database queries and workflows are never changed by design work.

## 2. The four layers and the two-phase rule

Every UI change belongs to one of four layers. Say which layer a change is in before making it.

| Layer | What it covers | Who may change it |
|---|---|---|
| 1. Theme and visual identity | Colors, semantic tokens, fonts, light/dark, theme switching | Phase 1. Through tokens only. |
| 2. Shared component styling | Borders, backgrounds, shadows, states of buttons, inputs, tables, cards, status indicators | Phase 1. Must not change a component's size. |
| 3. Screen layout and density | Where things sit, sizes, spacing, row heights, columns, what is shown | Phase 2. One screen at a time, each approved first. |
| 4. Workflows and interactions | Steps, field order, keyboard flow, navigation structure | Phase 2. Explicit approval, never bundled with cosmetics. |

**Phase 1 (design system and themes)** may change layers 1 and 2 only. It must not change screen layouts, field positions, navigation structure, workflows, component dimensions or information density. Any typography change must be checked for wrapping, clipping and layout shift.

**Phase 2 (screen by screen)**. For each screen, in this order:

1. Analyze the existing layout, function and user workflow.
2. Identify improvements to looks, density and productivity.
3. Present a visual mockup in the approved BPS theme.
4. Label each change as cosmetic, layout or workflow.
5. Explain benefits and tradeoffs.
6. Wait for explicit approval before implementing.

**Protected screens.** Some layouts were deliberately tuned for operations and must not be reorganized without explicit approval, even for a change that looks harmless:

- **Order Entry** (`/orders/new`, `/orders/[id]/edit`): optimized for heads-down, high-speed data entry.
- Treat any other entry or production-floor screen as protected until the owner says otherwise.

**Screens approved for layout change so far:** Dashboard (2026-11-25), AR Open Balances (2026-11-25), Admin › Company/Customer Users (Show inactive, Last activity; 2026-11-25), Customer portal › Users (new, 2026-11-25), Orders › Manage Orders (2026-11-25).

## 3. Target screens

- Primary: a 13-inch laptop with a 1920 × 1080 display. With normal display scaling (125–150%) and browser chrome, the usable viewport is roughly **1536 × 740** to **1280 × 600** CSS pixels. Design for that, not for 1920 × 1080.
- Also check: 1366 × 768, 1280 × 800, a large desktop, iPad (touch), and a phone.
- Large screens should use the extra space. Small screens reorganize (stack, fold the sidebar, scroll tables inside their own panel); they do not just shrink and do not drop essential functions.
- The sidebar docks at 1280px and wider; below that it opens as a sheet.

## 4. Themes and tokens

Architecture (`website/lib/theme/`): a theme is data only, 11 hex seed colors per mode (`themes.ts`). `derive.ts` turns seeds into a full token set and corrects anything that fails contrast; `tokens.ts` maps that onto the shadcn/Tailwind tokens; `apply.ts` writes them on `:root[data-bps-theme]`. The server paints the saved theme into the first HTML, so there is no flash. Users choose a theme and Light / Dark / Follow system under Profile › Appearance, and can build their own.

**BPS identity themes (built in):**

| Theme | Character | Accent |
|---|---|---|
| **Ledger** | Cool slate, white work surfaces | Ink blue |
| **Hearth** (default) | Warm grey, white panels | Copper |
| **Graphite** | Green-grey, dark top bar in both modes | Teal |

Bakery (the original look), Clay, Sepia, High contrast and the curated catalog remain available. **Printing** still uses Bakery's fixed light colours. The **customer portal** shows the default theme (Hearth) whatever a device last chose; customers cannot pick a theme.

**Semantic tokens** (use these Tailwind names, never raw palette colors):

| Purpose | Token classes |
|---|---|
| Page / panels / sidebar | `bg-background`, `bg-card`, `bg-muted` |
| Text / secondary text | `text-foreground`, `text-muted-foreground` |
| Brand accent: primary buttons, links, selection | `bg-primary`, `text-primary`, `ring-ring` |
| Hover and selected rows | `bg-accent`, `bg-muted/40` |
| Lines | `border-border`, `border-input` |
| Good / money in | `text-success`, `bg-success-soft` |
| Caution | `text-warning`, `bg-warning-soft` |
| Information | `text-info`, `bg-info-soft` |
| Error / overdue / money out | `text-destructive` |

Rules:

- No hex colors and no raw Tailwind palette classes (`text-amber-600`, `bg-orange-500`, …) in screens. They do not follow themes or dark mode.
- The accent is for actions and selection. Green, amber, red and blue are for status only.
- New themes are added in `themes.ts` (built in) or `catalog.ts` (curated); `npm test` checks every theme for contrast.
- A color need that the tokens do not cover is a design-system change: propose a token, do not hard-code.
- Graphite's dark top bar is defined in `app/globals.css` (`.bps-topnav`).

## 5. Typography

- **Inter** is the one application font, for text and for numbers. No per-theme fonts: a font change shifts every layout.
- Playfair Display belongs to the public marketing pages only. It is being removed from staff screens as each screen is reviewed. Never set a figure in a serif.
- Sizes in use: `text-xs` (12px) for labels, table headers and secondary lines; `text-sm` (14px) for body, tables and controls; `text-lg` (18px) for a page title; `text-2xl` (24px) for a headline figure. Avoid one-off pixel sizes.
- Weights: 400 body, 500 labels and links, 600 headings and totals.
- Hierarchy comes from weight and color (`text-muted-foreground`) before size.
- Numbers in columns use tabular figures (already applied to every `th` and `td`; add `tabular-nums` elsewhere).

## 6. Spacing and density

Phase 1 does not change sizes. Current shared sizes: buttons and inputs 40px (`default`) and 36px (`sm`); top bar 56px; sidebar 260px.

Any density change is Phase 2 and screen-specific. The dashboard, as the first approved screen, uses: 12px gaps between panels, 40px panel headers, table rows with `py-1.5`, 16px horizontal cell padding. Use it as the reference when proposing other screens.

A user-selectable compact / comfortable density setting has been proposed but is **not approved**.

## 7. Components

Use the shared components in `website/components/ui/` and `website/components/bps/`. Change a look in the shared component, not per screen.

- **Navigation.** Top menubar for modules, context sidebar for quick access and recent records. Structure is layer 4.
- **Panels and cards.** One border, `bg-card`, small radius, at most `shadow-sm`. A title row with an optional sub-line and one link. Do not put a card around every number; group related figures in one panel with hairline dividers.
- **Tables.** Left-align text, right-align numbers and money. Header in `text-xs`, muted, on `bg-muted/50`. Row hover `bg-muted/40`. Totals in a distinct final row. Wide tables scroll inside their own container.
- **Forms.** Label above the field, required fields marked with `*`. Field order and tab order are layer 4.
- **Dialogs.** Title says the action; primary button on the right names the action ("Save payment", not "OK"). Destructive actions use the destructive style and say what will be lost.
- **Button order.** In every form, panel and dialog: Cancel (outline) on the left, the main action (primary) on its right. An action the person came to do, such as Send invite, uses the primary style too.
- **Reports and print.** Print colors are fixed (Bakery light) regardless of the screen theme.
- **Icons.** `lucide-react` only, 16px in text rows, with an accessible label when the icon is the whole control.

## 8. Status, money, dates and numbers

- **Status** is shown with a colored dot or soft-background pill plus a word. Never color alone.
- **Money**: `$1,234.56`, two decimals, right-aligned. The sign goes before the `$`. Whole dollars only in headline figures.
- **Quantities**: thousands separators, right-aligned.
- **Dates**: computed in the database in the tenant's time zone. Show one format per screen.
- **Change vs a prior period**: ▲ or ▼, the percentage, and what it is compared to. Green up, red down.
- Totals, dates and business rules are computed in database functions, never in the website.

## 9. Accessibility and keyboard

- Text contrast at least 4.5:1, controls and focus rings 3:1 (enforced for themes by the tests).
- Every control is reachable by keyboard and shows a visible focus ring (`focus-visible:ring-2 ring-ring`).
- Touch targets at least 40px on iPad.
- Data-entry screens keep their existing tab order and shortcuts.
- Respect reduced-motion; keep transitions short.

## 10. Patterns to avoid

- Raw palette colors or hex values in a screen.
- Serif or decorative fonts in the application; oversized headings.
- A card, icon tile and shadow around every figure.
- Large padding that forces scrolling on a 1280 × 600 viewport.
- Capping content width so wide screens sit half empty.
- Formatting money or dates differently on different screens.
- Mixing a layout or workflow change into a cosmetic change.
- Reorganizing a protected screen.

## 11. Review checklist

Before calling UI work done:

- [ ] The change is labeled with its layer; layers 3 and 4 have explicit approval for this screen.
- [ ] Only tokens are used for color; it reads correctly in Hearth, Ledger and Graphite, light and dark.
- [ ] Checked at about 1536 × 740 and 1280 × 600, and on iPad width; no clipping, unwanted wrapping or sideways page scroll.
- [ ] Numbers are right-aligned with tabular figures; money and dates follow section 8.
- [ ] Keyboard path and focus rings work; tab order unchanged on entry screens.
- [ ] Permissions, queries, calculations and workflows are unchanged.
- [ ] `npm test` and the type check pass.
- [ ] This document is updated if a new decision was approved.

## 12. Known gaps

- About 150 uses of raw Tailwind palette colors (amber, orange, sky, red, green) remain across screens and need moving to tokens.
- Playfair Display is still set inline on several staff and portal screens.
- Money and dates are formatted in place in many files; there is no shared formatter yet.
- Four control heights (28, 32, 36, 40px) are mixed across screens.
- Main content is capped at 1440px wide.

## 13. Decision log

| Date | Decision |
|---|---|
| 2026-11-25 | Two-phase approach adopted: design system and themes first, then screen-by-screen layout with approval per screen. |
| 2026-11-25 | Ledger, Hearth and Graphite approved as BPS themes. Hearth chosen by the owner as the default. |
| 2026-11-25 | Inter stays the single application font; no per-theme fonts. |
| 2026-11-25 | Dashboard layout redesign approved and implemented. |
| 2026-11-25 | Order Entry declared a protected screen. |
| 2026-11-25 | Hearth is the default for everyone until they choose another theme; the customer portal shows Hearth too (it was fixed to Bakery). Printing stays Bakery light. |
| 2026-11-25 | Admin › Users: Show inactive users checkbox (off by default, says how many are hidden), Last activity column (time and approximate place), "Active in this company" wording; ended accounts labeled Ended. |
| 2026-11-25 | Customer portal › Users for customer administrators (list, add, role, invite, deactivate; never their own access), styled like the approved Dashboard panels. |
| 2026-11-25 | Privacy line for customer users: the bakery (second-level support) sees their name, email, role, account and status and can deactivate them; their activity times, IP addresses and places are visible only to their own customer administrator. Customer Users has no Last activity column. |
| 2026-11-25 | Button order everywhere: Cancel on the left, main action (primary) on the right; Send invite is primary. Applied to Admin › Users and portal › Users. |
| 2026-11-25 | Manage Orders redesign (docs/design/mockups/manage-orders.html): real orders; Day / Shift / Group dropdowns (Today, All shifts, Group by Shift by default); compact one-line summary strip, centered, status figures filter the list; search right above the list; 50 per page with group subtotals over all pages; no header buttons (New order and Export Orders are in Quick access); shift names from the company's production codes (AM, PM, PM2, …). |
| 2026-11-25 | AR Open Balances: list only customers with an open balance (with the balance), click a name for its open items below (each with the payments and credits applied and what else they covered), collapsible first section that folds when a customer is opened. |
