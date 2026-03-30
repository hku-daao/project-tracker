-- Person in charge (PIC) on singular `task`; matches Flutter insert and load (staff id uuid).

ALTER TABLE public.task
  ADD COLUMN IF NOT EXISTS pic uuid REFERENCES public.staff(id);

COMMENT ON COLUMN public.task.pic IS 'Person in charge (references staff.id; same id space as assignee_01..10).';
