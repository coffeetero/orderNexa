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
