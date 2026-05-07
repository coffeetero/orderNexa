# Style And Conventions

Development guidelines:
- Stack: Next.js + Supabase.
- Prefer Server Components by default; use Client Components only for interactivity (`'use client'`).
- Keep route files thin; move reusable logic into `components/` or `lib/`.
- Use `@/lib/supabase/server` in server components and `@/lib/supabase/client` in client components.
- Do not use legacy `@/lib/supabase` imports.
- Auth/session is SSR cookie-based only; do not store auth/session-sensitive data in localStorage.
- RLS is enforced in the database; do not bypass it in app logic.

Database conventions:
- Application DB objects are in the `bps` schema.
- Prefer schema-agnostic SQL via `SET search_path` and unqualified object names; avoid hardcoded schema prefixes unless required.
- Functional prefixes: `fnd_` foundation, `om_` orders, `ar_` receivables.
- Primary keys should use `BIGINT` unless an exception is documented.
- Table/DDL scripts belong in `database/schema/`; functions in `database/functions/`; policies in `database/policies/`; migration/seed helpers in `database/migration/`.
- Do not invent schema objects. Use existing schema exactly; if required schema is missing, leave a TODO or ask.

UI conventions:
- Use existing layout shells (`TenantLayoutShell`, `CustomerLayoutShell`) and `DashboardHeader`/sidebars.
- Reuse shared UI primitives from `components/ui` before adding variants.
- Dashboard surfaces are dense, restrained, and work-focused; avoid oversized headings.
- Typical typography: page/section titles `text-base` to `text-xl`, form/control text `text-sm`, meta text `text-xs` or `text-[10px]`.
- Use existing semantic tokens from `globals.css`, Tailwind spacing rhythm, and compact form/table patterns.
- Prioritize keyboard-driven data entry workflows where applicable.