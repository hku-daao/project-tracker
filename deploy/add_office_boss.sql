-- Staff in office X supervise everyone else in each office whose boss_office_id
-- is X, without a row in public.subordinate.
-- VPIAO is the boss of DAAO, CPAO, and VPIAO, so VPIAO staff see all three.

ALTER TABLE public.office
  ADD COLUMN IF NOT EXISTS boss_office_id text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'office_boss_office_id_fkey'
  ) THEN
    ALTER TABLE public.office
      ADD CONSTRAINT office_boss_office_id_fkey
      FOREIGN KEY (boss_office_id) REFERENCES public.office (office_id)
      ON UPDATE CASCADE
      ON DELETE RESTRICT;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'office_boss_not_self'
  ) THEN
    ALTER TABLE public.office DROP CONSTRAINT office_boss_not_self;
  END IF;
END $$;

UPDATE public.office
SET boss_office_id = 'vpiao'
WHERE office_id IN ('vpiao', 'daao', 'cpao')
  AND boss_office_id IS DISTINCT FROM 'vpiao';

CREATE OR REPLACE VIEW public.subordinate_implied AS
SELECT DISTINCT sup.app_id AS supervisor_id, sub.app_id AS subordinate_id
FROM public.staff sup
JOIN LATERAL (
  SELECT office_id
  FROM public.team
  WHERE lower(team_id) = lower(sup.team_id)
  LIMIT 1
) sup_team ON true
JOIN public.office covered
  ON lower(covered.boss_office_id) = lower(sup_team.office_id)
JOIN public.team sub_team
  ON lower(sub_team.office_id) = lower(covered.office_id)
JOIN public.staff sub
  ON lower(sub.team_id) = lower(sub_team.team_id)
WHERE sup.app_id IS NOT NULL
  AND btrim(sup.app_id) <> ''
  AND sub.app_id IS NOT NULL
  AND btrim(sub.app_id) <> ''
  AND lower(sup.app_id) <> lower(sub.app_id);

CREATE OR REPLACE VIEW public.subordinate_effective AS
SELECT supervisor_id, subordinate_id
FROM public.subordinate
UNION
SELECT supervisor_id, subordinate_id
FROM public.subordinate_implied;

GRANT SELECT ON public.subordinate_implied TO anon, authenticated, service_role;
GRANT SELECT ON public.subordinate_effective TO anon, authenticated, service_role;

-- Drop stored rows that the boss-office rule now covers.
DELETE FROM public.subordinate stored
USING public.subordinate_implied implied
WHERE lower(stored.supervisor_id) = lower(implied.supervisor_id)
  AND lower(stored.subordinate_id) = lower(implied.subordinate_id);
