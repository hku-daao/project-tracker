-- App-level subordinate links by staff.app_id (Flutter web filters tasks + assignee picker).
-- Safe if you already created `public.subordinate` manually.

CREATE TABLE IF NOT EXISTS public.subordinate (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id text NOT NULL,
  subordinate_id text NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS subordinate_supervisor_subordinate_uidx
  ON public.subordinate (supervisor_id, subordinate_id);

CREATE INDEX IF NOT EXISTS subordinate_supervisor_id_idx
  ON public.subordinate (supervisor_id);

ALTER TABLE public.subordinate ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_read_subordinate" ON public.subordinate;
CREATE POLICY "anon_read_subordinate" ON public.subordinate FOR SELECT TO anon USING (true);

-- Supervisor assignees: self + rows in `subordinate` (by app_id), instead of only subordinate_mapping.
CREATE OR REPLACE FUNCTION get_assignable_staff(p_firebase_uid text)
RETURNS TABLE (
  staff_id uuid,
  staff_app_id text,
  staff_name text,
  team_id uuid,
  team_app_id text,
  team_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_app_user_id uuid;
  v_staff_id uuid;
  v_role_app_id text;
  v_supervisor_app_id text;
BEGIN
  SELECT u.id, u.staff_id, r.app_id INTO v_app_user_id, v_staff_id, v_role_app_id
  FROM app_users u
  JOIN user_role_mapping urm ON urm.app_user_id = u.id
  JOIN roles r ON r.id = urm.role_id
  WHERE u.firebase_uid = p_firebase_uid
  LIMIT 1;

  IF v_app_user_id IS NULL THEN
    RETURN;
  END IF;

  IF v_role_app_id IN ('sys_admin', 'dept_head') THEN
    RETURN QUERY
    SELECT s.id, s.app_id, s.name, t.id, t.app_id, t.name
    FROM staff s
    LEFT JOIN team_members tm ON tm.staff_id = s.id
    LEFT JOIN teams t ON t.id = tm.team_id
    WHERE s.app_id IS NOT NULL
    ORDER BY t.name NULLS LAST, s.name;
    RETURN;
  END IF;

  IF v_role_app_id = 'supervisor' AND v_staff_id IS NOT NULL THEN
    SELECT s.app_id INTO v_supervisor_app_id FROM staff s WHERE s.id = v_staff_id LIMIT 1;
    RETURN QUERY
    SELECT s.id, s.app_id, s.name, t.id, t.app_id, t.name
    FROM staff s
    LEFT JOIN team_members tm ON tm.staff_id = s.id
    LEFT JOIN teams t ON t.id = tm.team_id
    WHERE s.app_id IS NOT NULL
      AND (
        s.id = v_staff_id
        OR EXISTS (
          SELECT 1
          FROM subordinate sub
          WHERE sub.supervisor_id = v_supervisor_app_id
            AND sub.subordinate_id = s.app_id
        )
      )
    ORDER BY t.name NULLS LAST, s.name;
    RETURN;
  END IF;

  IF v_role_app_id = 'general' AND v_staff_id IS NOT NULL THEN
    RETURN QUERY
    SELECT s.id, s.app_id, s.name, t.id, t.app_id, t.name
    FROM staff s
    LEFT JOIN team_members tm ON tm.staff_id = s.id
    LEFT JOIN teams t ON t.id = tm.team_id
    WHERE s.id = v_staff_id
    ORDER BY s.name;
    RETURN;
  END IF;
END;
$$;

COMMENT ON FUNCTION get_assignable_staff(text) IS 'Assignable staff by role; supervisor uses public.subordinate (app_id keys) plus self.';
