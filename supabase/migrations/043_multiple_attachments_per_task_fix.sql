-- Deployments that only ran 034 still have UNIQUE (task_id) on public.attachment,
-- which blocks more than one row per task. Migration 036 drops it; re-apply safely here.

DROP INDEX IF EXISTS public.attachment_task_id_uidx;

CREATE INDEX IF NOT EXISTS attachment_task_id_idx ON public.attachment (task_id);

-- Same pattern for sub-task attachments if 036 was skipped.
DROP INDEX IF EXISTS public.subtask_attachment_subtask_uidx;

CREATE INDEX IF NOT EXISTS subtask_attachment_subtask_id_idx ON public.subtask_attachment (subtask_id);
