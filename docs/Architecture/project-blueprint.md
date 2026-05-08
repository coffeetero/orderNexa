# orderNexa Project Blueprint

Last updated: May 8, 2026

## Purpose

orderNexa is a migration and platform project. The first implementation is BPS, a wholesale bakery production system being migrated from a 25-year-old PowerBuilder/SQL Anywhere client/server application that is currently in production.

The near-term goal is to reproduce enough of the legacy BPS workflows in a modern web application that Alpine Bakery can begin parallel testing. The long-term goal is a reusable, multi-tenant business application framework that can support other verticals beyond wholesale bakery.

## Current Context

The project started about one month before this document was created. The database schema has already been redesigned and legacy data has been migrated into PostgreSQL/Supabase.

Development is currently in proof-of-concept and design exploration mode. The priority is learning what is possible, choosing maintainable patterns, and validating requirements against real legacy workflows before hardening the app for production.

The active app stack is:

- Next.js frontend.
- Supabase/PostgreSQL backend.
- PostgreSQL functions as the data access and business operation layer.
- Next.js API routes as the application-facing and future integration-facing API layer.
- GitHub as the source of truth.

## Product Vision

The system should become a self-service SaaS-style platform where a prospective tenant can sign up, use the application for free within limits, and upgrade to a paid plan.

BPS is the first vertical, not the whole product. The framework should be reusable for:

- Wholesale bakery production and order management.
- Small restaurants.
- Small service operators who serve homeowners, such as lawn service, handyman, and similar local operators.
- Future tenant vendors who may want to track their own orders across this tenant and other vendors.

The platform may also support service-provider users, such as call center agents and accountant agents, who can provide services across one or more tenants with restricted access.

## First Vertical: BPS

BPS is the first implementation of the framework. It targets wholesale bakery production operations.

The current tenant/customer example is Alpine Bakery. Tenant staff use tenant-level routes, while customers of the tenant use customer-scoped routes.

Example URL model:

```text
alpine.localhost:3000/orders
```

Tenant staff context for Alpine.

```text
alpine.localhost:3000/hilton/orders
```

Customer context for Hilton under Alpine.

The current proof-of-concept features are:

- Customer management.
- Enter Orders.

At go-live, customers should at minimum be able to log in and view or enter orders.

## Architecture Principles

The application should remain tool agnostic. Development may move between Cursor, Codex, Bolt.new, and other tools depending on their strengths. GitHub remains the source of truth.

The database layer should be schema agnostic. Objects are currently built in the `bps` schema, but the design should allow the schema name to be changed if there are collisions or if another deployment needs a different schema.

Application data access should go through API routes that map to PostgreSQL functions. This forces the web app to use and test the same API surface that external integrations can use later.

Primary flow:

```text
React UI -> Next.js API route -> PostgreSQL function -> tables
```

Direct table access from application features should be avoided unless there is a deliberate architectural reason.

The platform should eat its own API. Future clients such as Excel extracts, mobile apps, partner integrations, and automation tools should be able to use the same API contracts as the web app.

## Data Model Direction

The `bps` schema currently uses object prefixes to separate functional areas:

- `fnd_`: foundational objects.
- `om_`: order management.
- `ar_`: accounts receivable.

The prefix strategy supports framework reuse while keeping vertical-specific concepts organized.

The schema must support multi-tenancy through row-level security and authorization checks. Users may belong directly to a tenant or to a customer within a tenant.

Future user categories include:

- Tenant staff users.
- Customer users.
- Call center agents.
- Accountant agents.
- Other service-provider users.

Service-provider users may need access to multiple tenants and may be restricted to specific customers within each tenant or granted access to all customers for a tenant.

## Tenancy And Authorization

Tenant context is expressed through subdomains. Customer context is expressed through a path slug below the tenant subdomain.

The URL is a context selector, not a security boundary. Tenant and customer access must still be enforced by the API and database layer.

Because the app uses PostgreSQL functions, especially where `SECURITY DEFINER` may be used, each function that reads or mutates tenant data should follow a consistent authorization pattern:

1. Resolve the authenticated application user.
2. Verify tenant access.
3. Verify customer scope when applicable.
4. Verify capability or role for the requested action.
5. Return or mutate only authorized tenant/customer data.

This access model is a major design area to review before the proof of concept becomes production code.

## API Philosophy

The API should be designed as a durable contract, not just an internal convenience layer.

Every page feature should exercise API endpoints that call PostgreSQL functions. This supports:

- Web app development.
- Future public or partner APIs.
- Excel/reporting extracts.
- Automation.
- Testing of business operations outside the UI.

The API should not rely only on caller-supplied `tenant_id` or slugs for security. Request context, authenticated user identity, and database authorization checks must determine what the caller may access.

## Tooling Philosophy

Cursor is the primary hands-on IDE tool and is valued for fast interactive development.

Codex is expected to help as an architecture reviewer, implementation partner, code reviewer, debugger, and documentation maintainer. Codex should help keep concise engineering blueprints updated as decisions are made.

Bolt.new may be useful for rapid UI experiments and prototypes.

The project should avoid becoming dependent on assumptions from any single AI tool. Durable project knowledge should live in repository documentation.

## Documentation Practice

The repository should keep concise engineering blueprints while the product is still being explored. These notes are not final user documentation yet; they are decision memory.

The purpose of the blueprints is to preserve:

- The business reason behind each workflow.
- The current implementation contract.
- Open design questions and likely future directions.
- Differences between legacy BPS behavior and intentional web-app changes.
- Decisions discovered through real testing conversations.

Later, these notes can be promoted into fuller documentation for developers, operators, tenant administrators, API users, and end users.

When Codex, Cursor, or another tool changes a meaningful workflow, the relevant blueprint should be updated in the same work session. The docs should stay concise enough to read quickly, but specific enough that tomorrow's work does not depend on memory.

## Near-Term Delivery Targets

Target demo: Friday, May 8, 2026.

Demo goal:

- Show Alpine Bakery enough pages and workflows from the legacy BPS system to begin parallel testing.
- Use the demo to gather feedback, ideas, and validation from current production users.
- Keep the scope focused on proving workflow direction rather than final production polish.

Three-month goal: approximately early August 2026.

Three-month goal:

- Finish enough of the app for meaningful UAT.
- Continue expanding core legacy BPS workflow coverage.
- Prepare for production go-live near the end of the three-month period.

Go-live minimum:

- Customers can log in.
- Customers can view orders.
- Customers can enter orders.
- Tenant staff can support the core BPS workflows needed for parallel use.

## Open Design Questions

- What is the final authorization model for tenant staff, customer users, call center agents, accountant agents, and other service-provider users?
- Which authorization checks belong in RLS policies versus PostgreSQL functions versus API routes?
- Which PostgreSQL functions should use `SECURITY DEFINER`, and what standard guardrails should every such function follow?
- How should schema agnosticism be implemented in practice across Supabase clients, API routes, migrations, and SQL functions?
- What is the minimum feature set Alpine Bakery needs for the May 8 demo?
- What is the minimum feature set required for go-live at the end of the three-month target?
- How much of the legacy PowerBuilder workflow should be reproduced exactly, and where should the web version intentionally improve the workflow?

## Current Operating Mode

This project is currently in exploration and proof-of-concept mode. Decisions should be documented, but premature abstraction should be avoided.

The immediate priority is to validate architecture and workflow patterns with real BPS features. Once patterns prove useful, they can be promoted into framework conventions.

## May 6, 2026 Session Notes

Today's main focus was the tenant Order Entry screen.

Key decisions:

- Order Entry is a keyboard-first workflow surface, not a generic form.
- Existing-order selection should happen before defaulting Department/Event or moving focus to Item.
- The Order Number field is display-only; selection happens through a popup that uses internal `order_id`.
- `New Order` is a visible workflow state, not a generated database order number.
- After save, the form clears and focus returns to Customer for the next heads-down entry.
- Department/Event is central to supporting site/department/event orders and future walk-in orders.

Technical fixes completed:

- Live order detail retrieval now returns order lines after selecting/loading an existing order.
- Department/Event is saved through the order save flow.
- Customer hierarchy rows include customer type so the UI can distinguish account/site/department/event behavior.
- Order Entry layout was tightened for dense data entry: Customer and Item search widths aligned, dropdown rows compacted, Retrieve removed, and Order Number simplified.

## May 8, 2026 Session Notes

Today's work moved Order Entry closer to real Alpine parallel testing and added tenant-scoped document numbering.

Key decisions:

- Existing-order retrieval must use internal `order_id` for updates and reloads. Display order numbers are not stable enough to be the edit identity.
- Selecting an existing order from the popup should not automatically replace the currently selected customer when the user already selected a customer. The selected customer remains the workflow context; the loaded order supplies Department/Event and line details.
- If the Customer field is blank and a future search action is used, selecting an order may populate Customer from the selected order because there was no customer context to preserve.
- Location customers are order-entry helpers. When selected, they default Department/Event, but the saved order belongs to the immediate parent customer; the order stores a customer name snapshot.
- Tenant document numbers should be allocated only at save time, not when a new order form is opened.
- Tenant sequences belong in `fnd_tenant_sequences`, not as columns on `fnd_tenants`, so order, invoice, customer, and other number sequences can lock independently.
- Sequence masks support date tokens and grouped `#` placeholders. Grouped placeholders fill from right to left, with overflow expanding the leftmost group.
- Alpine Bakery uses the order number mask `####-####` for readability. Legacy max `ordr_no` seeds the sequence, and the next generated value advances one past the legacy max.

Technical fixes completed:

- Added `fnd_tenant_sequences` schema, policies, seed support, and tenant settings UI surface.
- Updated `om_orders_save` so new orders allocate `order_number` through `fnd_tenant_sequence_next`.
- Added Alpine sequence seed from legacy `ordr.ordr_no`.
- Added `top_customer_id` direction for customer hierarchy/security performance and updated customer seed support.
- Added user preference fields direction for time zone, language, number/date/currency formats.
- Fixed `bps_dev` grants for `fnd_tenant_sequences`. Remaining visibility issue appears to be RLS because direct SQL sessions do not have Supabase JWT app metadata.
