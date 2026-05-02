# BPS Modernization: Order Entry UI/UX Specification

This document serves as the authoritative guideline for Cursor's LLM to generate the Order Entry Screen. It is optimized for high-speed, keyboard-centric data entry, mimicking the efficiency of legacy PowerBuilder/SQL Anywhere applications.

---

## 1. High-Speed Workflow Philosophy
The interface must facilitate a continuous data entry loop without requiring a mouse. 
**The "Gold Path" Loop:**
`Customer Search` → `Item Search` → `Quantity SLE` → `[Enter]` → `Item Search` (Repeat)

---

## 2. Control Definitions & Behavior

### SLE (Single Line Entry)
- **Web Equivalent:** `<input type="text">` or `<input type="number">`.
- **Focus Rule:** Must **Auto-Select** all text on focus for immediate overwrite.
- **Keypad Support:** The `Enter` key on the numeric keypad must commit the value and advance focus.

### EntityComboBox (Searchable Selection)
- **Component:** `EntityComboBox`.
- **Behavior:** Typing filters the list; `Arrow Keys` navigate; `Enter` selects.
- **Handoff:** Once a selection is made via `Enter`, focus must move immediately to the next logical control.

### Display Only
- **Web Equivalent:** Styled `<div>` or `<input readonly tabindex="-1">`.
- **Rule:** These fields MUST be skipped in the `Tab` or `Enter` sequence to prevent workflow interruption.

---

## 3. Explicit Focus Management (The "Deterministic" Flow)

Focus must never be "lost." Every action has a defined destination.

| Action / Trigger | Next Focus Target |
| :--- | :--- |
| **Initial Page Load** | `Customer Search` |
| **Select Customer + [Enter]** | `Item Search` |
| **Select Item + [Enter]** | `Quantity SLE` |
| **[Enter] in Quantity SLE** | `Item Search` (Clear the search box) |
| **[Tab] in Quantity SLE** | **Grid:** `Quantity` cell of the active row |
| **[Enter] in Grid `Discount`** | `Item Search` |

---

## 4. Visual Layout (Refining the 3-Row Pattern)

Based on the legacy BPS screenshot, the layout should be a compact, vertical stack of horizontal rows:

- **Row 1 (Order Header):** - `Customer` (EntityComboBox)
    - `Prdctn Date` (Date SLE)
    - `Prdctn Time` (LOV: AM/PM/Special)
    - `Invoice No` (SLE)
-     - `Credit` (Display Only)
    - `Dlvry $` (SLE)
    - `Ttl Order` (Display Only - Bold/Yellow Background)
- **Row 2 (The Action Loop):**
    - `Item` (EntityComboBox - Wide)
    - `Qty` (SLE - Large Font)
- **Row 3 (The Grid):** - Full-width data grid.
    - Columns: `Item No`, `Item Description`, `SL`, `W`, `CV`, `CS`, `Qty`, `Price`, `Discnt`, `Total`.
    - **Active Row Highlight:** The row corresponding to the current `Item Search` must be visually distinct.

---

## 5. Logic & State Rules

### Item Entry Logic
1. When an item is selected in `Item Search`:
   - If it exists in the grid: Scroll to and highlight row; pull quantity into `Quantity SLE`.
   - If new: Add row to bottom; set `Quantity SLE` to blank; focus `Quantity SLE`.
2. Upon `[Enter]` in `Quantity SLE`:
   - Update grid row, recalculate line `Total` and `Ttl Order`, clear `Item Search`, and return focus to `Item Search`.

### Grid Interaction
- The grid is for overrides. Only `Qty`, `Price`, and `Discnt` columns are editable.
- Navigating the grid should feel like a spreadsheet (Arrow keys, Enter to move right).

---

## 6. Implementation Notes for Cursor
- **Styling:** Use compact padding (Tailwind `p-1` or `p-2`) to fit more data on screen.
- **Performance:** Calculations must be client-side and instantaneous.
- **Validation:** Use non-modal alerts (e.g., a red border or status text) to signal errors without stopping the user's hands.
