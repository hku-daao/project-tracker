-- HKU / HK public holidays for calendar pickers (synced from project holiday list).
CREATE TABLE IF NOT EXISTS public.calendar_holiday (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  holiday_type text NOT NULL CHECK (holiday_type IN ('HKU', 'HK')),
  name text NOT NULL,
  holiday_date date NOT NULL,
  full_or_pm text NOT NULL CHECK (full_or_pm IN ('Full', 'PM')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS calendar_holiday_date_idx
  ON public.calendar_holiday (holiday_date);

ALTER TABLE public.calendar_holiday ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS calendar_holiday_select_authenticated ON public.calendar_holiday;
CREATE POLICY calendar_holiday_select_authenticated
  ON public.calendar_holiday FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS calendar_holiday_select_anon ON public.calendar_holiday;
CREATE POLICY calendar_holiday_select_anon
  ON public.calendar_holiday FOR SELECT TO anon USING (true);

GRANT SELECT ON public.calendar_holiday TO anon, authenticated;

COMMENT ON TABLE public.calendar_holiday IS
  'HKU vs HK holidays for in-app date pickers; holiday_type HKU=blue, HK=red in UI.';

TRUNCATE public.calendar_holiday;

INSERT INTO public.calendar_holiday (holiday_type, name, holiday_date, full_or_pm) VALUES
  ('HKU', 'New Year''s Eve (PM - UH)', '2025-12-31'::date, 'PM'),
  ('HK', 'The first day of January', '2026-01-01'::date, 'Full'),
  ('HKU', 'Lunar New Year''s Eve (PM - UH)', '2026-02-16'::date, 'PM'),
  ('HK', 'Lunar New Year''s Day', '2026-02-17'::date, 'Full'),
  ('HK', 'The second day of Lunar New Year', '2026-02-18'::date, 'Full'),
  ('HK', 'The third day of Lunar New Year', '2026-02-19'::date, 'Full'),
  ('HKU', 'HKU Foundation Day (UH)', '2026-03-16'::date, 'Full'),
  ('HK', 'Good Friday', '2026-04-03'::date, 'Full'),
  ('HK', 'The day following Good Friday', '2026-04-04'::date, 'Full'),
  ('HK', 'The day following Ching Ming Festival', '2026-04-06'::date, 'Full'),
  ('HK', 'The day following Easter Monday', '2026-04-07'::date, 'Full'),
  ('HK', 'Labour Day', '2026-05-01'::date, 'Full'),
  ('HK', 'The day following the Birthday of the Buddha', '2026-05-25'::date, 'Full'),
  ('HK', 'Tuen Ng Festival', '2026-06-19'::date, 'Full'),
  ('HK', 'Hong Kong Special Administrative Region Establishment Day', '2026-07-01'::date, 'Full'),
  ('HK', 'The day following the Chinese Mid-Autumn Festival', '2026-09-26'::date, 'Full'),
  ('HK', 'National Day', '2026-10-01'::date, 'Full'),
  ('HK', 'The day following Chung Yeung Festival', '2026-10-19'::date, 'Full'),
  ('HKU', 'Christmas Eve (UH)', '2026-12-24'::date, 'PM'),
  ('HK', 'Christmas Day', '2026-12-25'::date, 'Full'),
  ('HK', 'The first weekday after Christmas Day', '2026-12-26'::date, 'Full'),
  ('HKU', 'New Year''s Eve (PM - UH)', '2026-12-31'::date, 'PM'),
  ('HK', 'The first day of January', '2027-01-01'::date, 'Full'),
  ('HKU', 'Lunar New Year''s Eve (PM - UH)', '2027-02-05'::date, 'PM'),
  ('HK', 'Lunar New Year''s Day', '2027-02-06'::date, 'Full'),
  ('HK', 'The second day of Lunar New Year', '2027-02-07'::date, 'Full'),
  ('HK', 'The third day of Lunar New Year', '2027-02-08'::date, 'Full'),
  ('HK', 'The fourth day of Lunar New Year', '2027-02-09'::date, 'Full'),
  ('HKU', 'HKU Foundation Day (UH)', '2027-03-16'::date, 'Full'),
  ('HK', 'Good Friday', '2027-03-26'::date, 'Full'),
  ('HK', 'The day following Good Friday', '2027-03-27'::date, 'Full'),
  ('HK', 'The day following Easter Monday', '2027-03-29'::date, 'Full'),
  ('HK', 'Ching Ming Festival', '2027-04-05'::date, 'Full'),
  ('HK', 'Labour Day', '2027-05-01'::date, 'Full'),
  ('HK', 'Birthday of the Buddha', '2027-05-13'::date, 'Full'),
  ('HK', 'Tuen Ng Festival', '2027-06-09'::date, 'Full'),
  ('HK', 'Hong Kong Special Administrative Region Establishment Day', '2027-07-01'::date, 'Full'),
  ('HK', 'Mid-Autumn Festival', '2027-09-16'::date, 'Full'),
  ('HK', 'National Day', '2027-10-01'::date, 'Full'),
  ('HK', 'Chung Yeung Festival', '2027-10-08'::date, 'Full'),
  ('HKU', 'Christmas Eve (UH)', '2027-12-24'::date, 'Full'),
  ('HK', 'Christmas Day', '2027-12-25'::date, 'Full'),
  ('HK', 'The first weekday after Christmas Day', '2027-12-27'::date, 'Full'),
  ('HKU', 'New Year''s Eve (PM - UH)', '2027-12-31'::date, 'PM');
