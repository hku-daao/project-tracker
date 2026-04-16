-- Sub-task assignee due-today (HK calendar): one batch per sub-task per HK day.

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS subtask_assignee_due_today_reminder_sent_on date;

COMMENT ON COLUMN public.subtask.subtask_assignee_due_today_reminder_sent_on IS
  'HK calendar date when assignee due-today emails were last sent for this sub-task.';
