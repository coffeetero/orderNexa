# Development Guidelines

## Project Overview

- Next.js app using Supabase.
- SSR with cookie-based authentication.
- RLS enforced at the database level.

## Folder Structure Conventions

- `app/` -> routes and layouts.
- `components/` -> reusable UI components.
- `lib/` -> utilities and framework logic.
- `docs/` -> documentation.

## Page Creation Standards

- Use layout-level auth (do not duplicate auth checks in pages).
- Prefer server components by default.
- Use client components only when needed (`'use client'`).
- Keep pages thin; move logic to `lib/` or `components/`.

## Supabase Usage

- Use `@/lib/supabase/client` in client components.
- Use `@/lib/supabase/server` in server components.
- Never use legacy `@/lib/supabase`.

## Auth & Session Rules

- Session is cookie-based (SSR).
- Do not use localStorage for auth.
- Do not introduce alternative auth flows.

## UI/UX Consistency

- Reuse existing layout components:
  - `CustomerLayoutShell`
  - `DashboardHeader`
  - `CustomerSidebar`
- Follow existing spacing, typography, and styling patterns.
- Do not introduce new UI paradigms without alignment.

## State Management

- Prefer server-side data fetching.
- Avoid unnecessary client-side state.
- Keep client logic minimal.

## Naming Conventions

- Use `snake_case` for database objects.
- Keep naming consistent for components and files.
- Use clear, descriptive function names.

## Do's

- Keep logic reusable.
- Follow existing patterns.
- Keep components small and focused.

## Don'ts

- Do not duplicate auth logic.
- Do not bypass RLS.
- Do not introduce new Supabase client patterns.
- Do not store sensitive data in localStorage.
