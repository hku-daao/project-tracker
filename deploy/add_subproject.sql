-- Optional subproject layer between project and task.
-- Hierarchy: project -> subproject -> task -> subtask.
-- task.project_id stays the project uuid. task.subproject_id is nullable.
-- Safe to run more than once.

create table if not exists public.subproject (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.project (id),
  name text not null,
  description text,
  status text not null default 'Not started',
  pause_status text not null default 'Not Paused',
  start_date date,
  end_date date,
  sort_order integer not null default 0,
  create_by uuid references public.staff (id),
  create_date timestamptz,
  update_by uuid references public.staff (id),
  update_date timestamptz
);

comment on table public.subproject is
  'Optional grouping under a project. status Deleted = removed from UI.';

comment on column public.subproject.project_id is
  'Parent project. A subproject belongs to exactly one project.';

alter table public.task
  add column if not exists subproject_id uuid references public.subproject (id);

comment on column public.task.subproject_id is
  'Optional subproject under task.project_id. Null = task sits directly under the project.';

create index if not exists idx_subproject_project_id
  on public.subproject (project_id);

create index if not exists idx_task_subproject_id
  on public.task (subproject_id);

create or replace function public.task_subproject_matches_project()
returns trigger
language plpgsql
as $$
declare
  sp_project_id uuid;
begin
  if new.subproject_id is null then
    return new;
  end if;
  if new.project_id is null then
    raise exception 'task.subproject_id requires task.project_id';
  end if;
  select s.project_id into sp_project_id
  from public.subproject s
  where s.id = new.subproject_id;
  if sp_project_id is null then
    raise exception 'task.subproject_id does not exist';
  end if;
  if sp_project_id <> new.project_id then
    raise exception 'task.project_id must match subproject.project_id';
  end if;
  return new;
end;
$$;

drop trigger if exists task_subproject_matches_project on public.task;
create trigger task_subproject_matches_project
  before insert or update of project_id, subproject_id
  on public.task
  for each row
  execute function public.task_subproject_matches_project();

alter table public.subproject enable row level security;

drop policy if exists subproject_anon_all on public.subproject;
create policy subproject_anon_all
  on public.subproject
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists subproject_authenticated_all on public.subproject;
create policy subproject_authenticated_all
  on public.subproject
  for all
  to authenticated
  using (true)
  with check (true);

grant select, insert, update, delete
  on public.subproject
  to anon, authenticated;

notify pgrst, 'reload schema';
