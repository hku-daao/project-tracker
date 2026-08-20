-- Production-only.
-- Allow mkplam to view all active CPAO staff tasks by making mkplam the
-- supervisor of each active CPAO staff member in public.subordinate.
-- Existing subordinate rows are skipped.

-- Preview rows that would be inserted:
-- select 'mkplam' as supervisor_id, cpao_staff.subordinate_id
-- from (
--   select distinct lower(s.app_id) as subordinate_id
--   from public.staff s
--   join public.team t on lower(t.team_id) = lower(s.team_id)
--   join public.office o on lower(o.office_id) = lower(t.office_id)
--   where lower(o.office_id) = 'cpao'
--     and coalesce(s.active, true) = true
--     and lower(s.app_id) <> 'mkplam'
-- ) cpao_staff
-- where not exists (
--   select 1
--   from public.subordinate existing
--   where lower(existing.supervisor_id) = 'mkplam'
--     and lower(existing.subordinate_id) = cpao_staff.subordinate_id
-- )
-- order by cpao_staff.subordinate_id;

insert into public.subordinate (supervisor_id, subordinate_id)
select 'mkplam' as supervisor_id, cpao_staff.subordinate_id
from (
  select distinct lower(s.app_id) as subordinate_id
  from public.staff s
  join public.team t on lower(t.team_id) = lower(s.team_id)
  join public.office o on lower(o.office_id) = lower(t.office_id)
  where lower(o.office_id) = 'cpao'
    and coalesce(s.active, true) = true
    and lower(s.app_id) <> 'mkplam'
) cpao_staff
where not exists (
  select 1
  from public.subordinate existing
  where lower(existing.supervisor_id) = 'mkplam'
    and lower(existing.subordinate_id) = cpao_staff.subordinate_id
)
on conflict on constraint unique_supervisor_subordinate do nothing;

notify pgrst, 'reload schema';
