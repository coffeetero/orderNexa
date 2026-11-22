# Appearance themes: sources and how to curate them

BPS themes are colours only. Admin › Appearance lets each user pick Light / Dark / Follow system and a theme; the choice is saved
with the account (`fnd_user_preferences.appearance`) or kept on one device. Code: `website/lib/theme/`, `website/components/theme/`.

## What a theme is

11 colours per mode (light and dark): accent, danger, success, warning, a secondary (info) colour, three surfaces
(page, sidebar/tables, cards) and three text shades. `derive.ts` turns them into tokens, adjusting anything that would fail WCAG AA
text contrast (the page then says "Adjusted N colours for readability"), and `tokens.ts` maps those onto BPS's shadcn tokens
(`--background`, `--primary`, `--card`, …) plus the status tokens `--success`, `--warning`, `--info`. Nothing but colours is stored,
and nothing from a theme is ever executed.

The default theme, **Bakery**, is pinned to the exact colours in `globals.css`; a test fails if the two drift apart.

## Sources reviewed (2026-11-22)

| Source | What it is | Use |
|---|---|---|
| https://github.com/livlign/ccthemes (MIT) | ~50 Claude Code **terminal** themes as small JSON files: `{ name, base, overrides }` | **Curated catalog.** Accent (`claude`), status colours, `planMode` and `text` are taken from the files. |
| https://buildwithclaude.com/themes | A directory of 78 themes: 54 "Desktop app" (plugins with animated backdrops and code), 24 "Terminal" (e.g. matcra587/claude-themes), each with its own GitHub repo and licence | **Discovery only.** Desktop-app themes keep their colours inside executable code; the importer reads colours as text and never runs code, and the official examples (Apache-2.0) do not expose seed colours in a form it can read. Terminal themes can be imported through the GitHub link box. |

Limitation of the terminal format: a Claude Code terminal theme colours accent, text and status only; it has **no page background**.
Curated themes therefore take their surfaces from each palette's published background colours (Nord, Dracula, Catppuccin, GitHub,
Solarized, Rosé Pine, Tokyo Night, One Dark, Everforest, Gruvbox). A pasted terminal theme gets an automatically chosen background; the
user can edit it ("Copy & edit").

## Adding a curated theme

1. Pick a theme file (ccthemes, or any repository with a compatible licence). Check the licence; keep the attribution below up to date.
2. Add an entry to `website/lib/theme/catalog.ts`: `claude` → `accent`, `error` → `danger`, `success`, `warning`, `planMode` → `pro`,
   `text` → `text-primary`, plus the palette's background(s) as `surface-0` / `surface-2` (and `surface-1` when it has a sidebar shade).
   Combine a light and a dark file of the same palette into one theme with both variants.
3. Run `npm test`: every preset theme is checked for complete tokens, readable text in both modes, and green/red status hues.
4. Open Admin › Appearance and try it on a real screen (Enter Orders, a table, a status badge).

## Third-party notices

Curated colours come from **ccthemes** (https://github.com/livlign/ccthemes), used under the MIT licence:

```
$LIC
```

Palette background colours are the published values of the palettes named above.
