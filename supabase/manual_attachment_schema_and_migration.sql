-- Manual Supabase SQL: split legacy attachments into uploaded files and URLs.
-- Run these blocks in order.
--
-- Assumption:
-- Uploaded files are Firebase Storage URLs containing `project_tracker`.
-- External URL attachments are all other non-empty attachment.content values.

-- (1) Create file_attachment table.
create table if not exists public.file_attachment (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('project', 'task', 'subtask')),
  entity_id uuid not null,
  url text not null,
  storage_path text,
  filename text,
  description text,
  mime_type text,
  file_size_bytes bigint,
  created_by uuid references public.staff(id),
  created_at timestamptz not null default now(),
  sort_order integer not null default 0,
  status text not null default 'Active' check (status in ('Active', 'Deleted'))
);

create index if not exists file_attachment_active_entity_idx
  on public.file_attachment (entity_type, entity_id, sort_order, created_at)
  where status = 'Active';

create index if not exists file_attachment_created_by_idx
  on public.file_attachment (created_by);

create index if not exists file_attachment_storage_path_idx
  on public.file_attachment (storage_path);

alter table public.file_attachment enable row level security;

drop policy if exists "anon_all_file_attachment" on public.file_attachment;
create policy "anon_all_file_attachment"
  on public.file_attachment
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists "authenticated_all_file_attachment" on public.file_attachment;
create policy "authenticated_all_file_attachment"
  on public.file_attachment
  for all
  to authenticated
  using (true)
  with check (true);

grant select, insert, update, delete on public.file_attachment to anon, authenticated;


-- (2) Create url_attachment table.
create table if not exists public.url_attachment (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('project', 'task', 'subtask')),
  entity_id uuid not null,
  url text not null,
  label text not null,
  created_by uuid references public.staff(id),
  created_at timestamptz not null default now(),
  sort_order integer not null default 0,
  status text not null default 'Active' check (status in ('Active', 'Deleted'))
);

create index if not exists url_attachment_active_entity_idx
  on public.url_attachment (entity_type, entity_id, sort_order, created_at)
  where status = 'Active';

create index if not exists url_attachment_created_by_idx
  on public.url_attachment (created_by);

alter table public.url_attachment enable row level security;

drop policy if exists "anon_all_url_attachment" on public.url_attachment;
create policy "anon_all_url_attachment"
  on public.url_attachment
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists "authenticated_all_url_attachment" on public.url_attachment;
create policy "authenticated_all_url_attachment"
  on public.url_attachment
  for all
  to authenticated
  using (true)
  with check (true);

grant select, insert, update, delete on public.url_attachment to anon, authenticated;


-- (3) Migrate information from attachment table to file_attachment table.
insert into public.file_attachment (
  id,
  entity_type,
  entity_id,
  url,
  storage_path,
  filename,
  description,
  created_at,
  sort_order,
  status
)
select
  a.id,
  'task',
  a.task_id,
  a.content,
  substring(a.content from '/o/([^?]+)'),
  coalesce(
    nullif(a.description, ''),
    nullif(regexp_replace(split_part(a.content, '?', 1), '^.*(%2F|/)', ''), ''),
    'Uploaded file'
  ),
  nullif(a.description, ''),
  coalesce(a.create_date, now()),
  row_number() over (partition by a.task_id order by coalesce(a.create_date, now()), a.id) - 1,
  'Active'
from public.attachment a
where nullif(trim(a.content), '') is not null
  and (
    a.content ilike '%firebasestorage.googleapis.com%'
    or a.content ilike '%storage.googleapis.com%'
  )
  and a.content ilike '%project_tracker%'
on conflict (id) do nothing;


-- (4) Migrate information from attachment table to url_attachment table.
insert into public.url_attachment (
  id,
  entity_type,
  entity_id,
  url,
  label,
  created_at,
  sort_order,
  status
)
select
  a.id,
  'task',
  a.task_id,
  a.content,
  coalesce(nullif(a.description, ''), a.content),
  coalesce(a.create_date, now()),
  row_number() over (partition by a.task_id order by coalesce(a.create_date, now()), a.id) - 1,
  'Active'
from public.attachment a
where nullif(trim(a.content), '') is not null
  and not (
    (
      a.content ilike '%firebasestorage.googleapis.com%'
      or a.content ilike '%storage.googleapis.com%'
    )
    and a.content ilike '%project_tracker%'
  )
on conflict (id) do nothing;


-- (5) Migrate information from subtask_attachment table to file_attachment table.
insert into public.file_attachment (
  id,
  entity_type,
  entity_id,
  url,
  storage_path,
  filename,
  description,
  created_at,
  sort_order,
  status
)
select
  sa.id,
  'subtask',
  sa.subtask_id,
  sa.content,
  substring(sa.content from '/o/([^?]+)'),
  coalesce(
    nullif(sa.description, ''),
    nullif(regexp_replace(split_part(sa.content, '?', 1), '^.*(%2F|/)', ''), ''),
    'Uploaded file'
  ),
  nullif(sa.description, ''),
  coalesce(sa.create_date, now()),
  row_number() over (partition by sa.subtask_id order by coalesce(sa.create_date, now()), sa.id) - 1,
  'Active'
from public.subtask_attachment sa
where nullif(trim(sa.content), '') is not null
  and (
    sa.content ilike '%firebasestorage.googleapis.com%'
    or sa.content ilike '%storage.googleapis.com%'
  )
  and sa.content ilike '%project_tracker%'
on conflict (id) do nothing;


-- (6) Migrate information from subtask_attachment table to url_attachment table.
insert into public.url_attachment (
  id,
  entity_type,
  entity_id,
  url,
  label,
  created_at,
  sort_order,
  status
)
select
  sa.id,
  'subtask',
  sa.subtask_id,
  sa.content,
  coalesce(nullif(sa.description, ''), sa.content),
  coalesce(sa.create_date, now()),
  row_number() over (partition by sa.subtask_id order by coalesce(sa.create_date, now()), sa.id) - 1,
  'Active'
from public.subtask_attachment sa
where nullif(trim(sa.content), '') is not null
  and not (
    (
      sa.content ilike '%firebasestorage.googleapis.com%'
      or sa.content ilike '%storage.googleapis.com%'
    )
    and sa.content ilike '%project_tracker%'
  )
on conflict (id) do nothing;
