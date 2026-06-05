-- Keep project audit fields in sync with activity from associated tasks.
--
-- Rules:
--   1) When a task is newly associated to a project, project.update_by/date
--      follow task.update_by/date.
--   2) When a task already belongs to a project and task.update_by,
--      task.update_date, or task.last_updated changes, project.update_by follows
--      task.update_by and project.update_date follows task.last_updated.

CREATE OR REPLACE FUNCTION public.project_touch_from_task_activity(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_project_id uuid;
  v_update_by uuid;
  v_update_at timestamptz;
BEGIN
  SELECT
    t.project_id,
    t.update_by,
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

CREATE OR REPLACE FUNCTION public._trg_task_touch_project_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  PERFORM public.project_touch_from_task_activity(NEW.id);
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS task_touch_project_audit_trg ON public.task;
CREATE TRIGGER task_touch_project_audit_trg
  AFTER INSERT OR UPDATE OF project_id, update_by, update_date, last_updated ON public.task
  FOR EACH ROW
  EXECUTE PROCEDURE public._trg_task_touch_project_audit();

-- Ensure comment-driven changes to task.last_updated also cascade to project.
CREATE OR REPLACE FUNCTION public.task_refresh_last_updated(p_task_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_upd       timestamptz;
  v_comm_max  timestamptz;
  v_result    timestamptz;
BEGIN
  SELECT t.update_date INTO v_upd FROM public.task t WHERE t.id = p_task_id;
  SELECT MAX(COALESCE(c.update_date, c.create_date)) INTO v_comm_max
  FROM public."comment" c
  WHERE c.task_id = p_task_id;

  IF v_upd IS NULL AND v_comm_max IS NULL THEN
    UPDATE public.task SET last_updated = NULL WHERE id = p_task_id;
    PERFORM public.project_touch_from_task_activity(p_task_id);
    RETURN;
  END IF;
  IF v_upd IS NULL THEN
    v_result := v_comm_max;
  ELSIF v_comm_max IS NULL THEN
    v_result := v_upd;
  ELSE
    v_result := GREATEST(v_upd, v_comm_max);
  END IF;
  UPDATE public.task SET last_updated = v_result WHERE id = p_task_id;
  PERFORM public.project_touch_from_task_activity(p_task_id);
END;
$fn$;

-- Backfill currently associated tasks into their projects using latest task activity.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id
    FROM public.task
    WHERE project_id IS NOT NULL
      AND COALESCE(last_updated, update_date) IS NOT NULL
    ORDER BY COALESCE(last_updated, update_date) ASC
  LOOP
    PERFORM public.project_touch_from_task_activity(r.id);
  END LOOP;
END $$;
