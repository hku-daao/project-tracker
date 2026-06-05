-- Inline images embedded in task/sub-task descriptions and comments.
-- Files live in Firebase Storage; this table stores URLs and placement metadata.

CREATE TABLE IF NOT EXISTS public.inline_attachment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL
    CHECK (entity_type IN (
      'task_description',
      'task_comment',
      'subtask_description',
      'subtask_comment'
    )),
  entity_id uuid NOT NULL,
  url text NOT NULL,
  description text,
  mime_type text,
  created_by uuid REFERENCES public.staff (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  sort_order integer NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS inline_attachment_entity_idx
  ON public.inline_attachment (entity_type, entity_id, sort_order, created_at);

ALTER TABLE public.inline_attachment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_inline_attachment" ON public.inline_attachment;
CREATE POLICY "anon_select_inline_attachment" ON public.inline_attachment
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_inline_attachment" ON public.inline_attachment;
CREATE POLICY "anon_insert_inline_attachment" ON public.inline_attachment
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_inline_attachment" ON public.inline_attachment;
CREATE POLICY "anon_update_inline_attachment" ON public.inline_attachment
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_inline_attachment" ON public.inline_attachment;
CREATE POLICY "anon_delete_inline_attachment" ON public.inline_attachment
  FOR DELETE TO anon USING (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inline_attachment TO anon, authenticated;

COMMENT ON TABLE public.inline_attachment IS
  'Inline image references for task/subtask descriptions and comments; actual image files are stored in Firebase Storage.';
COMMENT ON COLUMN public.inline_attachment.entity_type IS
  'task_description | task_comment | subtask_description | subtask_comment.';
COMMENT ON COLUMN public.inline_attachment.entity_id IS
  'ID of the owning task/comment/subtask/subtask_comment row, depending on entity_type.';
