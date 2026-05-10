# Custom Fields Architecture

## Implemented Slice: Item Prep Options

OrderNexa now has the first slice of the customization framework: cached valuesets for item preparation options.

The implemented item-prep flow is:

- `fnd_valuesets` defines the tenant-scoped valueset, currently `ITEMPREP`.
- `fnd_valueset_values` stores cached UI values such as `SLICED`, `WRAPPED`, and `COVERED`.
- `fnd_items.allowed_prep_options` stores which prep option codes may be selected for an item.
- `fnd_items.default_prep_options` stores which prep option codes are selected by default when the item is added to an order.
- `om_order_lines.prep_options` stores the final selected order-line prep option snapshot.

The Enter Orders page now uses `prep_options` instead of hardcoded `is_sliced`, `is_wrapped`, and `is_covered` order-line columns.

## Valueset Tables

`fnd_valuesets` is the valueset header table.

```text
fnd_valuesets
  tenant_id
  valueset_id
  valueset_code
  valueset_name
  value_type
  control_type
  source_type
  source_sql
  refresh_mode
  refresh_status
  last_refreshed_at
  last_refresh_error
  is_active
```

`fnd_valueset_values` is the runtime lookup table used by UI and backend functions.

```text
fnd_valueset_values
  tenant_id
  valueset_value_id
  valueset_id
  value
  label
  display_order
  is_default
  is_disabled
  metadata
  source_hash
  refreshed_at
```

SQL-backed valuesets are not used directly by the UI. SQL is intended to refresh/cache rows into `fnd_valueset_values`; runtime screens read the cached table.

## Item Prep Data Shape

The immediate Alpine item-prep valueset is:

```text
ITEMPREP
  SLICED  -> Sliced
  WRAPPED -> Wrapped
  COVERED -> Covered
```

Item-level JSONB stores codes only:

```json
{
  "allowed_prep_options": ["SLICED", "COVERED"],
  "default_prep_options": ["SLICED"]
}
```

Order lines store selected values as snapshots with labels:

```json
[
  { "value": "SLICED", "label": "Sliced" },
  { "value": "COVERED", "label": "Covered" }
]
```

The snapshot keeps historical orders readable even if option labels change later.

## Current Integration

The relevant database functions now use prep option JSONB:

- `om_items_get` returns labeled `allowed_prep_options` and `default_prep_options`.
- `om_orders_get` returns each line’s `allowed_prep_options` and selected `prep_options`.
- `om_orders_save` writes `prep_options` on `om_order_lines`.

The Enter Orders page uses a Prep multiselect in the ordered items grid. It no longer uses separate SL/W/CV order-line booleans.

The `om_order_lines` table no longer has:

```text
is_sliced
is_wrapped
is_covered
```

`bps_items` may still contain legacy capability/default fields for migration and backfill purposes. Those fields are not the order-line persistence model.

## Scripts

Permanent DDL:

- `database/schema/fnd_valuesets.sql`
- `database/schema/fnd_items.sql`
- `database/schema/om_order_lines.sql`

Seed/backfill:

- `database/migration/seed_item_prep_options.sql`
- `database/migration/seed_om_order_lines.sql`

One-time apply scripts:

- `database/migration/add_item_prep_options_jsonb.sql`
- `database/migration/drop_om_order_line_prep_booleans.sql`

Orchestration:

- `database/schema/recreate_all.py` includes `fnd_valuesets.sql`.
- `database/migration/seed_all.py` runs `seed_item_prep_options.sql` after `seed_bps_items.sql`.
- `database/migration/recreate_all_drop.sql` drops `fnd_valueset_values` and `fnd_valuesets`.

## Deferred Work

Future customization slices can add:

- SQL-backed valueset refresh jobs.
- Context-linked cached values.
- Structured validation rules for free-form fields.
- SQL validation rules with review/approval.
- Pricing modifiers based on selected options.
