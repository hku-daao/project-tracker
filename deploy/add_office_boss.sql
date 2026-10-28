-- office_admin and performance_admin see every other staff member whose team
-- is in that office. super_admin sees every other staff member.
-- A new staff member is covered as soon as their team belongs to the office.
-- This does not write a row in public.subordinate.
-- Requires public.staff_admin. If that table is absent, the implied list is empty.

DO $$
BEGIN
  IF to_regclass('public.staff_admin') IS NULL THEN
    EXECUTE $view$
      CREATE OR REPLACE VIEW public.subordinate_implied AS
      SELECT NULL::text AS supervisor_id, NULL::text AS subordinate_id
      WHERE false
    $view$;
  ELSE
    EXECUTE $view$
      CREATE OR REPLACE VIEW public.subordinate_implied AS
      SELECT DISTINCT admin.app_id AS supervisor_id, member.app_id AS subordinate_id
      FROM public.staff_admin grant_row
      JOIN public.staff admin ON admin.id = grant_row.staff_id
      JOIN public.team member_team
        ON lower(member_team.office_id) = lower(grant_row.office_id)
      JOIN public.staff member
        ON lower(member.team_id) = lower(member_team.team_id)
      WHERE grant_row.role IN ('office_admin', 'performance_admin')
        AND grant_row.office_id IS NOT NULL
        AND btrim(grant_row.office_id) <> ''
        AND admin.app_id IS NOT NULL
        AND btrim(admin.app_id) <> ''
        AND member.app_id IS NOT NULL
        AND btrim(member.app_id) <> ''
        AND lower(admin.app_id) <> lower(member.app_id)
      UNION
      SELECT DISTINCT admin.app_id AS supervisor_id, member.app_id AS subordinate_id
      FROM public.staff_admin grant_row
      JOIN public.staff admin ON admin.id = grant_row.staff_id
      JOIN public.staff member ON true
      WHERE grant_row.role = 'super_admin'
        AND grant_row.office_id IS NULL
        AND admin.app_id IS NOT NULL
        AND btrim(admin.app_id) <> ''
        AND member.app_id IS NOT NULL
        AND btrim(member.app_id) <> ''
        AND lower(admin.app_id) <> lower(member.app_id)
    $view$;
  END IF;
END $$;

CREATE OR REPLACE VIEW public.subordinate_effective AS
SELECT supervisor_id, subordinate_id
FROM public.subordinate
UNION
SELECT supervisor_id, subordinate_id
FROM public.subordinate_implied;

GRANT SELECT ON public.subordinate_implied TO anon, authenticated, service_role;
GRANT SELECT ON public.subordinate_effective TO anon, authenticated, service_role;
