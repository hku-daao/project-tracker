-- Assignee 80% urgent sub-task emails: at most one HK batch per day (mirrors task.urgent_reminder_last_sent_on).

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS assignee_urgent_reminder_last_sent_on date;

COMMENT ON COLUMN public.subtask.assignee_urgent_reminder_last_sent_on IS
  'HK calendar date of last assignee 80% urgent email batch for this sub-task.';
