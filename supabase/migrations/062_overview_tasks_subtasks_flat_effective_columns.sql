-- Adds [effective_status] and [effective_submission]: per-row lifecycle status and submission
-- text for that row only (task row → task columns; sub-task row → sub-task columns).
-- Flutter filters use these columns so filters match each card row, not the parent task alone.

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
    WHEN lower(trim(coalesce(t.status::text, ''))) IN ('deleted', 'delete') THEN 'deleted'
    WHEN lower(trim(coalesce(t.status::text, ''))) IN ('completed', 'complete') THEN 'completed'
    ELSE 'incomplete'
  END AS effective_status,
  CASE
    WHEN COALESCE(t.overdue, 'No')::text = 'Yes' THEN 'Yes'
    ELSE 'No'
  END AS is_overdue_row,
  trim(coalesce(t.submission, ''))::text AS row_submission,
  trim(coalesce(t.submission, ''))::text AS effective_submission
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
    WHEN lower(trim(coalesce(s.status::text, ''))) IN ('deleted', 'delete') THEN 'deleted'
    WHEN lower(trim(coalesce(s.status::text, ''))) IN ('completed', 'complete') THEN 'completed'
    ELSE 'incomplete'
  END AS effective_status,
  CASE
    WHEN COALESCE(s.overdue, 'No')::text = 'Yes' THEN 'Yes'
    ELSE 'No'
  END AS is_overdue_row,
  trim(coalesce(s.submission, ''))::text AS row_submission,
  trim(coalesce(s.submission, ''))::text AS effective_submission
FROM public.subtask s;

COMMENT ON VIEW public.overview_tasks_subtasks_flat IS
  'Flat rows for Overview: task card + one row per sub-task. effective_status / effective_submission describe that row only (not the parent).';

COMMENT ON COLUMN public.overview_tasks_subtasks_flat.effective_status IS
  'Lifecycle: incomplete | completed | deleted — from task.status for task rows, subtask.status for sub-task rows.';

COMMENT ON COLUMN public.overview_tasks_subtasks_flat.effective_submission IS
  'Workflow submission for this row: task.submission or subtask.submission, trimmed.';

GRANT SELECT ON public.overview_tasks_subtasks_flat TO anon, authenticated;
