-- Unified [is_overdue_row] from stored columns only: task rows use public.task.overdue;
-- sub-task rows use public.subtask.overdue only (each view row is independent for filtering).
--
-- Postgres forbids renaming view columns via CREATE OR REPLACE (42P16); drop and recreate.
DROP VIEW IF EXISTS public.overview_tasks_subtasks_flat CASCADE;

CREATE VIEW public.overview_tasks_subtasks_flat AS
SELECT
  'task'::text AS row_kind,
  t.id AS parent_task_id,
  NULL::uuid AS subtask_id,
  CASE
    WHEN lower(trim(coalesce(t.status::text, ''))) IN ('deleted', 'delete') THEN 'deleted'
    WHEN lower(trim(coalesce(t.status::text, ''))) IN ('completed', 'complete') THEN 'completed'
    ELSE 'incomplete'
  END AS row_status,
  CASE
    WHEN COALESCE(t.overdue, 'No')::text = 'Yes' THEN 'Yes'
    ELSE 'No'
  END AS is_overdue_row
FROM public.task t

UNION ALL

SELECT
  'subtask'::text AS row_kind,
  s.task_id AS parent_task_id,
  s.id AS subtask_id,
  CASE
    WHEN lower(trim(coalesce(s.status::text, ''))) IN ('deleted', 'delete') THEN 'deleted'
    WHEN lower(trim(coalesce(s.status::text, ''))) IN ('completed', 'complete') THEN 'completed'
    ELSE 'incomplete'
  END AS row_status,
  CASE
    WHEN COALESCE(s.overdue, 'No')::text = 'Yes' THEN 'Yes'
    ELSE 'No'
  END AS is_overdue_row
FROM public.subtask s;

COMMENT ON VIEW public.overview_tasks_subtasks_flat IS
  'Flat task/sub-task rows for filters; is_overdue_row copies only that row''s task.overdue or subtask.overdue.';

COMMENT ON COLUMN public.overview_tasks_subtasks_flat.is_overdue_row IS
  'Yes | No: task rows from task.overdue; sub-task rows from subtask.overdue (no cross-row logic).';

GRANT SELECT ON public.overview_tasks_subtasks_flat TO anon, authenticated;
