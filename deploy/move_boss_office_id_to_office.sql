-- The vice-president office lives on public.office, not on each staff row.
-- cpao, daao, and vpiao currently sit under VPIA.

ALTER TABLE public.office
  ADD COLUMN IF NOT EXISTS boss_office_id text;

UPDATE public.office
SET boss_office_id = 'vpiao'
WHERE lower(btrim(office_id)) IN ('cpao', 'daao', 'vpiao')
  AND (boss_office_id IS NULL OR btrim(boss_office_id) = '')
  AND EXISTS (
    SELECT 1 FROM public.office AS boss WHERE boss.office_id = 'vpiao'
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'office_boss_office_id_fkey'
  ) THEN
    ALTER TABLE public.office
      ADD CONSTRAINT office_boss_office_id_fkey
      FOREIGN KEY (boss_office_id)
      REFERENCES public.office (office_id)
      ON UPDATE CASCADE
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS office_boss_office_id_idx
  ON public.office (boss_office_id);

ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_boss_office_id_fkey;
DROP INDEX IF EXISTS public.staff_boss_office_id_idx;
ALTER TABLE public.staff DROP COLUMN IF EXISTS boss_office_id;

NOTIFY pgrst, 'reload schema';
