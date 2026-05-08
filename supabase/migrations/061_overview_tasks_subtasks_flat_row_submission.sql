-- Adds [row_submission] from task.submission / subtask.submission for Overview allowlist filters (case-insensitive via client .ilike).

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
  END AS is_overdue_row,
  trim(coalesce(t.submission, ''))::text AS row_submission
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
  END AS is_overdue_row,
  trim(coalesce(s.submission, ''))::text AS row_submission
FROM public.subtask s;

COMMENT ON VIEW public.overview_tasks_subtasks_flat IS
  'Flat task/sub-task rows; row_submission is trimmed task/subtask submission for filters.';

COMMENT ON COLUMN public.overview_tasks_subtasks_flat.row_submission IS
  'Trimmed submission text (empty string if null); filter with ilike for case-insensitive match.';

GRANT SELECT ON public.overview_tasks_subtasks_flat TO anon, authenticated;
