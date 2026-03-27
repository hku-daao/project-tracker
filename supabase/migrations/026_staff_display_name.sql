-- Preferred UI label per staff row (welcome banner, etc.). Falls back to name when null.
ALTER TABLE staff ADD COLUMN IF NOT EXISTS display_name text;

COMMENT ON COLUMN staff.display_name IS 'Display name for UI; if null, clients may use name.';

UPDATE staff
SET display_name = trim(name)
WHERE display_name IS NULL OR trim(display_name) = '';
