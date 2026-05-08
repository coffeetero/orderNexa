# Order Entry And Tenant Sequences - May 2026

Durable decisions from the May 8, 2026 work session:

- Existing order retrieval and updates use internal `order_id`. Display `order_number` is tenant-formatted and should not be used as the edit identity.
- If a customer is already selected, selecting an existing order from the popup preserves the selected customer. The loaded order supplies Location/Event and order lines.
- If customer is blank and a future search button is used, selecting an existing order may populate customer from that order.
- Location customers are order-entry helpers. They default Location/Event, while saved orders belong to the immediate parent customer and preserve a customer-name snapshot.
- New orders show `New Order` in the UI; the database allocates the real order number only during save.
- Tenant document numbers are stored in `fnd_tenant_sequences` by `(tenant_id, sequence_name)`, allowing independent row locks for order, invoice, customer, and future sequences.
- `fnd_tenant_sequence_next` locks the sequence row and returns the formatted next value.
- Sequence masks support `[YY]`, `[YYYY]`, `[YYYYMM]`, `[YYYYMMDD]`, `[YYYY-MM]`, `[YYYY-MM-DD]`, and grouped `#` placeholders.
- `#` placeholders fill right-to-left across groups. Short values are zero-filled; overflow expands the leftmost group. Examples: `####-####` + `1151044` -> `0115-1044`; `#-####` + `1151044` -> `115-1044`.
- Alpine Bakery uses order mask `####-####`; its sequence is seeded from legacy `max(ordr_no)` with `next_value = max(ordr_no) + 1`.
- `bps_dev` has table/function grants for `fnd_tenant_sequences`, but direct row visibility may still be blocked by RLS because the current policy depends on Supabase JWT app metadata.