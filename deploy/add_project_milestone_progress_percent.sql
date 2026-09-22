-- Share of project progress for each Active milestone.
-- App enforces that visible milestones sum to 100%.
-- Safe to run more than once.

alter table public.project_milestone
  add column if not exists progress_percent integer not null default 0;

alter table public.project_milestone
  drop constraint if exists project_milestone_progress_percent_check;

alter table public.project_milestone
  add constraint project_milestone_progress_percent_check
  check (progress_percent >= 0 and progress_percent <= 100);

comment on column public.project_milestone.progress_percent is
  'Percent of overall project progress this Active milestone represents.';

notify pgrst, 'reload schema';
