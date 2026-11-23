# Items

## Compound items
A compound item is an item made from other items (a gift basket of small breads, baguettes and butter).
- `fnd_items.is_compound` flags it. Components are rows in `fnd_item_bom` (parent item, component item, quantity, decimals allowed).
- Two levels only: a compound item holds simple items. Enforced in the database: `fnd_item_bom_guard` (parent must be compound, component must be simple) and `fnd_items_compound_guard` (cannot turn Compound off while components exist, and a component cannot become compound). Self-reference, duplicates and quantity <= 0 are table constraints.
- `fnd_item_components_get` / `fnd_item_components_set` (full list; unlisted components are removed). API: `/api/items/components`.
- Item Profile: "Compound item" checkbox next to Active; the Components tab is enabled only for compound items. Preparation, Dimensions and Production are on the Details tab.
- The compound item has its own price in the pricing books and its own weight and box settings; components carry no price inside it. An order line is the compound item as one line. Expanding it into components for production, packing and inventory is not built yet.
- Inventory ingredients and recipes (many levels) will be a separate model.

## Item list and Stale
- The Item Profile has a collapsible item list (search, Active/Inactive, Compound, Unpriced, Stale, Category). Unpriced = on no active pricing book line.
- Stale = never ordered, or last ordered more than the company's "Stale after" years ago (`fnd_tenants.pricebook_unused_years`, default 2, Application Settings > Pricing; shared with the pricing book Stale filter).
- `fnd_items.last_ordered_date` is stored and refreshed by `fnd_items_last_ordered_refresh(tenant)` (meant for the nightly health check, see docs/backlog.md), so the list never scans order lines.

## Compound items in production reports
- `om_run_item_quantities(tenant, run)` returns the items to produce for a run with compound items expanded (basket quantity x component quantity; `from_compound` marks those rows). Simple lines come through as ordered. A compound item with no components returns nothing.
- The Baker's Report uses it: item quantities and totals count what is baked, `in_compounds` shows how much of an item's quantity comes from baskets (printed as "(n in sets)"), and the baskets themselves are listed in a "Compound items to assemble" section that is not part of the totals.
- Orders, invoices and statements keep the compound item as one line at its own price. Labels, the packaging list and the route delivery report are not expanded yet.
