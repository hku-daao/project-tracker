-- `public."comment"`: store audit times as timestamptz (Hong Kong wall clock can be written from the app as +08:00).

-- If columns are still `date`, cast calendar day to HK midnight then timestamptz.
ALTER TABLE public."comment"
  ALTER COLUMN create_date TYPE timestamptz USING (
    CASE
      WHEN create_date IS NULL THEN NULL
      ELSE ((create_date::text || ' 00:00:00')::timestamp AT TIME ZONE 'Asia/Hong_Kong')
    END
  ),
  ALTER COLUMN update_date TYPE timestamptz USING (
    CASE
      WHEN update_date IS NULL THEN NULL
      ELSE ((update_date::text || ' 00:00:00')::timestamp AT TIME ZONE 'Asia/Hong_Kong')
    END
  );
