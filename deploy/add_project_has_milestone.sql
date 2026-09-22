-- Optional project milestones.
-- Creator sets project.has_milestone = true to show the milestone list.
-- Each visible step is a public.project_milestone row with status = 'Active'.
--
-- Remove a milestone (4 -> 3):
--   do not DELETE the row
--   set status = 'Deleted' (soft delete)
--   compact sort_order on remaining Active rows to 0, 1, 2, ...
-- The app only lists Active rows, ordered by sort_order, then create_date.
-- Turning has_milestone off hides the list but keeps Active rows, so turning
-- it back on restores them.
--
-- Safe to run more than once.

alter table public.project
  add column if not exists has_milestone boolean not null default false;

comment on column public.project.has_milestone is
  'When true, the project creator opted in to optional milestone steps.';

comment on table public.project_milestone is
  'Optional project steps. status Active = visible; Deleted = removed from UI.';

notify pgrst, 'reload schema';
