-- Soft-delete support for inline images.
-- Files are deleted from Firebase Storage on commit, while metadata remains for audit/history.

ALTER TABLE public.inline_attachment
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'Active'
    CHECK (status IN ('Active', 'Deleted'));

CREATE INDEX IF NOT EXISTS inline_attachment_active_entity_idx
  ON public.inline_attachment (entity_type, entity_id, sort_order, created_at)
  WHERE status = 'Active';

UPDATE public.inline_attachment
SET status = 'Active'
WHERE status IS NULL OR status = '';

COMMENT ON COLUMN public.inline_attachment.status IS
  'Active rows are displayed; Deleted rows are hidden after the Firebase Storage object is removed.';
