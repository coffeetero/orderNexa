# Order Entry Blueprint

Last updated: May 8, 2026

## Purpose

Order Entry is the most demanding BPS screen because it must support heads-down data entry. The target workflow should require no mouse use during normal entry except when the user is finished or intentionally chooses a visual option.

This screen should preserve the speed and workflow intent of the legacy PowerBuilder BPS order-entry process while using the web app's API-first architecture.

## Header Workflow

The tenant order-entry screen starts with four key header fields:

- Customer.
- Location/Event.
- Production date.
- Production code.
- Order number.

On page load, the app retrieves the customer hierarchy as JSON. The customer control displays customers, sites, and locations/events in a hierarchical list. The user can start typing, and the list filters while preserving enough hierarchy context to select the right entity quickly.

After the user selects a customer by pressing Enter or clicking:

1. Retrieve existing orders for the selected customer, production date, and production code.
2. Do not fill Location/Event or move focus to Item until the existing-order decision is resolved.
3. If no orders exist, prepare a new order, default Location/Event from the selected customer, show `New Order` in the Order Number field, and move focus to Item.
4. If one or more orders exist, show an order-selection popup immediately after customer selection instead of auto-loading any order.
5. The popup shows `New Order` first, followed by existing orders with order number, Location/Event context, and amount.
6. If the user selects `New Order`, default Location/Event from the selected customer, keep the grid empty, show `New Order` in the Order Number field, and move focus to Item.
7. If the user selects an existing order, set the Order Number display from that order, retrieve the order detail by `order_id`, populate Location/Event and the grid from the loaded order, and then move focus to Item.

The order lines grid must be updated from the selected order detail response, not from the header-only order lookup response.

The Order Number field is display-only on the header. Existing-order selection is handled by the popup, using the internal `order_id` for retrieval. Order numbers are display values and may be non-numeric, generated, or tenant-specific.

When a customer has already been selected, choosing an existing order must not replace that selected customer with the customer stored on the order. This matters for location/event workflows: a location selection can find parent-customer orders, but the user's selected customer remains the workflow context. The loaded order should provide the persisted Location/Event text and order lines.

When no customer is selected and the user searches existing orders by production date/code, selecting an existing order can populate Customer from the selected order because there is no customer context to preserve.

The popup is part of the keyboard flow:

- Focus moves into the popup when it opens.
- `New Order` is the first/default selection.
- Up and Down move the active selection.
- Enter chooses the active row.
- Only after the user chooses `New Order` or an existing order should the workflow continue to Location/Event and Item entry.

## Current UI Contract

The current tenant Order Entry screen uses a compact, single-workflow layout:

- Title: `Enter Orders - {selected customer}` after customer selection.
- Customer search: fixed width aligned with Item search.
- Location/Event: editable text field on the header row.
- Production Date and Production Time: header fields to the right of Location/Event.
- Order Number: display-only field centered under the `Order Number` label.
- Item search: fixed width aligned with Customer search.
- Item and Customer dropdown rows use compact spacing for high-density keyboard scanning.
- Save persists the order, clears the form, and returns focus to Customer.
- Clear/Cancel clears the form and returns focus to Customer.

The Retrieve button was removed because order retrieval is now driven by the existing-order popup.

## Customer Hierarchy

BPS customers can be one of several business types:

- Aggregator.
- Account.
- Site.
- Location or event.

The hierarchy is not just visual. It affects order entry, billing, invoicing, pricing, and future integration behavior.

## Aggregators

An aggregator represents many customers to increase purchasing power, negotiate discounts, or coordinate buying. Aggregators may have different requirements than regular account customers.

Example:

```text
Feather Stone
  NJ301
  NJ204
    Banquet
    Wedding
  NY200
    Kitchen
```

Aggregator-specific needs may include upload flows, such as CSV or Excel files that contain an aggregator account code. In some cases, the aggregator may intentionally keep the tenant from knowing the underlying end customer.

## Account Customers

An account customer is usually a customer responsible for billing. It may have many sites and locations. An account can call in or enter orders for itself, its sites, or its locations.

The account receives statements that show site, invoice, and order details.

Examples:

```text
The Hilton Hotels
  Hilton 5th Ave

Chase Bank
  Executive Floor
  Chase 2nd Ave
    Cafeteria
```

## Sites

A site belongs to an account customer. Sites can call in or enter orders. Sites can receive invoices, but they are not necessarily responsible for billing.

Invoices may show items separated by site or location.

## Locations And Events

Locations and events are used to separate order items within an order. They are not full billing customers.

The same item cannot be entered twice within the same customer/order grouping, so locations/events provide a way to separate duplicate item needs.

Example:

```text
Chase 2nd Ave
  Brioche        2
  French Bread   7

Cafeteria
  French Bread   6
```

When entering an order for a location or event, the location/event customer is used to default the editable Location/Event text. The parent customer ID is recorded on the order, while a `location_event` field is unique within that order.

The order-entry screen has an editable `Location/Event` text field in the header row. The field should not default immediately when the customer is selected if existing orders may need to be resolved first.

After the existing-order decision is resolved, Location/Event defaults from the selected customer. For a location/event customer, it should default from the selected location/event name for active entry, while the save function records the immediate parent's customer name as the order's customer snapshot. The user may override Location/Event before saving.

## Walk-In And On-The-Fly Orders

The location/event pattern also supports walk-in or on-the-fly orders where the tenant should not have to create a full customer and price list first.

Example future pattern:

- Define a general customer such as `Alpine`.
- Use `Alpine` as the order customer.
- Default the order's `location_event` field to an auto-numbered value such as `001`.
- Allow the user to append to or replace the generated `location_event` value.

This still needs implementation.

## Proposed Existing-Order Selection Flow

For account/site/location ordering, existing orders should be searched by the effective parent order customer rather than only the exact selected location/event customer. A location may be a child of a site or account, but the persisted order can still belong to the parent customer while using `event_location` to distinguish where the order applies.

Example:

```text
The Hilton Hotels 10000
  Hilton 5th Ave 10001
    Wedding 10002
    Kitchen 10003
  Hilton Luxury 10011
    Kitchen 10012
```

If `Hilton Luxury` enters and saves the first order, the order stores `customer_id = 10011` and receives an order number such as `ORDR1001`.

If `Hilton Luxury - Kitchen` later starts an order, the system should search for existing orders under the effective parent customer, `10011`, for the selected production date and code. Finding `ORDR1001` should not automatically load that order into the grid, because the kitchen may intend to create its own order.

Proposed interaction:

- When prior orders exist for the effective parent customer/date/code, open the order picker popup.
- Include `New Order` as the first/default selection.
- Show existing orders below it, including order number, Location/Event context, and amount.
- Pressing Enter on the default `New Order` keeps the grid empty and derives a default `event_location`.
- Selecting an existing order loads that order's lines for review or change.

This supports both intentions without forcing a mouse-dependent correction path:

- Create a new location/event order.
- Retrieve and edit an existing parent/site/location order.

For a selected location/event customer, the initial `event_location` default should be derived from the selected hierarchy path and a sequence when needed, for example `Hilton Luxury - Kitchen 001`. The user can replace it with a meaningful value such as `Hilton Luxury - Kitchen Noon`.

## Resolved Issue: Existing Order Lines

The order-entry flow previously had an issue where existing order headers were found, but the grid did not show order lines.

The corrected behavior is:

- Header-only lookup finds matching orders.
- Detail lookup retrieves the selected order with `headers_only=false`.
- Detail response includes `lines`.
- `OrderEntryForm` maps those lines into `draft.lines`.
- `OrderLineGrid` renders `draft.lines`.

The detail lookup must use `order_id`, not the display order number.

## API And Database Notes

Order Entry currently depends on these API/function contracts:

- Customer hierarchy is loaded as JSON and includes customer type so the UI can distinguish account/site/location/event behavior.
- Existing orders are retrieved through a header-only order lookup for tenant, customer, production date, and production code.
- Existing order detail is retrieved by `order_id` with `headers_only=false`.
- Order save sends `location_event` and line details through the API to the PostgreSQL save function.
- The save result returns the resolved order id, generated/final order number, and line references.
- New orders send a visible `New Order` state from the UI. The database assigns the real tenant order number during save.
- `om_orders_save` updates an existing order when `order_id` is provided. If `order_id` is null, the save path creates a new order and allocates an order number.

Recent database/function fixes:

- `om_orders_get` was corrected to match the current schema and return order detail lines.
- Stale references to removed item/order fields were removed from the active function path.
- `om_orders_save` was corrected to save `location_event`.
- `fnd_customers_get` was updated to include `customer_type` in hierarchy payloads.
- `om_orders_get` now treats a selected location customer as a lookup against its parent customer, so parent-level existing orders can be found from a location selection.
- `om_orders_save` records the appropriate parent customer for location-type selections and preserves a customer name snapshot on the order.

## Tenant Order Numbering

Order numbers are tenant-scoped and come from `fnd_tenant_sequences`.

Important rules:

- Numbers are allocated only when a new order is saved.
- Existing orders update by `order_id` and do not allocate a new number.
- `sequence_name = 'order_number'` is the sequence used by Order Entry.
- The sequence row is locked with `FOR UPDATE` during allocation so two order saves cannot receive the same number.
- Non-gap requirements are modeled through `requires_gapless`; tenants requiring non-gap order numbers should not be allowed to physically delete orders after assignment.

Mask interpretation:

- Date tokens include `[YY]`, `[YYYY]`, `[YYYYMM]`, `[YYYYMMDD]`, `[YYYY-MM]`, and `[YYYY-MM-DD]`.
- All `#` placeholders across the mask are treated as one grouped numeric field.
- The numeric value fills `#` positions from right to left.
- If the value has fewer digits than the total number of `#` characters, it is left-padded with zeroes.
- If the value has more digits than the total number of `#` characters, overflow expands the leftmost `#` group.

Examples:

```text
####-#### + 1151044     -> 0115-1044
#-#### + 1151044        -> 115-1044
[YY]####-#### + 1151044 -> 260115-1044
O## + 321               -> O321
```

Alpine Bakery currently uses `####-####`, seeded from the legacy maximum `ordr.ordr_no`. The sequence `start_value` preserves the legacy maximum and `next_value` advances one past it.

## Open Follow-Ups

- Add the no-customer Search button beside Production Code. It should pass production date, production code, and optional customer id into the existing-order lookup.
- Existing Orders popup should include customer search and group/sort results by account customer name, with existing orders listed under each account.
- Existing Orders popup should show customer number/name, Location/Event context, order number, and amount in the final compact layout.
- RLS for `fnd_tenant_sequences` needs a dev/admin access decision. `bps_dev` has grants, but direct SQL sessions may not see rows when the RLS policy depends on Supabase JWT `app_metadata.tenant_id`.
- Walk-in and sample order flows need a clean pattern for default customer, generated Location/Event, and price handling.
- Debugging flags should be added later so workflow/API checkpoints can be enabled without noisy production logs.
- Item property modeling needs future design beyond the current booleans such as sliced, wrapped, and covered.

## Design Notes

The order-entry screen should be treated as a workflow surface, not a generic CRUD form. Keyboard flow, predictable focus movement, and quick recovery from mistakes matter more than decorative UI.

Business rules around account, site, location, and event customers should be explicit in the API/database contract rather than hidden only in React component behavior.
