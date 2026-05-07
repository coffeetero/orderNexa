# orderNexa Overview

orderNexa is a migration and platform project for modernizing BPS, a wholesale bakery production system originally built as a PowerBuilder/SQL Anywhere client/server app. Near-term focus is reproducing enough legacy BPS workflow for Alpine Bakery parallel testing; long-term vision is a reusable multi-tenant business application framework.

Core architecture: Next.js app in `website/`, Supabase/PostgreSQL backend, database schema/functions/policies under `database/`, and project docs under `docs/`. Primary app flow is intended to be React UI -> Next.js API route -> PostgreSQL function -> tables. Tenant context is subdomain-based; customer context is path-slug-based. URL context is not a security boundary; database/API authorization must enforce tenant/customer access.

Repo structure:
- `website/`: Next.js 13 App Router app, React 18, TypeScript, Tailwind, Radix/shadcn-style UI primitives, Supabase clients.
- `database/schema/`: table/DDL scripts.
- `database/functions/`: PostgreSQL functions/RPC scripts.
- `database/policies/`: RLS policy scripts.
- `database/migration/`: migration and seed helpers, mostly Python/PowerShell/SQL.
- `docs/`: architecture, UI, data model, cursor/development guidance.

Important current product areas: customer management and order entry. The Order Entry screen is a keyboard-first workflow surface; order number is display-only, existing orders are selected through a popup/internal `order_id`, and save clears the form/focuses Customer for rapid entry.