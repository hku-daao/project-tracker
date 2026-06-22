-- Project comments and project inline images.
--
-- This enables the project slide to mirror task/subtask comment and inline-image
-- behavior without reusing task/subtask comment tables.

CREATE TABLE IF NOT EXISTS public.project_comment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.project (id) ON DELETE CASCADE,
  description text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'Active'
    CHECK (status IN ('Active', 'Deleted')),
  create_by uuid REFERENCES public.staff (id),
  create_date timestamptz NOT NULL DEFAULT now(),
  update_by uuid REFERENCES public.staff (id),
  update_date timestamptz
);

CREATE INDEX IF NOT EXISTS project_comment_project_id_idx
  ON public.project_comment (project_id);

CREATE INDEX IF NOT EXISTS project_comment_project_activity_idx
  ON public.project_comment (
    project_id,
    (COALESCE(update_date, create_date)) DESC
  );

ALTER TABLE public.project_comment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_project_comment" ON public.project_comment;
CREATE POLICY "anon_all_project_comment"
  ON public.project_comment
  FOR ALL
  TO anon
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_all_project_comment" ON public.project_comment;
CREATE POLICY "authenticated_all_project_comment"
  ON public.project_comment
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_comment TO anon, authenticated;

COMMENT ON TABLE public.project_comment IS
  'Project-linked comments for the Asana project slide.';
COMMENT ON COLUMN public.project_comment.project_id IS
  'Owning public.project row.';
COMMENT ON COLUMN public.project_comment.status IS
  'Active rows are displayed; Deleted rows are hidden.';

-- Extend inline image owners to include project descriptions and project comments.
DO $$
DECLARE
  v_constraint_name text;
BEGIN
  SELECT c.conname
  INTO v_constraint_name
  FROM pg_constraint c
  WHERE c.conrelid = 'public.inline_attachment'::regclass
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) LIKE '%entity_type%'
    AND pg_get_constraintdef(c.oid) LIKE '%task_description%'
  LIMIT 1;

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.inline_attachment DROP CONSTRAINT %I',
      v_constraint_name
    );
  END IF;
END $$;

ALTER TABLE public.inline_attachment
  ADD CONSTRAINT inline_attachment_entity_type_check
  CHECK (entity_type IN (
    'task_description',
    'task_comment',
    'subtask_description',
    'subtask_comment',
    'project_description',
    'project_comment'
  ));

COMMENT ON COLUMN public.inline_attachment.entity_type IS
  'task_description | task_comment | subtask_description | subtask_comment | project_description | project_comment.';

-- Project comments should affect the project "last updated" display/sort.
CREATE OR REPLACE FUNCTION public._trg_project_comment_touch_project()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_project_id uuid;
  v_staff_id text;
  v_activity_at timestamptz;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_project_id := OLD.project_id;
    v_staff_id := COALESCE(OLD.update_by::text, OLD.create_by::text);
    v_activity_at := COALESCE(OLD.update_date, OLD.create_date, now());
  ELSE
    v_project_id := NEW.project_id;
    v_staff_id := COALESCE(NEW.update_by::text, NEW.create_by::text);
    v_activity_at := COALESCE(NEW.update_date, NEW.create_date, now());
  END IF;

  UPDATE public.project
  SET
    update_by = COALESCE(v_staff_id, update_by),
    update_date = v_activity_at
  WHERE id = v_project_id;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS project_comment_touch_project_trg
  ON public.project_comment;

CREATE TRIGGER project_comment_touch_project_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.project_comment
  FOR EACH ROW
  EXECUTE PROCEDURE public._trg_project_comment_touch_project();
