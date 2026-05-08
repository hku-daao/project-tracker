-- Unified search across singular `task` and `subtask` for landing / Overview lists.
-- Uses pg_trgm indexes + one RPC (token AND semantics) instead of multiple client .ilike scans.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Combined searchable text per row (task row + subtask row). Supports FTS-style docs on server.
CREATE OR REPLACE VIEW public.task_subtask_search_document AS
SELECT
  t.id AS parent_task_id,
  NULL::uuid AS subtask_id,
  'task'::text AS row_kind,
  trim(
    both FROM (
      coalesce(t.task_name, '') || ' ' || coalesce(t.description, '')
    )
  ) AS search_blob,
  to_tsvector(
    'simple',
    trim(
      both FROM (
        coalesce(t.task_name, '') || ' ' || coalesce(t.description, '')
      )
    )
  ) AS search_vector
FROM public.task t
WHERE lower(trim(coalesce(t.status::text, ''))) NOT IN ('deleted', 'delete')

UNION ALL

SELECT
  s.task_id AS parent_task_id,
  s.id AS subtask_id,
  'subtask'::text AS row_kind,
  trim(
    both FROM (
      coalesce(s.subtask_name, '') || ' ' || coalesce(s.description, '')
    )
  ) AS search_blob,
  to_tsvector(
    'simple',
    trim(
      both FROM (
        coalesce(s.subtask_name, '') || ' ' || coalesce(s.description, '')
      )
    )
  ) AS search_vector
FROM public.subtask s
WHERE lower(trim(coalesce(s.status::text, ''))) NOT IN ('deleted', 'delete');

COMMENT ON VIEW public.task_subtask_search_document IS
  'Rows indexed for task/sub-task search (non-deleted parents and sub-tasks only).';

GRANT SELECT ON public.task_subtask_search_document TO anon, authenticated;

-- Accelerate substring search (same expressions as RPC below).
CREATE INDEX IF NOT EXISTS idx_task_search_concat_lower_trgm ON public.task USING gin (
  (
    lower(
      coalesce(task_name, '') || ' ' || coalesce(description, '')
    )
  ) gin_trgm_ops
);

CREATE INDEX IF NOT EXISTS idx_subtask_search_concat_lower_trgm ON public.subtask USING gin (
  (
    lower(
      coalesce(subtask_name, '') || ' ' || coalesce(description, '')
    )
  ) gin_trgm_ops
);

-- Parent task ids where EVERY non-empty token appears (case-insensitive substring) in either
-- the parent task (task_name, description) or any non-deleted sub-task row (subtask_name, description).
CREATE OR REPLACE FUNCTION public.search_parent_task_ids_for_tokens(p_tokens text[])
RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  tok text;
  ids uuid[];
  acc uuid[];
  empty uuid[] := ARRAY[]::uuid[];
BEGIN
  IF p_tokens IS NULL THEN
    RETURN empty;
  END IF;

  FOREACH tok IN ARRAY p_tokens
  LOOP
    tok := trim(tok);
    IF tok = '' THEN
      CONTINUE;
    END IF;

    SELECT coalesce(array_agg(DISTINCT x), empty)
    INTO ids
    FROM (
      SELECT t.id AS x
      FROM public.task t
      WHERE lower(trim(coalesce(t.status::text, ''))) NOT IN ('deleted', 'delete')
        AND lower(coalesce(t.task_name, '') || ' ' || coalesce(t.description, ''))
          LIKE '%' || lower(tok) || '%'
      UNION
      SELECT s.task_id AS x
      FROM public.subtask s
      WHERE lower(trim(coalesce(s.status::text, ''))) NOT IN ('deleted', 'delete')
        AND lower(coalesce(s.subtask_name, '') || ' ' || coalesce(s.description, ''))
          LIKE '%' || lower(tok) || '%'
    ) q;

    IF acc IS NULL THEN
      acc := ids;
    ELSE
      acc := ARRAY(
        SELECT unnest(acc)
        INTERSECT
        SELECT unnest(ids)
      );
    END IF;

    IF acc IS NULL OR cardinality(acc) = 0 THEN
      RETURN empty;
    END IF;
  END LOOP;

  RETURN coalesce(acc, empty);
END;
$$;

COMMENT ON FUNCTION public.search_parent_task_ids_for_tokens(text[]) IS
  'AND semantics over trimmed tokens; matches task fields or any child sub-task text (non-deleted only).';

GRANT EXECUTE ON FUNCTION public.search_parent_task_ids_for_tokens(text[]) TO anon, authenticated;
