-- Materialized view: one row per live parent task with pre-joined, aggregated searchable text
-- from `task` + all non-deleted `subtask` rows. GIN indexes give fast substring / FTS lookups;
-- RPC `search_parent_task_ids_for_tokens` reads only this MV (single indexed scan per token).

-- Requires 055 (extension pg_trgm, prior RPC). Safe to run after 055.

-- Refresh when task/subtask data changes (pick one):
--   REFRESH MATERIALIZED VIEW CONCURRENTLY public.task_subtask_search_mv;
--   Or schedule via pg_cron / Edge Function calling refresh_task_subtask_search_mv().

CREATE MATERIALIZED VIEW public.task_subtask_search_mv AS
SELECT
  parent_task_id,
  doc_lower,
  to_tsvector('simple', doc_lower) AS search_vector
FROM (
  SELECT
    t.id AS parent_task_id,
    lower(
      trim(both FROM coalesce(t.task_name, '') || ' ' || coalesce(t.description, '')) ||
      ' ' ||
      coalesce(
        string_agg(
          lower(
            trim(
              both FROM coalesce(s.subtask_name, '') || ' ' || coalesce(s.description, '')
            )
          ),
          ' '
          ORDER BY s.create_date NULLS LAST
        ),
        ''
      )
    ) AS doc_lower
  FROM public.task t
  LEFT JOIN public.subtask s
    ON s.task_id = t.id
    AND lower(trim(coalesce(s.status::text, ''))) NOT IN ('deleted', 'delete')
  WHERE lower(trim(coalesce(t.status::text, ''))) NOT IN ('deleted', 'delete')
  GROUP BY t.id, t.task_name, t.description
) agg;

COMMENT ON MATERIALIZED VIEW public.task_subtask_search_mv IS
  'Pre-aggregated task + sub-task search blob per parent. Stale until REFRESH MATERIALIZED VIEW CONCURRENTLY.';

GRANT SELECT ON public.task_subtask_search_mv TO anon, authenticated;

-- Required for REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS task_subtask_search_mv_parent_uidx
  ON public.task_subtask_search_mv (parent_task_id);

-- Substring search (same predicate as RPC: doc_lower LIKE ''%'' || token || ''%'')
CREATE INDEX IF NOT EXISTS task_subtask_search_mv_doc_lower_trgm
  ON public.task_subtask_search_mv USING gin (doc_lower gin_trgm_ops);

-- Full-text search on the precomputed document (optional direct queries: @@ to_tsquery)
CREATE INDEX IF NOT EXISTS task_subtask_search_mv_search_vector_gin
  ON public.task_subtask_search_mv USING gin (search_vector);

-- Operator-assisted refresh (run from SQL editor, cron, or automation). Uses DEFINER so RLS on base tables is not required for refresh.
CREATE OR REPLACE FUNCTION public.refresh_task_subtask_search_mv()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.task_subtask_search_mv;
END;
$$;

COMMENT ON FUNCTION public.refresh_task_subtask_search_mv() IS
  'Rebuild search MV after task/subtask edits. Prefer scheduling (e.g. every 1–5 min) vs per-row triggers.';

REVOKE ALL ON FUNCTION public.refresh_task_subtask_search_mv() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_task_subtask_search_mv() TO service_role;

-- Single-source scan: parent ids whose aggregated doc matches each token (AND across tokens).
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
      SELECT m.parent_task_id AS x
      FROM public.task_subtask_search_mv m
      WHERE m.doc_lower LIKE '%' || lower(tok) || '%'
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
  'AND semantics over tokens; reads indexed task_subtask_search_mv (refresh MV after data changes).';

-- Base-table trigram indexes were only used by the previous RPC implementation; the MV carries search payloads now.
DROP INDEX IF EXISTS public.idx_task_search_concat_lower_trgm;
DROP INDEX IF EXISTS public.idx_subtask_search_concat_lower_trgm;
