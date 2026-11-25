---
name: bps-ui-design
description: BPS UI design standard. Use before creating, modifying, restyling or reviewing any screen, component, theme, color, font, table, form, dialog or layout in website/ (any .tsx under app/ or components/, globals.css, tailwind config, lib/theme). Enforces the two-phase rule - theme and component styling are separate from screen layout and workflow changes, which need per-screen approval.
---

# BPS UI design

The standard lives in `docs/design/BPS-UI-UX-GUIDELINES.md`. Read it now, in full, before touching UI code. Do not rely on memory of it and do not copy its contents here.

Then work in this order:

1. **Name the layer** of the requested change (guidelines section 2): theme, shared component styling, screen layout and density, or workflow.
2. **Theme or shared component styling:** change tokens or the shared component only. Do not alter any size, position, spacing or density. Check typography changes for wrapping and clipping.
3. **Layout, density or workflow:** stop unless the user has approved that change for that specific screen. Otherwise analyze the screen, present a mockup in the approved theme, label each change as cosmetic, layout or workflow, explain tradeoffs, and wait.
4. **Protected screens** (Order Entry and any screen listed in the guidelines): never reorganize without explicit approval, even as part of a broader task.
5. **Building a new screen:** follow the component, token, formatting and accessibility sections; reuse `website/components/ui` and `website/components/bps`.
6. **Before finishing:** run the review checklist in the guidelines (section 11) and report what you checked and what you could not.
7. **When the user approves a new design decision:** update the guidelines and add a line to its decision log in the same change.
