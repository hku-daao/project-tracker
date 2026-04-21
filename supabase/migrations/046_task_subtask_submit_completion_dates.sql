-- PIC submit / completion audit (HK +08:00 values written from app as timestamptz ISO strings).
alter table public.task
  add column if not exists submit_date timestamptz;

alter table public.task
  add column if not exists completion_date timestamptz;

alter table public.subtask
  add column if not exists submit_date timestamptz;

alter table public.subtask
  add column if not exists completion_date timestamptz;

comment on column public.task.submit_date is 'When PIC clicked Submit (app writes HK +08:00 instant).';
comment on column public.task.completion_date is 'When status became Completed; product rule: equals submit_date at accept.';
comment on column public.subtask.submit_date is 'When assignee clicked Submit (app writes HK +08:00 instant).';
comment on column public.subtask.completion_date is 'When status became Completed; product rule: equals submit_date at accept.';
