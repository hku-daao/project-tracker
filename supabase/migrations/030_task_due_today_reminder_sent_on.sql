-- At most one "due today" email batch per HK calendar day per task.
ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS due_today_reminder_sent_on date;

COMMENT ON COLUMN public.task.due_today_reminder_sent_on IS
  'HK calendar date when due-today reminder emails were last sent for this task.';
