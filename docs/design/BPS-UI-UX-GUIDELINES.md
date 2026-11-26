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

**Screens approved for layout change so far:** Dashboard (2026-11-25), AR Open Balances (2026-11-25), Admin › Company/Customer Users (Show inactive, Last activity; 2026-11-25), Customer portal › Users (new, 2026-11-25), Orders › Manage Orders (2026-11-25), Order Entry › Invoice No. box and order search fields only (2026-11-25), Financials › Enter Credits (2026-11-25).

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
| **BPS Classic** | The old BPS window: Windows gray, blue top bar, yellow headers, cyan entry fields; light only | Windows blue |

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

- **Navigation.** Top menubar for modules, context sidebar for quick access and recent records. The breadcrumb bar ends with a screen search (Ctrl+K) and 4 icon quick buttons each user assigns from the avatar menu (default Enter Orders, Enter Payments, Customers, Items). Structure is layer 4.
- **Panels and cards.** One border, `bg-card`, small radius, at most `shadow-sm`. A title row with an optional sub-line and one link. Do not put a card around every number; group related figures in one panel with hairline dividers.
- **Tables.** Left-align text, right-align numbers and money. Header in `text-xs`, muted, on `bg-muted/50`. Headers are always centered over their column, whatever the column's alignment. When a header is too wide for its column, break it onto two lines rather than widening the column or abbreviating it; headers are bottom-aligned (`align-bottom`), so single-line headers sit on the same baseline as the second line of two-line ones. Row hover `bg-muted/40`. Totals in a distinct final row. Wide tables scroll inside their own container.
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
| 2026-11-25 | Manage Orders redesign (docs/design/mockups/manage-orders.html): real orders; Day dropdown (Yesterday, Today, Tomorrow, This week; Today by default) with From / To dates always shown, Shift and Group dropdowns (All shifts, Group by Shift by default); compact one-line summary strip, centered, status figures filter the list; search right above the list; 50 per page with group subtotals over all pages; no header buttons (New order and Export Orders are in Quick access); shift names from the company's production codes (AM, PM, PM2, …). |
| 2026-11-25 | AR Open Balances: list only customers with an open balance (with the balance), click a name for its open items below (each with the payments and credits applied and what else they covered), collapsible first section that folds when a customer is opened. |
| 2026-11-25 | Financials › Cash › Enter Payments (docs/design/mockups/enter-payments.html), modeled on old BPS AR - Payments: Customer picker as in Enter Orders (accounts only), Received, Check no. (CASH for cash), Amount, live Check balance; cursor waits in Invoice #, ↑ ↓ / typing / click picks, Enter or Tab to Payment (defaults to what is open), Enter applies and moves to the next open one; Tab to Allowance and Allowance reason (why and which items, stored on the invoice); credits taken whole; read-only list with one live Balance column (Returns column kept); Cancel and Save payment top right; over-applying blocks Save, money left over is kept as unapplied cash only after asking. Manage Payments renamed Payment History. |
| 2026-11-25 | Enter Payments: earlier payments with unapplied cash show in the list as PMT rows and are taken whole like credits (oldest money is applied first); a new payment needs its check no. or CASH (reapplying earlier cash alone does not); money left over gets a gentle confirm. |
| 2026-11-25 | New built-in theme BPS Classic (docs/design/mockups/bps-classic-theme.html): old BPS window colours, softened to pass contrast, light only. Windows gray and blue, blue top bar, yellow table headers and grid lines everywhere; screens opt in to yellow field labels (bps-label), cyan fields you type in (bps-entry), yellow highlighted amounts (bps-hi) and a blue selected row (bps-sel). These styles exist only under data-bps-theme='bps-classic', so other themes are unchanged. Enter Payments uses all four. |
| 2026-11-25 | Order Entry (protected; this change only, docs/design/mockups/order-entry-invoice-no.html): read-only Invoice No. box in the item row, left of the read-only Order Number, not in the tab order. Shows the invoice number once the Packaging List has issued it, otherwise Draft (run processed), Not invoiced, or New. Search existing orders also matches invoice no., PO and customer number, and each row shows the invoice no. and PO. |
| 2026-11-25 | Order Entry (owner request): PO Number 20% narrower (115px); Invoice No. and Order Number the same width as PO Number. The cutoff line is removed from staff Enter Orders: cutoffs apply to customers only (the save function still enforces them for customers). |
| 2026-11-25 | Order Entry (owner request, no mockup): Quantity label shortened to QTY and its box 25% narrower (60px). |
| 2026-11-25 | Order Entry (owner request): PO Number, Total Order, Invoice No. and Order Number are the same width as Delivery (96px). |
| 2026-11-25 | Financials › Enter Credits redesign (docs/design/mockups/enter-credits.html): filters Customer (Enter Orders customer search, account customers only; its departments' and sites' orders are included), Production Date (today by default) and Production Time; orders list (Order No., Dept/Event, Amount, Invoice, Status) capped at about 8 rows with its own scroll; picking an order shows Item name, Qty, Price, Extended, Credit Qty, Credit Amt; Reason, then Cancel and Save under the grid. One credit memo per order. Orders not on an issued invoice are greyed out. Credit Amt is a screen preview; the saved amount and the limits come from the database. |
| 2026-11-25 | Enter Credits (owner request): Find by dropdown (Order No. default, Invoice No., PO No.) and a Number box left of the customer search; Enter finds the order and opens its account, date and time with the order selected, several matches show a list to click, blank + Enter moves to the customer search. Production Date and Time are disabled until a customer is chosen. |
| 2026-11-25 | Enter Credits (owner request): Orders grid gains PO Number, Order No. and Invoice No. (renamed) centered; the items grid is titled Order Detail with Qty centered; Cancel and Save move to the right of the Orders bar; Reason fills in from the credit lines ("Credit 3 Whole Wheat, Credit 2 Brioche") until the user types their own. |
| 2026-11-25 | Enter Credits (owner request): while a number is in the Find box, Customer, Production Date and Production Time are disabled (clear the number to change them); the Orders bar reads "Orders for <customer> · <date> <time>". |
| 2026-11-25 | Enter Credits: a Credit Qty above what is left (ordered less earlier credits) turns the box red, shows "Only N left" in Credit Amt, is left out of the total and keeps Save off; the database refuses it too. |
| 2026-11-25 | Enter Credits: an order found by number whose account is inactive still shows the account in the Customer box and the Orders heading (the picker lists active accounts only). |
| 2026-11-25 | Enter Credits: Order Detail shows Credited Qty (earlier credits on the line, from the stored ar_transaction_lines.quantity_credited) before Credit Qty; quantity only, no credited amount column, by owner decision. |
| 2026-11-25 | Enter Credits: Clear button left of Cancel on the Orders bar (Clear, Cancel, Save). Clear starts over (number, customer, lists cleared, date back to today, cursor in Number); Cancel only drops the typed credit quantities and reason. |
| 2026-11-25 | Enter Credits: Orders grid starts with Date (the order date, MM/DD/YYYY, centered) before Order No. |
| 2026-11-25 | Organizer › Calendar: Day / Week / Month / Agenda with a left rail (Create, mini month, calendars with show/hide, production-run overlay); event dialog with repeat; Google-style keyboard shortcuts. |
| 2026-11-25 | Calendar colours come from theme tokens (accent, info, success, warning, destructive, muted); read-only items from BPS (production runs) are drawn with a dashed outline. Bends the status-colour rule; owner to confirm or ask for categorical tokens. |
| 2026-11-25 | Organizer › Tasks: three panes (views + lists rail, task list, details pane that saves per field); Google Tasks model (lists, star, date and optional time, one level of subtasks, Completed section, My order / Date / Starred sort) plus company-shared lists, assign to staff, Upcoming / Starred / Assigned to me views; delete with Undo instead of a confirm. |
| 2026-11-25 | Repeating tasks: the next occurrence is created in the database on completion; a late completion skips to today or later; repeats may carry subtasks. |
| 2026-11-25 | Inventory › Recipes (new screen): two panes like Contacts; recipe = base-batch weights, baker's % of total flour incl. pre-ferment flour (BBGA overall formula), all figures from inv_recipe_calc; summary column beside the formula only at 1700px+, below it otherwise. |
| 2026-11-25 | Recipe ingredients are a per-tenant catalog (inv_ingredients) with role, price and allergens, not fnd_items; recipes link to items through dough_code = fnd_items.dough_type and an optional finished item. |
| 2026-11-25 | Batch sheets print in fixed black on white, like nutrition labels. |
| 2026-11-26 | Grid headers always centered; a header too wide for its column goes onto two lines, and all headers are bottom-aligned so single-line ones line up with the second line. Applies to every grid through one rule in globals.css (thead th), which overrides per-column alignment classes; cells keep their own alignment. |
| 2026-11-26 | Menu: Orders and Production merged into one Operations mega menu with three columns, Orders, Production and Delivery (planned: Routes Maintenance, Vehicles, Maintenance, Driver Checks, Fuel & Costs, Renewals). Branch ui-redesign. |
| 2026-11-26 | Breadcrumb bar: screen search (Ctrl+K, jumps to a screen) then 4 icon quick buttons at the right end; each user assigns them from Quick Buttons in the avatar menu (under Appearance), saved as their Quick access pins; the list shows only screens the user may open; defaults Enter Orders, Enter Payments, Customers, Items. The dead search icon in the top bar was removed. Bar 42px, breadcrumb text 14px, buttons and search 32px, icons 20px (touch friendly on iPad). |
| 2026-11-26 | Keyboard: Alt+Shift+1 to 4 (Option+Shift on a Mac) open the 4 quick buttons (plain Alt+digit switches tabs in Brave and Linux browsers); Ctrl+K (⌘K on a Mac) focuses screen search; labels and tooltips show the key for the user's computer. Browser keys (F5, F1, F3, F6, F11, F12, Ctrl+R/F/P/W/T) are never taken over, even where old BPS used them. |
| 2026-11-26 | Operations › Delivery › Routes Maintenance (docs/design/mockups/routes-maintenance.html): day of week buttons and production time in the title row; routes on the left with stop counts for all 7 days of that time, unassigned ship-to locations under them (Ordering only by default); the selected route's stops on the right (window and driver notes edited in place, ↑ ↓ buttons, Alt+↑/↓, Delete); Copy day, Date changes and Edit route dialogs; route sheet print in fixed black on white. |
| 2026-11-26 | Routes: stops are per ship-to (account or department; sites ride with their parent), one route per ship-to per day + production time; a department without its own stop follows its account's stop. Process run stamps each own-fleet shipment's route and stop from the delivery date's day of week and code with date changes applied; the Route Delivery Report prints in route order and stop number. |
| 2026-11-26 | Dense grids at 1280px: secondary columns fold into the main cell (customer number below 1440px, address below 1700px) instead of scrolling sideways; panel action buttons may show icons only below 1600px, with a tooltip and accessible label. |
| 2026-11-26 | Customer Management › Profile shows a read-only "Delivery routes" summary; routes are changed only in Routes Maintenance. |
