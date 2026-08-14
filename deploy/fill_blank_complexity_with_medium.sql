update public.task
set complexity = 'Medium'
where complexity is null or btrim(complexity) = '';

update public.subtask
set complexity = 'Medium'
where complexity is null or btrim(complexity) = '';

notify pgrst, 'reload schema';
