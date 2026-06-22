-- Fix project comment trigger for databases where project.update_by is text.
--
-- Some environments have public.project.update_by as text while
-- project_comment.create_by/update_by are uuid. Cast staff ids to text before
-- writing project.update_by to avoid "COALESCE types uuid and text cannot be
-- matched".

CREATE OR REPLACE FUNCTION public.project_touch_from_task_activity(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_project_id uuid;
  v_update_by text;
  v_update_at timestamptz;
BEGIN
  SELECT
    t.project_id,
    t.update_by::text,
    COALESCE(t.last_updated, t.update_date)
  INTO v_project_id, v_update_by, v_update_at
  FROM public.task t
  WHERE t.id = p_task_id;

  IF v_project_id IS NULL OR v_update_at IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.project
  SET
    update_by = COALESCE(v_update_by, update_by),
    update_date = v_update_at
  WHERE id = v_project_id;
END;
$fn$;

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
