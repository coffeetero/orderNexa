# Adding Item Options via JSONB

## Summary

OrderNexa supports tenant-specific item options without hardcoding order-line columns such as `is_sliced`, `is_covered`, or `is_wrapped`.

The current implementation uses a hybrid model:

- Define valid options through cached valuesets.
- Store item-level allowed/default prep option codes on `fnd_items`.
- Store selected order-line prep options as a JSONB snapshot on `om_order_lines`.
- Keep item variants optional for tenants that benefit from fast code-based entry.

This avoids spreading junction tables across the order-entry path while still keeping option codes controlled and reusable.

## Implemented Item Prep Model

Tenant values are defined by:

```text
fnd_valuesets
fnd_valueset_values
```

For Alpine, the current static valueset is:

```text
ITEMPREP
  SLICED  -> Sliced
  WRAPPED -> Wrapped
  COVERED -> Covered
```

Items store prep option codes:

```text
fnd_items.allowed_prep_options jsonb
fnd_items.default_prep_options jsonb
```

Example:

```json
{
  "allowed_prep_options": ["SLICED", "COVERED"],
  "default_prep_options": ["SLICED"]
}
```

Order lines store the selected order-time snapshot:

```text
om_order_lines.prep_options jsonb
```

Example:

```json
[
  { "value": "SLICED", "label": "Sliced" },
  { "value": "COVERED", "label": "Covered" }
]
```

The order-line snapshot represents what was ordered at that time. It should remain readable even if item defaults or option labels change later.

## Removed Order-Line Booleans

The order-line table no longer stores hardcoded prep booleans:

```text
om_order_lines.is_sliced
om_order_lines.is_wrapped
om_order_lines.is_covered
```

The Enter Orders page now reads and writes `prep_options`.

The database functions now follow this contract:

- `om_items_get` returns labeled `allowed_prep_options` and `default_prep_options`.
- `om_orders_get` returns line-level `allowed_prep_options` and selected `prep_options`.
- `om_orders_save` persists `prep_options`.

## Item Variants

Child items remain optional and tenant-driven.

Example:

```text
100 French Baguette
101 French Baguette Sliced
102 French Baguette Covered
103 French Baguette Sliced & Covered
```

Variants are useful when a combination has operational meaning:

- Faster clerk entry by item number.
- Distinct price.
- Distinct packaging behavior.
- Distinct production or reporting identity.
- Known customer or tenant preference.

For tenants with too many combinations, base items plus order-line `prep_options` are preferred.

## Order Entry Behavior

Different tenants and users may enter options differently, but all paths should normalize into the same order-line shape.

Supported entry patterns:

- Direct variant SKU entry, such as `101`.
- Encoded option code entry, such as `101-1324`.
- Base item entry followed by Prep multiselect changes.
- Customer-facing checkbox or dropdown selection.

Regardless of input path, the saved order line should include:

```text
item_id
item_description
quantity
price
prep_options
```

## Pricing Path

Pricing can evolve in stages:

1. Use the selected item or variant item price.
2. Add simple option surcharges if needed.
3. Add formal pricing rules later if option pricing becomes complex.

Variant item pricing should take precedence when the selected item is already a variant. If no variant exists, the system can price from the base item and optionally apply option-level surcharges later.

## Deferred Work

Future work can add:

- SQL-backed valueset refresh.
- Context-linked values.
- Structured validation rules.
- SQL validation rules with review/approval.
- Pricing modifiers based on selected prep options.
