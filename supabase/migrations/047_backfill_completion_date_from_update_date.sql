-- Backfill completion_date from update_date for historical rows where completion_date
-- was never set (columns added in 046_task_subtask_submit_completion_dates.sql).
--
-- IMPORTANT: Do not set completion_date on rows that are still in progress. This
-- migration only touches rows that already look "finished" (status / submission),
-- matching how the app treats completion (see task_detail / accept flow).
--
-- --- Dry run (Supabase SQL Editor): inspect counts ---
-- SELECT count(*) AS task_rows_to_fill
-- FROM public.task
-- WHERE completion_date IS NULL
--   AND update_date IS NOT NULL
--   AND (
--     lower(trim(status)) IN ('completed', 'complete')
--     OR lower(trim(coalesce(submission, ''))) IN ('accepted', 'completed')
--   );
--
-- SELECT count(*) AS subtask_rows_to_fill
-- FROM public.subtask
-- WHERE completion_date IS NULL
--   AND update_date IS NOT NULL
--   AND (
--     lower(trim(status)) IN ('completed', 'complete')
--     OR lower(trim(submission)) IN ('accepted', 'completed')
--   );
--
-- --- Optional: sample rows before update ---
-- SELECT id, status, submission, update_date, completion_date
-- FROM public.task
-- WHERE completion_date IS NULL AND update_date IS NOT NULL
--   AND (
--     lower(trim(status)) IN ('completed', 'complete')
--     OR lower(trim(coalesce(submission, ''))) IN ('accepted', 'completed')
--   )
-- LIMIT 50;

BEGIN;

UPDATE public.task
SET completion_date = update_date
WHERE completion_date IS NULL
  AND update_date IS NOT NULL
  AND (
    lower(trim(status)) IN ('completed', 'complete')
    OR lower(trim(coalesce(submission, ''))) IN ('accepted', 'completed')
  );

UPDATE public.subtask
SET completion_date = update_date
WHERE completion_date IS NULL
  AND update_date IS NOT NULL
  AND (
    lower(trim(status)) IN ('completed', 'complete')
    OR lower(trim(submission)) IN ('accepted', 'completed')
  );

COMMIT;

-- If you truly need "copy update_date → completion_date for every row where
-- completion_date is NULL" (including Incomplete / Pending), replace the AND (...)
-- block with only:
--   AND update_date IS NOT NULL
-- Run the dry-run SELECTs first; that variant can mark incomplete work as completed
-- in the UI wherever completion_date drives display.
