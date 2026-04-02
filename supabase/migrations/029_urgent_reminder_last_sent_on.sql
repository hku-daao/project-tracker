-- Daily urgent emails: at most one batch per HK calendar day per task.
ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS urgent_reminder_last_sent_on date;

COMMENT ON COLUMN public.task.urgent_reminder_last_sent_on IS
  'HK calendar date when urgent reminder emails were last sent for this task.';

COMMENT ON COLUMN public.task.urgent_reminder_sent IS
  'True while the task is in the daily urgent window; set false after the due calendar date passes.';
