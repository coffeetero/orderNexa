# Suggested Commands

Run these from `D:\Dev\orderNexa\website` for the Next.js app:

```powershell
npm run dev
npm run build
npm run start
npm run lint
npm run typecheck
```

Project/file exploration on Windows PowerShell:

```powershell
Get-ChildItem -Force
Get-ChildItem -Recurse -File -Depth 3
Get-Content -Raw path\to\file
git status --short
git diff -- path\to\file
```

Notes:
- `rg` may be unavailable or blocked in this Codex desktop sandbox on this machine; use PowerShell enumeration/search if needed.
- Database scripts are organized under `D:\Dev\orderNexa\database` and should be handled carefully because they define schema, functions, policies, and seed/migration behavior.