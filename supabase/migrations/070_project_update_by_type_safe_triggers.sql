-- Make project update_by trigger writes safe across environments.
--
-- Some databases have public.project.update_by as uuid, while others have it as
-- text. These functions detect the column type and write update_by with the
-- correct cast, avoiding COALESCE uuid/text mismatch errors.

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
  v_project_update_by_type text;
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

  SELECT c.udt_name
  INTO v_project_update_by_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'project'
    AND c.column_name = 'update_by';

  IF v_project_update_by_type = 'uuid' THEN
    IF v_update_by ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      EXECUTE
        'UPDATE public.project
         SET update_by = COALESCE($1::uuid, update_by),
             update_date = $2
         WHERE id = $3'
      USING v_update_by, v_update_at, v_project_id;
    ELSE
      UPDATE public.project
      SET update_date = v_update_at
      WHERE id = v_project_id;
    END IF;
  ELSE
    EXECUTE
      'UPDATE public.project
       SET update_by = COALESCE($1::text, update_by::text),
           update_date = $2
       WHERE id = $3'
    USING v_update_by, v_update_at, v_project_id;
  END IF;
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
  v_project_update_by_type text;
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

  SELECT c.udt_name
  INTO v_project_update_by_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'project'
    AND c.column_name = 'update_by';

  IF v_project_update_by_type = 'uuid' THEN
    IF v_staff_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      EXECUTE
        'UPDATE public.project
         SET update_by = COALESCE($1::uuid, update_by),
             update_date = $2
         WHERE id = $3'
      USING v_staff_id, v_activity_at, v_project_id;
    ELSE
      UPDATE public.project
      SET update_date = v_activity_at
      WHERE id = v_project_id;
    END IF;
  ELSE
    EXECUTE
      'UPDATE public.project
       SET update_by = COALESCE($1::text, update_by::text),
           update_date = $2
       WHERE id = $3'
    USING v_staff_id, v_activity_at, v_project_id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$fn$;
