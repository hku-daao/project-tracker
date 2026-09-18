-- Optional free-text when commencement_status is 'To be commenced'.
-- Safe to run more than once.

alter table public.task
  add column if not exists commencement_note text;

alter table public.subtask
  add column if not exists commencement_note text;

comment on column public.task.commencement_note is
  'Optional note when commencement_status is To be commenced.';

comment on column public.subtask.commencement_note is
  'Optional note when commencement_status is To be commenced.';

notify pgrst, 'reload schema';
