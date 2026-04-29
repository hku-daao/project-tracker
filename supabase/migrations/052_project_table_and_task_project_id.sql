-- Project grouping for singular tasks; HK timestamps written by app (see HkTime.timestampForDb).

CREATE TABLE IF NOT EXISTS public.project (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  assignee_01 text,
  assignee_02 text,
  assignee_03 text,
  assignee_04 text,
  assignee_05 text,
  assignee_06 text,
  assignee_07 text,
  assignee_08 text,
  assignee_09 text,
  assignee_10 text,
  description text NOT NULL DEFAULT '',
  start_date date,
  end_date date,
  status text NOT NULL DEFAULT 'Not started'
    CHECK (status IN ('Not started', 'In progress', 'Completed')),
  create_by uuid REFERENCES public.staff (id),
  create_date timestamptz NOT NULL DEFAULT now(),
  update_by uuid REFERENCES public.staff (id),
  update_date timestamptz
);

COMMENT ON TABLE public.project IS 'Projects (Assignee(s), Description, dates, status)';
COMMENT ON COLUMN public.project.name IS 'Project';
COMMENT ON COLUMN public.project.description IS 'Description';

CREATE INDEX IF NOT EXISTS idx_project_create_date ON public.project (create_date DESC);

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES public.project (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_task_project_id ON public.task (project_id);

ALTER TABLE public.project ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_project" ON public.project;
CREATE POLICY "anon_select_project" ON public.project
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_project" ON public.project;
CREATE POLICY "anon_insert_project" ON public.project
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_project" ON public.project;
CREATE POLICY "anon_update_project" ON public.project
  FOR UPDATE TO anon USING (true);

DROP POLICY IF EXISTS "anon_delete_project" ON public.project;
CREATE POLICY "anon_delete_project" ON public.project
  FOR DELETE TO anon USING (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.project TO anon, authenticated;
