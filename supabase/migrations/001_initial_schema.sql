-- Project Tracker – Initial schema for DAAO Apps (Supabase)
-- Run this in Supabase SQL Editor or via: supabase db push

-- ========== 1. STAFF DATA ==========

CREATE TABLE staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text,
  created_at timestamptz DEFAULT now() NOT NULL
);

COMMENT ON TABLE staff IS 'Staff members (Directors and Responsible Officers)';

CREATE TABLE teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);

COMMENT ON TABLE teams IS 'Teams with hierarchy (Directors + Responsible Officers)';

CREATE TABLE team_members (
  team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('director', 'officer')),
  PRIMARY KEY (team_id, staff_id)
);

CREATE INDEX idx_team_members_staff ON team_members(staff_id);
COMMENT ON TABLE team_members IS 'Staff membership in teams; role = director | officer';

-- ========== 2. INITIATIVES (HIGH-LEVEL) ==========

CREATE TABLE initiatives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text DEFAULT '' NOT NULL,
  priority smallint NOT NULL CHECK (priority IN (1, 2)),
  start_date date,
  end_date date,
  created_at timestamptz DEFAULT now() NOT NULL
);

COMMENT ON COLUMN initiatives.priority IS '1 = Standard, 2 = Urgent';
CREATE INDEX idx_initiatives_team ON initiatives(team_id);
CREATE INDEX idx_initiatives_created ON initiatives(created_at DESC);

CREATE TABLE initiative_directors (
  initiative_id uuid NOT NULL REFERENCES initiatives(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  PRIMARY KEY (initiative_id, staff_id)
);

CREATE INDEX idx_initiative_directors_staff ON initiative_directors(staff_id);

CREATE TABLE sub_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  initiative_id uuid NOT NULL REFERENCES initiatives(id) ON DELETE CASCADE,
  label text NOT NULL,
  is_completed boolean DEFAULT false NOT NULL
);

CREATE INDEX idx_sub_tasks_initiative ON sub_tasks(initiative_id);

-- ========== 3. TASKS (LOW-LEVEL) ==========

CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid REFERENCES teams(id) ON DELETE SET NULL,
  name text NOT NULL,
  description text DEFAULT '' NOT NULL,
  priority smallint NOT NULL CHECK (priority IN (1, 2)),
  start_date date,
  end_date date,
  status text NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'in_progress', 'done')),
  progress_percent smallint DEFAULT 0 NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);

COMMENT ON COLUMN tasks.priority IS '1 = Standard, 2 = Urgent';
COMMENT ON COLUMN tasks.status IS 'todo = Not started, in_progress = In progress, done = Completed';
CREATE INDEX idx_tasks_team ON tasks(team_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_created ON tasks(created_at DESC);

CREATE TABLE task_assignees (
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, staff_id)
);

CREATE INDEX idx_task_assignees_staff ON task_assignees(staff_id);

-- ========== 4. COMMENTS (initiatives + tasks) ==========

CREATE TABLE comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL CHECK (entity_type IN ('initiative', 'task')),
  entity_id uuid NOT NULL,
  author_id uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  body text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX idx_comments_entity ON comments(entity_type, entity_id);
CREATE INDEX idx_comments_created ON comments(created_at);

-- ========== 5. AUDIT (deleted records) ==========

CREATE TABLE deleted_sub_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  initiative_id uuid NOT NULL,
  sub_task_label text NOT NULL,
  is_completed boolean NOT NULL,
  deleted_at timestamptz DEFAULT now() NOT NULL,
  deleted_by text NOT NULL
);

CREATE INDEX idx_deleted_sub_tasks_initiative ON deleted_sub_tasks(initiative_id);
CREATE INDEX idx_deleted_sub_tasks_deleted_at ON deleted_sub_tasks(deleted_at DESC);

CREATE TABLE deleted_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  task_name text NOT NULL,
  team_id uuid,
  assignee_ids uuid[] DEFAULT '{}',
  deleted_at timestamptz DEFAULT now() NOT NULL,
  deleted_by text NOT NULL
);

CREATE INDEX idx_deleted_tasks_team ON deleted_tasks(team_id);
CREATE INDEX idx_deleted_tasks_deleted_at ON deleted_tasks(deleted_at DESC);
-- Optional: GIN index to query by assignee in deleted_tasks
-- CREATE INDEX idx_deleted_tasks_assignee_ids ON deleted_tasks USING GIN (assignee_ids);
