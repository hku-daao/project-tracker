-- Dev user for offline migration (Step 1). SSO will replace this later.
-- Migration 016 imports kenkylee@hku.hk (app_id kenkylee). This seed ensures the row exists.

UPDATE staff
SET
  email = 'kenkylee@hku.hk',
  name = COALESCE(NULLIF(trim(name), ''), 'Ken Lee'),
  display_name = COALESCE(NULLIF(trim(display_name), ''), 'Ken Lee')
WHERE app_id IN ('ken', 'kenkylee')
   OR lower(email) = lower('kenkylee@hku.hk');

INSERT INTO staff (id, name, email, app_id, display_name)
SELECT gen_random_uuid(), 'Ken Lee', 'kenkylee@hku.hk', 'kenkylee', 'Ken Lee'
WHERE NOT EXISTS (
  SELECT 1 FROM staff WHERE lower(email) = lower('kenkylee@hku.hk')
);
