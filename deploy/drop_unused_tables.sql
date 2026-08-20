-- Confirmed no application-code references in project_tracker/project_tracker_test:
--   public.approved_complexity_review
--   public.unused_app_access_list_20260720
--   public.unused_app_list_20260720
--
-- Run on test and production after final DB-side confirmation.
-- No CASCADE is used, so PostgreSQL refuses the drop if any DB object still depends on a table.
begin;

drop table if exists public.approved_complexity_review;
drop table if exists public.unused_app_access_list_20260720;
drop table if exists public.unused_app_list_20260720;

notify pgrst, 'reload schema';

commit;
