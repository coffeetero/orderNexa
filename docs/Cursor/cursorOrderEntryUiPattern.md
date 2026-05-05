# cursorOrderEntryUiPattern

Use this document as the authoritative UI/UX pattern for BPS order entry screens.

This pattern is optimized for fast, heads-down order entry where the user primarily works from the keyboard and numeric keypad.

---

## Purpose

Order entry pages must prioritize:

- Fast keyboard-driven workflow
- Minimal mouse usage
- Numeric keypad efficiency
- Predictable focus movement
- Primary data entry outside the grid
- Optional grid editing only for overrides

This pattern applies to tenant/account order entry screens unless explicitly overridden.

---

## Terminology / Control Mapping

Use these mappings when generating UI components.

### SLE

Meaning:

- Single Line Entry

Web equivalent:

- Single-line input field
- Usually `<input type="text">`
- May use numeric validation where applicable

Use for:

- Quantity
- Price
- Discount
- Invoice Number
- Delivery Charges
- Customer / Location

Rules:

- Auto-select contents on focus where fast overwrite is expected
- Support Enter key and Tab workflow
- Avoid requiring mouse interaction

---

### EntityComboBox

Meaning:

- Searchable entity selector

Web equivalent:

- Searchable combo box / typeahead dropdown

Component:

- Use existing custom component: `EntityComboBox`

Use for:

- Customer Search
- Item Search
- Other large searchable entity lists

Rules:

- Must support keyboard typing
- Must support keyboard selection
- Must not require mouse interaction
- Must support focus handoff after selection

---

### LOV

Meaning:

- List of Values

Web equivalent:

- Dropdown select

Use for:

- Small fixed value lists

Example:

- Production Time:
  - AM
  - PM
  - SPECIAL 1

Rules:

- Default to first valid value unless specified otherwise
- Must support keyboard selection

---

### Display Only Field

Meaning:

- Read-only field

Web equivalent:

- Read-only input, disabled input, or styled text display

Use for:

- Credits
- Total Order
- Line Total
- Item Number
- Item Description

Rules:

- User cannot edit directly
- Must visually indicate read-only state
- Should still align visually with editable fields when placed in a form row

---

### Grid

Meaning:

- Data table containing order lines

Web equivalent:

- Editable data grid / table

Use for:

- Order items / order lines

Rules:

- Grid is not the primary entry mechanism
- Grid supports selection and optional inline overrides
- Grid must highlight the active/selected row
- Only explicitly editable columns should allow input

---

## Standard Order Entry Layout

The order entry page should be laid out in compact horizontal rows.

---

### Top Row

Left to right:

1. Customer Search
   - Control: EntityComboBox
   - Data source: all customers for selected tenant/account context
   - Tenant/account context comes from authenticated session/JWT/server context
   - Must support keyboard search and selection

2. Production Date
   - Control: single-line date input with calendar picker
   - Must support keyboard input
   - Default: tomorrow's date

3. Production Time
   - Control: LOV/dropdown
   - Values:
     - AM
     - PM
     - SPECIAL 1
   - Default: first value

4. Invoice Number
   - Control: SLE
   - Single-line text input

---

### Second Row

Left to right:

1. Customer / Location
   - Control: SLE

2. Credits
   - Control: Display Only

3. Delivery Charges
   - Control: SLE
   - Numeric entry expected

4. Total Order
   - Control: Display Only
   - Recalculated from order lines, credits, and delivery charges

---

### Third Row

Left to right:

1. Item Search
   - Control: EntityComboBox
   - Data source: all active/selectable items
   - Must support fast keyboard search and selection

2. Quantity SLE
   - Control: SLE
   - Numeric entry
   - Primary quantity entry point for selected item

3. Order Items Grid
   - Control: Grid
   - Displays order lines

Recommended grid columns:

- Item Number
  - Display Only

- Item Description
  - Display Only

- Quantity
  - Editable in grid for overrides

- Price
  - Editable in grid for overrides

- Discount
  - Editable in grid for overrides

- Total
  - Display Only

---

## Initialization Rules

On page load:

1. Load customer list for selected tenant/account context.
2. Load item list.
3. Default Production Date to tomorrow.
4. Default Production Time to first LOV value.
5. Initialize order lines grid as empty unless editing an existing order.
6. Set focus to Customer Search.
7. Do not require mouse interaction to begin entering an order.

---

## Primary Data Entry Flow

Primary order entry happens through controls above the grid.

The normal flow is:

Customer Search
  → Item Search
  → Quantity SLE
  → Item Search
  → Quantity SLE
  → repeat

---

### Step 1: Page Entry

When the page opens:

- Focus must be on Customer Search.
- User can immediately type to search/select a customer.

---

### Step 2: Customer Selection

After the user selects a customer:

- Store selected customer in page state.
- Populate customer/location defaults if applicable.
- Move focus to Item Search.

---

### Step 3: Item Selection

After the user selects an item from Item Search:

If the item already exists in the order items grid:

- Select/highlight the existing row.
- Copy the current grid Quantity value into the Quantity SLE.
- Focus moves to Quantity SLE.
- Quantity SLE selects its entire content.

If the item does not exist in the grid:

- Add a new row to the bottom of the order items grid.
- Populate:
  - Item Number
  - Item Description
  - Default Price if available
  - Discount if applicable
- Set Quantity to `0`.
- Select/highlight the new row.
- Copy Quantity `0` into the Quantity SLE.
- Focus moves to Quantity SLE.
- Quantity SLE selects its entire content.

---

### Step 4: Quantity Entry

When Quantity SLE receives focus:

- Select the entire current value.
- User enters quantity, usually using numeric keypad.

On Enter:

- Validate quantity.
- Update Quantity on the selected grid row.
- Recalculate line total.
- Recalculate order total.
- Clear or reset Item Search as appropriate.
- Move focus back to Item Search.

---

## Grid Interaction Model

The grid is for visibility and overrides.

Primary entry should not require direct grid editing.

---

### Entering the Grid

From Quantity SLE:

- Press Tab.
- Focus moves into the selected grid row.
- Focus lands on the Quantity cell of the selected row.

This is the intentional path for override editing.

---

### Editable Grid Columns

Only these columns are editable unless explicitly changed:

1. Quantity
2. Price
3. Discount

All other columns are display-only by default.

---

### Grid Keyboard Navigation

Inside the selected grid row:

- Enter on Quantity cell:
  - Save/commit Quantity value
  - Move focus to Price cell

- Enter on Price cell:
  - Save/commit Price value
  - Move focus to Discount cell

- Enter on Discount cell:
  - Save/commit Discount value
  - Recalculate row total
  - Recalculate order total
  - Move focus back to Item Search

Escape behavior, if implemented:

- Cancel current cell edit
- Keep row selected
- Return focus to Item Search

---

## Keyboard Behavior Rules

Order entry must be keyboard-first.

### Enter Key

Use Enter to:

- Confirm combo box selection
- Commit SLE values
- Move to the next logical workflow step
- Commit grid cell overrides
- Return focus to Item Search after final editable grid cell

---

### Tab Key

Use Tab sparingly.

Primary purpose:

- Move from Quantity SLE into the selected grid row for overrides

Do not design the normal workflow to require repeated Tab navigation.

---

### Numeric Keypad

The numeric keypad should be efficient for:

- Quantity
- Price
- Discount
- Delivery Charges
- Invoice Number where numeric

Rules:

- Numeric fields should accept direct numeric keypad input.
- Enter key from numeric keypad should behave the same as Enter.
- Do not require mouse clicks between numeric entries.

---

## Focus Management Rules

Focus behavior must be deterministic.

Required focus flow:

1. Page load:
   - Customer Search

2. Customer selected:
   - Item Search

3. Item selected:
   - Quantity SLE

4. Quantity entered + Enter:
   - Item Search

5. Quantity SLE + Tab:
   - Grid Quantity cell for selected row

6. Grid last editable cell + Enter:
   - Item Search

Avoid unexpected focus jumps.

---

## Totals and Recalculation

Recalculate totals whenever any of the following changes:

- Quantity
- Price
- Discount
- Delivery Charges
- Credits
- Item added
- Item removed

Line total:

- Calculated from quantity, price, and discount.

Order total:

- Sum of line totals
- Plus delivery charges
- Minus credits

Do not allow display-only totals to be manually edited.

---

## Error Handling and Validation

Validation should support fast correction.

Rules:

- Validate numeric fields on Enter or blur.
- Do not interrupt fast entry with excessive modal dialogs.
- Prefer inline error messages or field-level indicators.
- Keep focus on invalid field until corrected.
- Do not advance workflow on invalid entry.

---

## Performance Rules

Order entry must feel immediate.

Rules:

- Customer and item lists should be loaded before active entry begins when data size is reasonable.
- EntityComboBox filtering should happen client-side for reasonable list sizes.
- Avoid database calls on every keystroke.
- For very large customer/item lists, use server-side search with debounce.
- Grid updates should be local and immediate.
- Save to server only when user explicitly saves or workflow requires persistence.

---

## API / Save Pattern

Do not call Supabase RPC directly from the client component.

Save flow:

Client Order Entry UI
  → API route
  → Supabase RPC
  → RLS

Example endpoint pattern:

- POST `/api/orders/save`

The API route should:

- Validate payload
- Use authenticated server context
- Call order save RPC
- Return consistent JSON response

The UI should only know the API endpoint, not the RPC name.

---

## Do

- Optimize for speed.
- Use EntityComboBox for large searchable lists.
- Use SLE for fast single-value entry.
- Use Enter as the main workflow key.
- Keep the grid visible but secondary.
- Highlight the selected grid row.
- Auto-select text on focus for overwrite-friendly fields.
- Keep layout compact and predictable.

---

## Do Not

- Do not make grid editing the primary entry method.
- Do not require mouse interaction for normal entry.
- Do not require repeated Tab navigation.
- Do not introduce unnecessary dialogs.
- Do not call RPCs directly from client components.
- Do not invent new controls when existing patterns apply.
- Do not hide the selected grid row state.
- Do not allow editing display-only fields.

---

## Summary

The order entry page is a keyboard-first operational screen.

The core loop is:

Customer Search
  → Item Search
  → Quantity SLE
  → Enter
  → Item Search

The grid is used to display selected items and allow optional overrides, but normal order entry must happen through the controls above the grid.
