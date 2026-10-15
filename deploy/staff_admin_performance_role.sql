-- performance_admin covers one office per row, the same way office_admin does.
-- A person who oversees several offices has one row for each office.
-- super_admin keeps office_id empty, which means every office.

ALTER TABLE public.staff_admin DROP CONSTRAINT IF EXISTS staff_admin_role_check;
ALTER TABLE public.staff_admin ADD CONSTRAINT staff_admin_role_check
  CHECK (role = ANY (ARRAY['super_admin'::text, 'office_admin'::text, 'performance_admin'::text]));

ALTER TABLE public.staff_admin DROP CONSTRAINT IF EXISTS staff_admin_scope_check;
ALTER TABLE public.staff_admin ADD CONSTRAINT staff_admin_scope_check
  CHECK (
    ((role = 'super_admin'::text) AND (office_id IS NULL))
    OR ((role = ANY (ARRAY['office_admin'::text, 'performance_admin'::text])) AND (office_id IS NOT NULL))
  );

CREATE UNIQUE INDEX IF NOT EXISTS staff_admin_one_performance_grant_per_office
  ON public.staff_admin (staff_id, office_id)
  WHERE role = 'performance_admin';
