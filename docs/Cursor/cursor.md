# orderNexa Project Guardrails

- **Schema Rules**: 
  - NEVER hardcode the `bps.` schema prefix in code. 
  - All app database objects reside in the `bps` schema.
  - The database schema must be handled via `SET search_path` or connection-level configuration to remain schema-agnostic.
- **Database Architecture**: 
  - Use `fnd_` for foundational tables, `ar_` for receivables, and `om_` for order-related tables.
  - Use `BigInt` for primary keys.
- **File Organization & DDL**:
  - **DDL Scripts**: Name files exactly as the object with the `.sql` extension. Place in `database/schema/`.
  - **Functions/Procedures**: Place all logic scripts in `database/functions/`.
  - **Seeding/Migrations**: Place all data-seeding and migration scripts in `database/migration/`.
- **SQL Standards**:
  - **Aliases**: Use `sql_table_aliases.md` conventions whenever writing SQL.
  - **Optimization**: DB procedures and functions should avoid variable bloat.
  - **Documentation**: Strive for clarity and add comments to explain logic.
- **Next.js Development**: Keep Supabase client calls schema-agnostic (e.g., use `.from('fnd_customers')`).
- **UI Focus**: Prioritize high-speed, keyboard-driven data entry (Tab/Enter/Arrows).