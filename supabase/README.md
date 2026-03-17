# Supabase – DAAO Apps (Project Tracker)

This folder contains the schema design and migration for storing **staff** and **task** data in your Supabase project **"DAAO Apps"**.

## Quick start

1. **Create or select the project**  
   In [Supabase Dashboard](https://supabase.com/dashboard), create a project named **DAAO Apps** (or use an existing one).

2. **Run the migration**  
   - Open **SQL Editor** in the project.  
   - Copy the contents of `migrations/001_initial_schema.sql`.  
   - Run the script.  
   - All tables will be created in the `public` schema.

3. **Optional: Supabase CLI**  
   If you use the [Supabase CLI](https://supabase.com/docs/guides/cli):
   ```bash
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```

## Contents

| File | Purpose |
|------|--------|
| `schema-design.md` | Full table design, relationships, indexes, and data extraction notes |
| `migrations/001_initial_schema.sql` | SQL that creates all tables and indexes |

## Tables created

- **Staff:** `staff`, `teams`, `team_members`
- **Initiatives:** `initiatives`, `initiative_directors`, `sub_tasks`
- **Tasks:** `tasks`, `task_assignees`
- **Comments:** `comments` (for both initiatives and tasks)
- **Audit:** `deleted_sub_tasks`, `deleted_tasks`

## Next steps

- Seed `staff` and `teams` (and `team_members`) from your current app data.  
- Add [Row Level Security (RLS)](https://supabase.com/docs/guides/auth/row-level-security) and policies when you add authentication.  
- Integrate the Flutter app with [supabase_flutter](https://pub.dev/packages/supabase_flutter) and switch from in-memory state to these tables.
