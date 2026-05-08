# Feature and Issue Tracker

This file tracks roadmap items and known issues. It is not a coding standards file.

## Usage Rules

- Add new work under either **Feature Backlog** or **Issue Backlog**.
- Keep entries concise, actionable, and testable.
- Update status as work progresses.
- Link related PRs/commits when available.

### Status Values

- `todo`
- `in_progress`
- `blocked`
- `done`

### Priority Values

- `P0` critical
- `P1` high
- `P2` medium
- `P3` low

---

## Feature Backlog

### FT-002 Existing Orders Search And Popup Polish

- **Status:** `in_progress`
- **Priority:** `P1`
- **Owner:** unassigned
- **Area:** Order Entry

#### Goal

Complete the existing-orders search workflow for both customer-selected and no-customer investigation use cases.

#### Requirements

- Add a Search button to the right of Production Code.
- Search should pass production date, production code, and optional customer id.
- If Customer is blank, selecting an existing order should populate Customer from the selected order.
- If Customer is already selected, selecting an existing order should preserve the selected customer and only load Department/Event plus lines from the order.
- Existing Orders popup should include Customer search.
- Results should group/sort by account customer name, with existing orders listed under the account.
- Popup rows should show customer number/name, Department/Event context, order number, and amount.
- Popup line spacing should remain compact for keyboard scanning.

#### Notes

Location customers should search existing orders through the parent order customer. The location is used to default Department/Event, not as the persisted order customer.

---

### FT-003 Tenant Document Sequences

- **Status:** `in_progress`
- **Priority:** `P1`
- **Owner:** unassigned
- **Area:** Database + tenant settings

#### Goal

Support tenant-scoped document numbers such as order numbers, invoice numbers, customer numbers, and future generated identifiers.

#### Requirements

- Store sequences in `fnd_tenant_sequences`.
- Use independent rows by `tenant_id` and `sequence_name` so order and invoice allocation do not lock the same tenant row.
- Allocate order numbers only when a new order is saved.
- Do not allocate a new order number when updating an existing order by `order_id`.
- Support masks with date tokens and grouped `#` placeholders filled from right to left.
- Tenant profile/settings should allow editing start value and related sequence settings.
- Alpine Bakery should use `####-####`, seeded from legacy `max(ordr_no)`.

#### Notes

Current mask examples:

```text
####-#### + 1151044     -> 0115-1044
#-#### + 1151044        -> 115-1044
[YY]####-#### + 1151044 -> 260115-1044
```

Future customer-number automation may need template-backed custom rules, for example deriving site/location customer numbers from a top account customer number.

---

### FT-001 Debug Mode Side Panel

- **Status:** `todo`
- **Priority:** `P1`
- **Owner:** unassigned
- **Area:** UI + data/debug instrumentation

#### Goal

Add a setting-driven debug mode that opens a panel on the right side of the app and displays debug information from:
- database layer (RPC metadata, function responses, errors, timing)
- UI layer (state snapshots, events, selection context, fetch lifecycle)

#### Requirements

- Debug mode is controlled by settings (not always visible).
- Panel opens on the right side and can be collapsed/expanded.
- Panel content supports both:
  - database debug stream
  - UI debug stream
- Works in development first; production behavior is controlled by config.
- No impact to normal user experience when debug mode is off.

#### Suggested Settings

- `debug.enabled` (boolean)
- `debug.panel.position` (`right`)
- `debug.sources.ui` (boolean)
- `debug.sources.database` (boolean)
- `debug.verbosity` (`basic` | `verbose`)

#### Acceptance Criteria

- When `debug.enabled = true`, panel is visible and docked to right side.
- Database and UI debug events appear in the panel in near real-time.
- When `debug.enabled = false`, panel and debug collectors are inactive.
- No auth/session regressions and no layout breakage.

#### Notes

- Prefer redacting sensitive fields in debug output.
- Keep debug instrumentation centralized and easy to disable.

---

## Issue Backlog

### IS-002 fnd_tenant_sequences RLS Visibility For bps_dev

- **Status:** `todo`
- **Priority:** `P2`
- **Area:** Database security / RLS

#### Summary

`bps_dev` has table grants for `fnd_tenant_sequences`, but direct SQL visibility may still be blocked by RLS because the current policy relies on Supabase JWT `app_metadata.tenant_id`.

#### Follow-up

- Decide whether `bps_dev` should bypass RLS, use an admin/dev policy, or set a trusted session context for direct database work.
- Keep application access tenant-scoped and avoid weakening production RLS behavior.

---

### IS-001 RPC Signature Drift / Schema Cache Mismatch

- **Status:** `done`
- **Priority:** `P1`
- **Area:** Supabase RPC

#### Summary

Tenant customer page returned no data due to multiple `get_customers` function signatures in Supabase causing schema cache mismatch.

#### Resolution

- Dropped overloaded `get_customers` variants.
- Kept one canonical function signature.
- Reloaded PostgREST schema cache.

#### Follow-up

- Add migration guard to prevent duplicate overloads.
- Add startup check in docs/runbook for RPC signature consistency.
