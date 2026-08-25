alter table public.task
  add column if not exists commencement_status text not null default 'In progress';

alter table public.subtask
  add column if not exists commencement_status text not null default 'In progress';

update public.task
set
  commencement_status = 'To be commenced',
  status = 'Incomplete'
where lower(trim(status)) = 'to be commenced';

update public.subtask
set
  commencement_status = 'To be commenced',
  status = 'Incomplete'
where lower(trim(status)) = 'to be commenced';

alter table public.task
  drop constraint if exists task_status_check;

alter table public.task
  add constraint task_status_check
  check (status = any (array['Incomplete', 'Completed', 'Deleted']));

alter table public.subtask
  drop constraint if exists subtask_status_check;

alter table public.subtask
  add constraint subtask_status_check
  check (status = any (array['Incomplete', 'Completed', 'Deleted']));

alter table public.task
  drop constraint if exists task_commencement_status_check;

alter table public.task
  add constraint task_commencement_status_check
  check (commencement_status = any (array['In progress', 'To be commenced']));

alter table public.subtask
  drop constraint if exists subtask_commencement_status_check;

alter table public.subtask
  add constraint subtask_commencement_status_check
  check (commencement_status = any (array['In progress', 'To be commenced']));

notify pgrst, 'reload schema';
