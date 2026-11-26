# Purchasing module: research and outline

Status: research only, 2026-11-26. No code, database or menu was changed. New tables below are a list for owner approval.

## 0. Summary

- Build Purchasing as **buying ingredients (and later packaging) from vendors**: vendors, vendor items with pack sizes and prices, purchase orders, receiving, stock counts, suggested orders. Pay and book the bills in accounting (QuickBooks or similar), not here.
- Core idea from every tool studied: **separate the thing you buy (vendor item: "Giusto's 50 lb bag, item #123, $24.50") from the thing you use (ingredient: "bread flour, per lb/kg")**. A conversion factor links them. Recipes keep using `inv_ingredients`; Purchasing adds a layer under it.
- Recommended menu: **own top-level "Purchasing" menu** (section 2.3).
- Smallest useful first phase: vendors + vendor items (pack size, price, price history) feeding the ingredient cost that Recipes already uses. No POs yet.
- Packaging: **include it, but in Phase 4**, by making the catalog item-kind aware (ingredient or packaging) rather than a second system.

## 1. What a small-to-mid bakery purchasing module needs

### 1.1 What the tools do (and how I read them)

| Tool | Relevant behaviour | Source |
|---|---|---|
| Odoo | Purchase UoM on the product, converted to the stock UoM; the vendor line can carry its own preferred unit; units convert only within one category (weight to weight). Automatic POs need a vendor on the product. | [Odoo 18 UoM docs](https://www.odoo.com/documentation/18.0/applications/inventory_and_mrp/inventory/product_management/configure/uom.html), [Odoo 14 purchase UoM](https://www.odoo.com/documentation/user/14.0/purchase/products/uom.html) |
| Restaurant365 | Each **vendor item** has its own purchase unit; the same product in a different case pack or item number needs a separate vendor item. A "split unit" covers vendors that invoice in a smaller unit than they ship. Imported invoices with an unknown item create a new vendor item. Three-way match (PO, receipt, invoice) is a headline feature. | [Vendor item record](https://docs.restaurant365.com/docs/classic-vendor-item-record), [Purchased item record](https://docs.restaurant365.com/docs/classic-purchased-item-record-adding-a-new-purchased-item), [Multiple count UoMs](https://docs.restaurant365.com/docs/inventory-counts-using-multiple-count-u-of-ms), [R365 purchasing](https://www.restaurant365.com/inventory/purchasing-receiving/) |
| Craftable | Par = "in stock" threshold; items below par are flagged but **orders are never placed automatically**. Goal quantity subtracts what is already on order. Picks the purchase unit that meets par with the fewest units. Has 3-way match. | [Par levels](https://help.craftable.com/learning/setting-up-par-levels), [3-way matching](https://help.craftable.com/learning/3-way-matching) |
| MarketMan | Price-change notifications and price history; invoice OCR matched to POs, discrepancies flagged before approval; credits and price changes tracked during reconciliation. Some of this is plan-dependent. | [MarketMan](https://marketman.com/), [Snap](https://MarketMan.com/platform/marketman-snap-expense-tracking), [pricing](https://www.marketman.com/pricing) |
| BlueCart | Wholesale ordering network from the **supplier's** side (catalogs, customer price lists, order dashboard); also lists PO and supplier management. No approval or spend control per one listing. | [Capterra](https://www.capterra.com/p/150106/BlueCart/), [BlueCart PO article](https://www.bluecart.com/blog/order-management-software) |
| QuickBooks Online | PO, then item receipt and/or bill; partial receipts link several transactions to one PO; PO closes when billed. Users report friction receiving single lines on big POs. Inventory adjustments are separate from POs. | [Intuit help](https://quickbooks.intuit.com/learn-support/en-us/help-article/inventory-account/receive-inventory-item-receipt/L5xIhKRpV_US_en_US), [community thread](https://quickbooks.intuit.com/community/reports-and-accounting-5/process-for-receiving-partial-items-on-a-po-applying-partial-invoice-to-that-po-but-keeping-remaining-balance-of-po-unreceived-items-open-might-someone-help-50415) |

### 1.2 Pain points

**Not verified from owner forums.** My searches returned no Reddit threads (r/Bakery, r/smallbusiness); only vendor blogs, review sites and templates came back. Treat the list below as *vendor-marketing and review-site themes*, and ask Alpine's own staff for real ones (question 1):

- Ingredient cost swings, with costing done in spreadsheets that break when prices change ([Craftybase](https://craftybase.com/bakery-inventory-software), [Toast](https://pos.toasttab.com/blog/on-the-line/bakery-inventory-management), [Korona](https://koronapos.com/blog/bakery-inventory-management-system/)).
- Running out of an ingredient or over-buying; counts kept on paper or sheets ([Toast count sheet](https://pos.toasttab.com/blog/on-the-line/bakery-inventory-management)).
- Pack-size normalization (case price to price per oz/gram) done by hand in shared sheets ([example sheet](https://docs.google.com/spreadsheets/d/1bfOmwYtIgvW7VLQbX1QkPiSGSgZERT9DPLt_CgwzqVE/edit)).
- Order chaos across sticky notes, calls and email ([BakeSmart quote on Slashdot](https://slashdot.org/software/p/BakeSmart/)).
- Receiving mismatches: short ships, substitutions, price on invoice differs from PO; QuickBooks users report these are awkward to record ([thread above](https://quickbooks.intuit.com/community/reports-and-accounting-5/process-for-receiving-partial-items-on-a-po-applying-partial-invoice-to-that-po-but-keeping-remaining-balance-of-po-unreceived-items-open-might-someone-help-50415)).

### 1.3 Topics, with a recommendation each

| Topic | What it needs | Recommendation |
|---|---|---|
| Vendors | Name, contacts, lead time, order days/cutoff, minimum order, delivery days, terms (text), order method (email/phone/portal) | Phase 1. Reuse the Contacts pattern if the owner agrees (question 5). |
| Vendor items | Per vendor: their item #, description, pack (e.g. 50 lb bag), pack-to-ingredient factor, price per pack, preferred flag | Phase 1. This is the heart of the module. |
| Price history | Every price change with date and source (manual, PO, invoice) | Phase 1, append-only. Current price = latest row. |
| Purchase unit vs recipe unit | Vendor item stores `pack_qty` + `pack_unit` (e.g. 50 lb). Conversion to the ingredient's cost unit (lb/kg) is a **database function** (reuse `inv_unit_grams`). Count-in-bags vs recipe-in-grams is a display issue, not a data one. | Phase 1. Weight-to-weight only at first; "each" items (eggs by dozen, a 5 gal pail of oil by volume) need a density or each-weight, so mark volume and count as Phase 3. |
| Ingredient cost | Today one cost per lb/kg on `inv_ingredients`. Becomes **derived from the preferred vendor item's price** (or a rolled average) by a database function; manual cost stays as fallback. | Phase 1, needs owner decision (question 3). |
| Purchase orders | Draft, sent, partly received, received, cancelled; lines in vendor-item pack units; expected date; PO number; send as email/PDF | Phase 2. |
| Receiving | Receive against a PO line by line; partial deliveries keep the PO open; record actual price and lot/best-by when the vendor's price differs; receive without a PO | Phase 2. A price difference on receipt writes a price-history row and (optionally) alerts. |
| Stock counts | Count in the units people see (bags, pails, each), convert in the database; count sheets by storage location | Phase 3. |
| Reorder points | Min (and optional max/par) per ingredient, in recipe units; "on order" subtracted (Craftable behaviour) | Phase 3. Flag only; staff creates the order (matches Craftable, avoids surprise buys). |
| Suggested orders from production | Production plan → doughs → ingredient needs by day. Net against on-hand and on-order, round up to vendor pack sizes. Computed in the database, consumes the existing recipe flattening (`inv_recipe_flat`, `inv_recipe_calc`). | Phase 3, the main differentiator vs generic tools. Needs on-hand stock first, so it follows counts. |
| Invoices and matching | Capture vendor invoice number, date, lines, total; compare to PO and receipt (3-way) with price/qty tolerance | Phase 2 light (a receipt can carry the invoice #, total and a "matches" flag); full matching Phase 4 or never, depending on accounting (below). |

### 1.4 What belongs in accounting instead

Keep out: general ledger, bill payment and AP aging, vendor 1099s, bank reconciliation, sales tax, payment terms enforcement, credit memos as accounting entries. Purchasing hands accounting a **received-and-priced document** (export or later integration); the bill is booked there. Whether OrderNexa ever pushes bills to QuickBooks is a question for the owner (question 6). Note OrderNexa already has Financials > AR; AP is deliberately not proposed here.

## 2. How it fits what exists

### 2.1 Existing pieces (from the repo and the Recipes hand-over)

- `bps.inv_ingredients`: per-tenant recipe ingredient catalog with role (FLOUR/LIQUID/OTHER), `cost_amount` + `cost_unit` (kg|lb), allergens, notes, is_active. Used by Recipes (`website/components/features/inventory/recipes/`, e.g. the Ingredients dialog). Recipe cost and baker's % come from `inv_recipe_calc`.
- `bps.fnd_items`: **sale products** (unit_of_sale, per-piece weight, box capacity, `dough_type`). Recipes decided *not* to reuse it for raw ingredients ([recipes-handover.md](file:///Users/moraglen/Library/Application%20Support/Claude/side-session-notes/local_86bcc3fa-8f72-4a0e-9c2e-62e581733ad7/recipes-handover.md)). I agree: keep ingredients separate from products.
- I could not read the live table definitions through the Supabase connector (the schema query returned nothing for the `bps` schema in the connected project), so column names for `inv_ingredients` come from the hand-over note, not the database. Verify before the build.
- `website/lib/nav-config.ts` Inventory menu today: Items (Item Management, Pricing Books), Costing (Recipes, Costing & COGS soon, Waste Tracking soon), Nutrition (Nutritional Analysis soon, Nutrition Labels), Insight (Reports soon, Analysis soon). Other top-level menus seen: Production (incl. a *Packaging List* screen for shipping boxes), Delivery, Customers, Financials.

### 2.2 Proposed relationship

```
inv_ingredients  (what recipes use: lb/kg cost, allergens)      <- stays
      ^  1..n
po_vendor_items (what you buy: vendor, item #, 50 lb bag, price)
      ^  n..1
po_vendors
```

- `inv_ingredients.cost_amount` stays as the single number Recipes reads; a database function refreshes it from the preferred vendor item (price ÷ pack size in cost unit). Recipes code does not change.
- `fnd_items` is untouched. Products never appear in Purchasing, except possibly bought-in finished goods (flag as a question if Alpine resells anything).
- The planned Inventory > Ingredients screen (stock and ordering, owner decision) owns on-hand, min/max and the ingredient's vendor items tab. Purchasing owns vendors, POs, receiving and prices.

### 2.3 Menu placement

| Option | For | Against |
|---|---|---|
| Under Inventory | Ingredients live there; few clicks | Inventory is already four groups and mixes product, costing and nutrition; PO/receiving users (buyer, receiving dock) differ from recipe users; permission areas get muddy |
| Under Operations/Production | Suggested orders come from the production plan | Production is bake-day work (reports, labels); purchasing is weekly/daily buying and receiving |
| **Own top-level "Purchasing"** | Distinct roles and access areas (`purchasing.*`), clear home for POs/receiving/vendors, room to grow (packaging, invoices) | One more mega-menu column; sparse in Phase 1 |

**Recommendation: own top-level "Purchasing" menu**, placed beside Inventory. Ingredients (catalog, stock, counts, reorder levels) live under Inventory; Purchasing shows only buy-side screens. In Phase 1 it holds two items (Vendors, Price Lists), which is acceptable; a "soon" Purchase Orders entry makes the direction visible. If the owner prefers fewer top-level menus, the fallback is a "Purchasing" *group* inside Inventory, which can be promoted later without changing URLs if routes start at `/purchasing/...` from day one.

## 3. Packaging (bags, boxes, labels)

**Include it, later (Phase 4), and design for it now.** Bakeries buy packaging from the same vendors on the same POs, count it the same way, and run out of bags the same way. Different from ingredients: it is consumed per **product shipped/sold**, not per recipe (so no baker's %), and has no allergens. Approach: give the catalog an `item_kind` (INGREDIENT | PACKAGING | SUPPLY) so vendor items and counts work for both, and add a small "packaging per product" link (item → packaging, qty per unit) later, tying into the existing Production > Packaging List and `fnd_items` box fields. Phase 1-3 stay ingredient-only so the first release is not diluted. Alternative: skip packaging until a tenant asks; cost is mainly that the vendor-item table should not hard-code `ingredient_id` as NOT NULL (see tables). I could not find a source comparing tools on packaging; this reasoning is mine.

## 4. Phased plan

### Phase 1: Vendors and price lists (smallest useful)
Goal: know who sells what, at what pack and price, and keep recipe cost current.
- **Vendors** (list + detail, two panes like Contacts/Recipes).
- **Price Lists**: vendor items grouped by vendor or by ingredient; edit pack, price; price history drawer.
- Ingredient detail gets a "Vendors" tab (shared with the future Inventory > Ingredients screen).
- Database: cost refresh function; price-change report (items up/down since date).
- Tables: `po_vendors`, `po_vendor_items`, `po_vendor_item_prices`.

### Phase 2: Purchase orders and receiving
- **Purchase Orders** (list, editor, send as PDF/email, status).
- **Receiving** (open POs by vendor, line receive, partials, price/qty variance, receive without PO, invoice # and total).
- **Open Orders** view (what is expected, what is late).
- Tables: `po_orders`, `po_order_lines`, `po_receipts`, `po_receipt_lines`.

### Phase 3: Stock and suggested orders
- **Stock Counts** (count sheets, in purchase or recipe units, adjustments with reason).
- **Reorder Levels** (min/par per ingredient; low-stock list).
- **Suggested Orders**: production plan → ingredient need → net of stock and on-order → rounded to pack → draft POs per vendor.
- Tables: `inv_stock_counts`, `inv_stock_count_lines`, `inv_stock_moves` (ledger of receipts, usage, adjustments), and min/par columns on a stock-level table or `inv_ingredients` (owner decision; question 4).
- Use of stock by production (auto-deduct from recipes when a production run is closed) is a separate decision (question 4).

### Phase 4: Packaging, invoices, insight
- Packaging items and per-product packaging usage.
- Invoice matching with tolerances (only if the owner wants AP-lite; question 6).
- Purchasing reports: spend by vendor/category, price trends, yield and waste against recipe use (links to Costing & COGS and Waste Tracking, both "soon" today).

## 5. New tables (list only, awaiting owner approval; nothing created)

All tables: `tenant_id`, `created_at/by`, `updated_at/by`, RLS through `fnd_active_tenant_id()` and an access area (e.g. `purchasing.vendors`), all reads/writes through API → database functions, per project rules. Column lists are first drafts.

**Phase 1**
- `po_vendors`: vendor_id, vendor_name, account_no, contact_name, email, phone, address_line1, address_line2, city, state, postal_code, order_method (EMAIL|PHONE|PORTAL|OTHER), order_days text[], delivery_days text[], lead_time_days, order_cutoff_time, min_order_amount, terms_text, notes, is_active.
- `po_vendor_items`: vendor_item_id, vendor_id, ingredient_id (nullable for later packaging), item_kind (INGREDIENT|PACKAGING|SUPPLY), vendor_sku, description, pack_qty, pack_unit (g|kg|oz|lb now; later gal, each…), units_per_case (nullable, for case of bags), is_preferred, min_order_qty, price_per_pack (current, maintained by trigger/function from the latest price row), price_effective_date, is_active.
- `po_vendor_item_prices`: price_id, vendor_item_id, price_per_pack, effective_date, source (MANUAL|RECEIPT|INVOICE|IMPORT), source_ref_id, note.

**Phase 2**
- `po_orders`: order_id, vendor_id, po_no, status (DRAFT|SENT|PARTIAL|RECEIVED|CANCELLED), order_date, expected_date, ship_to, notes, sent_at/by, total_amount (database-computed).
- `po_order_lines`: order_line_id, order_id, line_no, vendor_item_id, ordered_qty (packs), unit_price, line_total (computed), notes.
- `po_receipts`: receipt_id, order_id (nullable), vendor_id, received_date, received_by, invoice_no, invoice_date, invoice_total, notes.
- `po_receipt_lines`: receipt_line_id, receipt_id, order_line_id (nullable), vendor_item_id, received_qty (packs), unit_price, lot_no, best_by_date, variance_note.

**Phase 3**
- `inv_stock_counts`: count_id, count_date, location, status (OPEN|POSTED), counted_by, notes.
- `inv_stock_count_lines`: count_line_id, count_id, ingredient_id (or vendor_item_id), counted_qty, count_unit, qty_in_cost_unit (computed).
- `inv_stock_moves`: move_id, ingredient_id, move_date, move_type (RECEIPT|COUNT_ADJUST|PRODUCTION|WASTE|MANUAL), qty_in_cost_unit, ref_table, ref_id, note.
- Reorder levels: `inv_ingredient_levels` (ingredient_id, min_qty, par_qty, unit) **or** columns on `inv_ingredients`; separate table is cleaner if levels ever vary by location.

**Phase 4**
- `inv_packaging_usage`: item_id (fnd_items), vendor_item/ingredient-kind id, qty_per_unit, per (EACH|BOX|CASE).
- Optional `po_invoices` / `po_invoice_lines` if full matching is chosen.

## 6. Unverified or weak claims

- No Reddit/forum pain points were found; section 1.2 is from vendor/review sites.
- MarketMan features by plan and prices ($127 to $249/month appeared across sources) are **unverified**; I did not confirm which plan includes price tracking.
- BlueCart pricing listing ($0.01, free tier) is a listing artifact; actual price unverified. BlueCart is mainly a *seller* platform, so I treated it as a reference for catalogs, not for buy-side design.
- Craftable: no documentation found on how invoice price differences update item cost.
- Odoo reordering-rule behaviour with UoM was not confirmed; only the UoM and vendor-unit points above are sourced.
- Restaurant365 approval routing not found.
- `inv_ingredients` columns come from the Recipes hand-over note, not a live schema read.

## 7. Questions for the owner

1. What goes wrong today at Alpine around buying: running out, surprise price increases, wrong deliveries, double orders, or something else? Who orders, who receives, and how (phone, email, portal, sticky note)? This decides whether Phase 2 or Phase 3 matters more.
2. How many vendors and ingredient/packaging items does Alpine have, and does any vendor sell through a portal or EDI, or send invoices by email/PDF? (Sizes the build; invoice import is a big feature.)
3. Should recipe ingredient cost come **automatically from the preferred vendor's latest price** (cost changes the day a price is entered), from a rolled average of recent receipts, or stay manual? This changes every recipe cost and COGS figure.
4. Is on-hand stock in scope now: should receipts add to stock and closing a production run deduct recipe ingredients, or will stock be counts-only and approximate? (Deduction needs accurate yields and is the largest risk to reliability.)
5. Should vendors reuse the existing Contacts/customer structure (one shared contact record) or be their own simple table? Does the same company ever act as both vendor and customer?
6. Where do bills get paid today (QuickBooks?), and do you want OrderNexa to stop at "received and priced" with an export, or hold invoices for matching?
7. Packaging: does Alpine want bags, boxes and labels tracked and ordered through this module (Phase 4), and do you want packaging use tied to products shipped?
8. Menu: top-level "Purchasing" (recommended) or a group inside Inventory? And who gets access: owner only, or a buyer/receiving role (affects the access areas to seed)?
