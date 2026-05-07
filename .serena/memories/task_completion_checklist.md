# Task Completion Checklist

Before finishing code changes:
- Run focused verification appropriate to the change.
- For website changes, prefer `npm run typecheck`, `npm run lint`, and/or `npm run build` from `website/` depending on risk and scope.
- For UI changes, start/verify the local Next.js app when useful and inspect the affected page in-browser.
- For database changes, review affected schema/function/policy scripts and use Supabase/Postgres tooling intentionally; do not invent missing schema objects.
- Update relevant docs/blueprints in the same work session when a meaningful workflow, API contract, or architecture decision changes.
- Preserve unrelated user changes in the git worktree; do not reset or revert unrelated edits.
- Summarize changed files, verification performed, and any remaining risks/blockers in the final response.