-- Sub-tasks under singular `public.task` (not legacy `sub_tasks` initiatives).

CREATE TABLE IF NOT EXISTS public.subtask (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.task (id) ON DELETE CASCADE,
  create_by uuid REFERENCES public.staff (id),
  subtask_name text NOT NULL,
  description text,
  priority text,
  start_date date,
  due_date date,
  status text NOT NULL DEFAULT 'Incomplete',
  submission text NOT NULL DEFAULT 'Pending',
  assignee_01 uuid,
  assignee_02 uuid,
  assignee_03 uuid,
  assignee_04 uuid,
  assignee_05 uuid,
  assignee_06 uuid,
  assignee_07 uuid,
  assignee_08 uuid,
  assignee_09 uuid,
  assignee_10 uuid,
  pic uuid REFERENCES public.staff (id),
  create_date timestamptz NOT NULL DEFAULT now(),
  update_by uuid REFERENCES public.staff (id),
  update_date timestamptz
);

CREATE INDEX IF NOT EXISTS subtask_task_id_idx ON public.subtask (task_id);

COMMENT ON TABLE public.subtask IS 'Child tasks under singular task; assignees subset of parent task assignees.';

CREATE TABLE IF NOT EXISTS public.subtask_attachment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subtask_id uuid NOT NULL REFERENCES public.subtask (id) ON DELETE CASCADE,
  content text,
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS subtask_attachment_subtask_uidx ON public.subtask_attachment (subtask_id);

CREATE TABLE IF NOT EXISTS public.subtask_comment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subtask_id uuid NOT NULL REFERENCES public.subtask (id) ON DELETE CASCADE,
  description text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'Active',
  create_by uuid REFERENCES public.staff (id),
  create_date timestamptz,
  update_by uuid REFERENCES public.staff (id),
  update_date timestamptz
);

CREATE INDEX IF NOT EXISTS subtask_comment_subtask_id_idx ON public.subtask_comment (subtask_id);

ALTER TABLE public.subtask ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subtask_attachment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subtask_comment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_subtask" ON public.subtask;
CREATE POLICY "anon_all_subtask" ON public.subtask FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_subtask_attachment" ON public.subtask_attachment;
CREATE POLICY "anon_all_subtask_attachment" ON public.subtask_attachment FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_subtask_comment" ON public.subtask_comment;
CREATE POLICY "anon_all_subtask_comment" ON public.subtask_comment FOR ALL TO anon USING (true) WITH CHECK (true);
