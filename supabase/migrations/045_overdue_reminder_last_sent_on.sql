-- Daily overdue reminder emails (HK calendar): at most one send per recipient per HK day per task/sub-task.

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS creator_overdue_reminder_last_sent_on date;

COMMENT ON COLUMN public.task.creator_overdue_reminder_last_sent_on IS
  'HK calendar date when CreatorOverdueReminder was last sent for this task.';

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS assignee_01_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_02_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_03_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_04_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_05_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_06_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_07_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_08_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_09_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_10_overdue_reminder_last_sent_on date;

COMMENT ON COLUMN public.task.assignee_01_overdue_reminder_last_sent_on IS
  'HK calendar date when AssigneeOverdueReminder was last sent to assignee_01 for this task.';

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS subtask_creator_overdue_reminder_last_sent_on date;

COMMENT ON COLUMN public.subtask.subtask_creator_overdue_reminder_last_sent_on IS
  'HK calendar date when Subtask_CreatorOverdueReminder was last sent for this sub-task.';

ALTER TABLE public.subtask
  ADD COLUMN IF NOT EXISTS assignee_01_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_02_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_03_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_04_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_05_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_06_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_07_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_08_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_09_overdue_reminder_last_sent_on date,
  ADD COLUMN IF NOT EXISTS assignee_10_overdue_reminder_last_sent_on date;

COMMENT ON COLUMN public.subtask.assignee_01_overdue_reminder_last_sent_on IS
  'HK calendar date when Subtask_AssigneeOverdueReminder was last sent to assignee_01 for this sub-task.';
