-- Multiple Persons-in-Charge per project (subset of assignees); stored as JSON array of staff.id uuid strings.

ALTER TABLE public.project
  ADD COLUMN IF NOT EXISTS pic jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.project.pic IS 'JSON array of staff.id (uuid) — Persons in Charge (chosen from assignees)';

UPDATE public.project SET pic = '[]'::jsonb WHERE pic IS NULL;
