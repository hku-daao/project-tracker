-- Creator due-today (HK calendar) sub-task emails: one send per HK day when today = due_date.

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS subtask_creator_due_today_reminder_sent_on date;

COMMENT ON COLUMN public.subtask.subtask_creator_due_today_reminder_sent_on IS
  'HK calendar date when sub-task creator due-today email was last sent (at most one per HK day).';
