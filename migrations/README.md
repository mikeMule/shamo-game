# SHAMO Supabase migrations

Run these in **Supabase SQL Editor** in order. Order matters — dependencies (tables, enums, functions) are defined top to bottom.

## First migration (full schema)

| File | Description |
|------|-------------|
| `001_shamo_complete_schema.sql` | Full SHAMO schema: enums, tables, triggers, views, RLS, seed questions |

### How to run

1. Open your Supabase project → **SQL Editor**.
2. Paste the contents of `001_shamo_complete_schema.sql` (or use “Open file” if available).
3. Click **Run**. Execute the whole file in one go.

If you already created the database with the Supabase dashboard or other scripts, you may need to adjust or split this migration (e.g. skip existing objects or add `IF NOT EXISTS` where appropriate).

## Future migrations

Add new files with a numeric prefix, e.g.:

- `002_add_xyz_table.sql`
- `003_alter_users_add_field.sql`

Run them in order after the first migration.
