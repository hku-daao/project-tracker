-- Adds [is_overdue] to overview_tasks_subtasks_flat (HK calendar vs due_date; aligns with task.overdue / subtask.overdue triggers).

CREATE OR REPLACE VIEW public.overview_tasks_subtasks_flat AS
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
    WHEN lower(trim(coalesce(t.status::text, ''))) IN ('completed', 'complete', 'deleted', 'delete')
      OR t.due_date IS NULL THEN 'No'
    WHEN t.due_date < (current_timestamp AT TIME ZONE 'Asia/Hong_Kong')::date THEN 'Yes'
    ELSE 'No'
  END AS is_overdue
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
    WHEN lower(trim(coalesce(s.status::text, ''))) IN ('completed', 'complete', 'deleted', 'delete')
      OR s.due_date IS NULL THEN 'No'
    WHEN s.due_date < (current_timestamp AT TIME ZONE 'Asia/Hong_Kong')::date THEN 'Yes'
    ELSE 'No'
  END AS is_overdue
FROM public.subtask s;

COMMENT ON VIEW public.overview_tasks_subtasks_flat IS
  'Each Overview flat row: task (subtask_id NULL) or sub-task. row_status / is_overdue mirror singular tables; is_overdue uses HK calendar day vs due_date (same rules as task.overdue / subtask.overdue).';

COMMENT ON COLUMN public.overview_tasks_subtasks_flat.is_overdue IS
  'Yes | No: due_date strictly before Asia/Hong_Kong today; No when completed/deleted status or null due_date.';

GRANT SELECT ON public.overview_tasks_subtasks_flat TO anon, authenticated;
