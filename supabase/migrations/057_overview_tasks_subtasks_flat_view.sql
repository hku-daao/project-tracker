-- Flat overview rows: one row per parent task + one per sub-task, with unified [row_status]
-- for strict PostgREST filters (.eq / .inFilter). Values: incomplete | completed | deleted.

CREATE OR REPLACE VIEW public.overview_tasks_subtasks_flat AS
SELECT
  'task'::text AS row_kind,
  t.id AS parent_task_id,
  NULL::uuid AS subtask_id,
  CASE
    WHEN lower(trim(coalesce(t.status::text, ''))) IN ('deleted', 'delete') THEN 'deleted'
    WHEN lower(trim(coalesce(t.status::text, ''))) IN ('completed', 'complete') THEN 'completed'
    ELSE 'incomplete'
  END AS row_status
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
  END AS row_status
FROM public.subtask s;

COMMENT ON VIEW public.overview_tasks_subtasks_flat IS
  'Each list row in Overview “All tasks & sub-tasks”: task rows use subtask_id NULL; sub-task rows use parent_task_id + subtask_id. row_status mirrors task.status / subtask.status.';

COMMENT ON COLUMN public.overview_tasks_subtasks_flat.row_status IS
  'Normalized: incomplete | completed | deleted (matches app status chip keys).';

GRANT SELECT ON public.overview_tasks_subtasks_flat TO anon, authenticated;
