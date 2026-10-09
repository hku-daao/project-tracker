-- Expand assignee and PIC columns.
-- Project and sub-project: assignee_21..assignee_60 and pic_21..pic_60.
-- Task and sub-task: assignee_11..assignee_25, plus the matching
-- overdue-reminder date columns when assignee_10_overdue_reminder_last_sent_on exists.
-- Task and sub-task PIC stays the single column named pic (one PIC per row).
-- Safe to run more than once. Copies the type of the existing slot column.

do $$
declare
  spec record;
  col_type text;
  reminder_type text;
  i int;
  col text;
begin
  for spec in
    select *
    from (
      values
        ('project', 'assignee_20', 'assignee', 21, 60),
        ('project', 'pic_20', 'pic', 21, 60),
        ('subproject', 'assignee_20', 'assignee', 21, 60),
        ('subproject', 'pic_20', 'pic', 21, 60),
        ('task', 'assignee_10', 'assignee', 11, 25),
        ('subtask', 'assignee_10', 'assignee', 11, 25)
    ) as t(table_name, source_col, prefix, start_n, end_n)
  loop
    select pg_catalog.format_type(a.atttypid, a.atttypmod)
      into col_type
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid = a.attrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = spec.table_name
      and a.attname = spec.source_col
      and a.attnum > 0
      and not a.attisdropped;

    if col_type is null then
      raise exception 'public.%.% was not found', spec.table_name, spec.source_col;
    end if;

    for i in spec.start_n..spec.end_n loop
      col := spec.prefix || '_' || lpad(i::text, 2, '0');
      execute format(
        'alter table public.%I add column if not exists %I %s',
        spec.table_name,
        col,
        col_type
      );
    end loop;
  end loop;

  select pg_catalog.format_type(a.atttypid, a.atttypmod)
    into reminder_type
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_class c on c.oid = a.attrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'task'
    and a.attname = 'assignee_10_overdue_reminder_last_sent_on'
    and a.attnum > 0
    and not a.attisdropped;

  if reminder_type is not null then
    for spec in
      select *
      from (values ('task'), ('subtask')) as t(table_name)
    loop
      for i in 11..25 loop
        col := 'assignee_' || lpad(i::text, 2, '0') || '_overdue_reminder_last_sent_on';
        execute format(
          'alter table public.%I add column if not exists %I %s',
          spec.table_name,
          col,
          reminder_type
        );
      end loop;
    end loop;
  end if;
end $$;

notify pgrst, 'reload schema';
