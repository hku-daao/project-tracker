-- Preferred UI label for staff (welcome banner). Backfill from name when missing.
ALTER TABLE staff ADD COLUMN IF NOT EXISTS display_name text;

COMMENT ON COLUMN staff.display_name IS 'Display name for UI; if null, clients may use name.';

UPDATE staff
SET display_name = trim(name)
WHERE display_name IS NULL OR trim(display_name) = '';
