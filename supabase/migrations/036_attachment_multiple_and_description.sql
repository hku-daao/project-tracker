-- Multiple attachment rows per task/subtask; optional description per row.

ALTER TABLE public.attachment
  ADD COLUMN IF NOT EXISTS description text;

COMMENT ON COLUMN public.attachment.description IS 'Optional label for the hyperlink.';

DROP INDEX IF EXISTS attachment_task_id_uidx;

CREATE INDEX IF NOT EXISTS attachment_task_id_idx ON public.attachment (task_id);

ALTER TABLE public.subtask_attachment
  ADD COLUMN IF NOT EXISTS description text;

COMMENT ON COLUMN public.subtask_attachment.description IS 'Optional label for the hyperlink.';

DROP INDEX IF EXISTS subtask_attachment_subtask_uidx;

CREATE INDEX IF NOT EXISTS subtask_attachment_subtask_id_idx ON public.subtask_attachment (subtask_id);
