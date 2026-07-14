# Skipped migrations (on-prem)

These files were moved out of `migrations/` because they fail or duplicate on a fresh local Postgres:

| File | Reason |
|------|--------|
| `011_import_excel_data.sql` | UTF-16 encoding; superseded by `016_import_user_level_tables_v1.sql` |
| `012_import_excel_data_exact_match.sql` | SQL syntax errors; superseded by `016` |
| `013_merge_loginid_to_email_and_set_app_id.sql` | Needs `loginID` columns from `012` |
| `018_team_members_admin_team_three.sql` | Hardcoded cloud Supabase UUIDs |

Added for on-prem: `017_singular_task_table.sql` (was missing from cloud history).
