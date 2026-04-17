-- Reason when start→due span exceeds policy (Standard: 3 working days; Urgent: 1).
ALTER TABLE public.task ADD COLUMN IF NOT EXISTS change_due_reason text;
ALTER TABLE public.subtask ADD COLUMN IF NOT EXISTS change_due_reason text;

COMMENT ON COLUMN public.task.change_due_reason IS
  'Required explanation when due date is after start + allowed working days for priority.';
COMMENT ON COLUMN public.subtask.change_due_reason IS
  'Required explanation when due date is after start + allowed working days for priority.';
