-- On-prem: missing from cloud migration history; required before 019_task_table_status_string.sql.
-- Singular task table used by Flutter (`task_name`, `assignee_01`..`assignee_10`).

CREATE TABLE IF NOT EXISTS public.task (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_name text NOT NULL,
  description text,
  priority text,
  start_date timestamptz,
  due_date timestamptz,
  active integer NOT NULL DEFAULT 1,
  team_id uuid,
  assignee_01 uuid,
  assignee_02 uuid,
  assignee_03 uuid,
  assignee_04 uuid,
  assignee_05 uuid,
  assignee_06 uuid,
  assignee_07 uuid,
  assignee_08 uuid,
  assignee_09 uuid,
  assignee_10 uuid,
  last_updated timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.task IS 'Singular task rows (Asana-style); legacy plural `tasks` is separate.';
