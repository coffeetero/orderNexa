# Development Guidelines

Use this file for implementation rules (application and database development). It is normative for Cursor coding behavior.

## Core Architecture

- Stack: Next.js + Supabase.
- Auth/session: SSR cookie-based auth only.
- Data security: RLS is enforced in the database; do not bypass it in app logic.

## Next.js and Supabase Usage

- Prefer Server Components by default.
- Use Client Components only when interactivity requires it (`'use client'`).
- Keep route files thin; move reusable logic into `components/` or `lib/`.
- Use `@/lib/supabase/server` in server components.
- Use `@/lib/supabase/client` in client components.
- Do not use legacy `@/lib/supabase` imports.

## Database and Schema Rules

- Application DB objects are in the `bps` schema.
- Do not hardcode schema prefixes in application SQL unless explicitly required.
- Prefer schema-agnostic SQL via `SET search_path` and unqualified object names.
- Use `fnd_` (foundation), `ar_` (receivables), and `om_` (orders) naming conventions.
- Primary keys should use `BIGINT` unless a specific exception is documented.

## SQL Authoring Standards

- Keep functions/procedures readable and compact; avoid variable bloat when a CTE/query can express the same logic.
- Add concise comments for non-obvious logic.
- Follow table alias standards from `docs/cursorSqlTablesAliases.md`.

## File and Script Organization

- Table/DDL scripts: `database/schema/`.
- Function/procedure scripts: `database/functions/`.
- Data load/reset/migration scripts: `database/migration/`.
- Name SQL files after the primary object they create/update when practical.

## UI/UX Guidelines

- Follow existing visual patterns (spacing, typography, controls).
- Reuse existing shared components before introducing new UI patterns.
- Prioritize fast keyboard-driven data entry workflows where applicable.

## Explicit Do / Do Not

- Do keep components focused, reusable, and consistent with existing project patterns.
- Do not duplicate auth checks already handled at layout/middleware levels.
- Do not store auth/session-sensitive data in localStorage.
- Do not introduce alternate auth/session flows without explicit project direction.
