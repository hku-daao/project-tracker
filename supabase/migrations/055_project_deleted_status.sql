-- Allow projects to use the same soft-delete lifecycle status as tasks.

ALTER TABLE public.project
  DROP CONSTRAINT IF EXISTS project_status_check;

ALTER TABLE public.project
  ADD CONSTRAINT project_status_check
  CHECK (status IN ('Not started', 'In progress', 'Completed', 'Deleted'));

COMMENT ON COLUMN public.project.status IS
  'Not started | In progress | Completed | Deleted';
