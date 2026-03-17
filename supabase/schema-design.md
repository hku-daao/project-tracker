# Supabase Schema Design – Project Tracker (DAAO Apps)

This document describes the table schema for storing **staff data** and **task data** in the Supabase project **"DAAO Apps"**, aligned with the Project Tracker app models.

---

## Entity relationship overview

```
staff (people)
  └── team_members (staff ↔ teams, with role: director | officer)

teams
  └── initiatives (high-level work)
  │     ├── initiative_directors (many-to-many)
  │     ├── sub_tasks
  │     └── comments (entity_type = 'initiative')
  └── tasks (low-level work)
        ├── task_assignees (many-to-many)
        └── comments (entity_type = 'task')

Audit:
  deleted_sub_tasks, deleted_tasks
```

---

## 1. Staff data

### `staff`

| Column       | Type         | Constraints        | Description                    |
|-------------|--------------|--------------------|--------------------------------|
| id          | uuid         | PK, default gen_random_uuid() | Unique staff ID (maps to Assignee.id) |
| name        | text         | NOT NULL           | Display name                   |
| email       | text         |                    | Optional email                 |
| created_at  | timestamptz  | DEFAULT now()      | Record creation time           |

- One row per person (Director or Responsible Officer).
- Use `id` as the stable reference in the app (e.g. store UUID in app, or keep existing string IDs and add a `legacy_id` text column for migration).

### `teams`

| Column      | Type         | Constraints        | Description        |
|------------|--------------|--------------------|--------------------|
| id         | uuid         | PK, default gen_random_uuid() | Unique team ID     |
| name       | text         | NOT NULL           | Team name (e.g. Alumni Team) |
| created_at | timestamptz  | DEFAULT now()      | Record creation    |

### `team_members`

| Column    | Type   | Constraints                    | Description                          |
|----------|--------|--------------------------------|--------------------------------------|
| team_id  | uuid   | PK, FK → teams.id ON DELETE CASCADE | Team                                 |
| staff_id | uuid   | PK, FK → staff.id ON DELETE CASCADE  | Staff member                         |
| role     | text   | NOT NULL, CHECK (role IN ('director', 'officer')) | Role in this team   |

- One row per (team, staff) with a single role.
- Replaces the previous `directorIds` and `officerIds` arrays on Team.

---

## 2. Task data (high-level: initiatives)

### `initiatives`

| Column       | Type        | Constraints        | Description                          |
|-------------|-------------|--------------------|--------------------------------------|
| id          | uuid        | PK, default gen_random_uuid() | Initiative ID                 |
| team_id     | uuid        | NOT NULL, FK → teams.id       | Owning team                    |
| name        | text        | NOT NULL           | Initiative name (Task field in UI)   |
| description | text        | DEFAULT ''         | Description                          |
| priority    | smallint    | NOT NULL, CHECK (priority IN (1, 2)) | 1 = Standard, 2 = Urgent     |
| start_date  | date        |                    | Start date                           |
| end_date    | date        |                    | Due date                             |
| created_at  | timestamptz | DEFAULT now()      | Creation time                        |

### `initiative_directors`

| Column        | Type | Constraints                         | Description        |
|---------------|------|-------------------------------------|--------------------|
| initiative_id | uuid | PK, FK → initiatives.id ON DELETE CASCADE | Initiative  |
| staff_id      | uuid | PK, FK → staff.id ON DELETE CASCADE       | Director    |

- Many-to-many: initiative ↔ directors (replaces `directorIds` list).

### `sub_tasks`

| Column        | Type    | Constraints                         | Description              |
|---------------|---------|-------------------------------------|--------------------------|
| id            | uuid    | PK, default gen_random_uuid()       | Sub-task ID              |
| initiative_id | uuid    | NOT NULL, FK → initiatives.id ON DELETE CASCADE | Parent initiative |
| label         | text    | NOT NULL           | Sub-task name            |
| is_completed  | boolean | DEFAULT false      | Completion flag          |

- Initiative progress = (count of completed sub_tasks) / (count of sub_tasks).

---

## 3. Task data (low-level: tasks)

### `tasks`

| Column          | Type        | Constraints        | Description                          |
|-----------------|-------------|--------------------|--------------------------------------|
| id              | uuid        | PK, default gen_random_uuid() | Task ID                       |
| team_id         | uuid        | FK → teams.id      | Owning team (nullable for legacy)    |
| name            | text        | NOT NULL           | Task name                            |
| description     | text        | DEFAULT ''         | Description                          |
| priority        | smallint    | NOT NULL, CHECK (priority IN (1, 2)) | 1 = Standard, 2 = Urgent     |
| start_date      | date        |                    | Start date                           |
| end_date        | date        |                    | Due date                             |
| status          | text        | NOT NULL, DEFAULT 'todo', CHECK (status IN ('todo', 'in_progress', 'done')) | Not started / In progress / Completed |
| progress_percent | smallint   | DEFAULT 0          | 0–100 (optional)                     |
| created_at      | timestamptz | DEFAULT now()      | Creation time                        |

### `task_assignees`

| Column   | Type | Constraints                         | Description        |
|----------|------|-------------------------------------|--------------------|
| task_id  | uuid | PK, FK → tasks.id ON DELETE CASCADE | Task               |
| staff_id | uuid | PK, FK → staff.id ON DELETE CASCADE  | Responsible Officer |

- Many-to-many: task ↔ assignees (replaces `assigneeIds` list).

---

## 4. Comments (initiatives and tasks)

### `comments`

| Column      | Type        | Constraints        | Description                          |
|-------------|-------------|--------------------|--------------------------------------|
| id          | uuid        | PK, default gen_random_uuid() | Comment ID                    |
| entity_type | text        | NOT NULL, CHECK (entity_type IN ('initiative', 'task')) | Initiative or task |
| entity_id   | uuid        | NOT NULL           | initiatives.id or tasks.id           |
| author_id   | uuid        | NOT NULL, FK → staff.id | Commenter                       |
| body        | text        | NOT NULL           | Comment text                        |
| created_at  | timestamptz | DEFAULT now()      | Creation time                       |

- One table for both initiative and task comments; filter by `(entity_type, entity_id)`.

---

## 5. Audit (deleted records)

### `deleted_sub_tasks`

| Column        | Type        | Constraints | Description                |
|---------------|-------------|-------------|----------------------------|
| id            | uuid        | PK, default gen_random_uuid() | Audit record ID      |
| initiative_id | uuid        | NOT NULL    | Parent initiative (for grouping) |
| sub_task_label| text        | NOT NULL    | Label at time of delete    |
| is_completed  | boolean     |             | Completion at delete       |
| deleted_at    | timestamptz | DEFAULT now() | When deleted           |
| deleted_by    | text        | NOT NULL    | Name (or staff_id) of who deleted |

### `deleted_tasks`

| Column     | Type        | Constraints | Description                    |
|------------|-------------|-------------|--------------------------------|
| id         | uuid        | PK, default gen_random_uuid() | Audit record ID          |
| task_id    | uuid        | NOT NULL    | Original task id (for reference) |
| task_name  | text        | NOT NULL    | Name at time of delete        |
| team_id    | uuid        |             | Team at time of delete        |
| assignee_ids| uuid[]     |             | Staff IDs assigned at delete  |
| deleted_at | timestamptz | DEFAULT now() | When deleted               |
| deleted_by | text        | NOT NULL    | Name (or staff_id) of who deleted |

- Use for “Deleted sub-tasks (audit)” and “Deleted tasks (audit)” in the app.

---

## 6. Indexes (recommended)

- `team_members`: index on `staff_id` (list teams for a person).
- `initiative_directors`: index on `staff_id`.
- `initiatives`: index on `team_id`, `created_at`.
- `sub_tasks`: index on `initiative_id`.
- `tasks`: index on `team_id`, `status`, `created_at`.
- `task_assignees`: index on `staff_id` (list tasks for a person).
- `comments`: index on `(entity_type, entity_id)`, `created_at`.
- `deleted_sub_tasks`: index on `initiative_id`, `deleted_at`.
- `deleted_tasks`: index on `team_id`, `deleted_at`; consider index on `assignee_ids` (GIN if using array) if you often filter by assignee.

---

## 7. Row Level Security (RLS)

- Enable RLS on all tables.
- Define policies per role (e.g. Professor, Director, Responsible Officer) so that:
  - Staff and teams: readable by authenticated users; writable by admins.
  - Initiatives/tasks/sub_tasks/comments: readable by assigned directors/officers and professors; writable by same (or as per your rules).
  - Deleted_*: read-only for audit; no delete/update.

You can add policies in a follow-up migration after the schema is applied.

---

## 8. Data extraction (queries)

- **Staff by team:**  
  `team_members` joined with `staff` and `teams`, filter by `team_id` and optionally `role`.
- **Initiatives for a team:**  
  `initiatives` where `team_id = ?`, join `initiative_directors` + `staff` for director names.
- **Initiative progress:**  
  Count `sub_tasks` where `initiative_id = ?` and `is_completed = true` vs total count.
- **Tasks for a team:**  
  `tasks` where `team_id = ?`, join `task_assignees` + `staff` for assignee names.
- **Tasks for a staff (My Tasks):**  
  `task_assignees` where `staff_id = ?` join `tasks`.
- **Comments for an initiative or task:**  
  `comments` where `entity_type = ?` and `entity_id = ?` order by `created_at`.
- **Deleted sub-tasks for an initiative:**  
  `deleted_sub_tasks` where `initiative_id = ?` order by `deleted_at desc`.
- **Deleted tasks for team or assignee:**  
  `deleted_tasks` where `team_id = ?` (or filter by `assignee_ids` containing a given `staff_id`) order by `deleted_at desc`.

---

## Next steps

1. Create the project “DAAO Apps” in Supabase (if not already created).
2. Run the migration in `supabase/migrations/001_initial_schema.sql` (see below) in the SQL Editor or via Supabase CLI.
3. Optionally seed `staff` and `teams` (and `team_members`) from existing app data.
4. Integrate the Flutter app with Supabase (supabase_flutter) and switch from in-memory state to these tables.
5. Add RLS policies and, if needed, auth (e.g. Supabase Auth) and map auth users to `staff.id`.
