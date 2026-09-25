-- Sub-project slide fields: assignees, PICs, comments, attachments.
-- Safe to run more than once.

alter table public.subproject
  add column if not exists assignee_01 text,
  add column if not exists assignee_02 text,
  add column if not exists assignee_03 text,
  add column if not exists assignee_04 text,
  add column if not exists assignee_05 text,
  add column if not exists assignee_06 text,
  add column if not exists assignee_07 text,
  add column if not exists assignee_08 text,
  add column if not exists assignee_09 text,
  add column if not exists assignee_10 text,
  add column if not exists assignee_11 text,
  add column if not exists assignee_12 text,
  add column if not exists assignee_13 text,
  add column if not exists assignee_14 text,
  add column if not exists assignee_15 text,
  add column if not exists assignee_16 text,
  add column if not exists assignee_17 text,
  add column if not exists assignee_18 text,
  add column if not exists assignee_19 text,
  add column if not exists assignee_20 text,
  add column if not exists pic_01 text,
  add column if not exists pic_02 text,
  add column if not exists pic_03 text,
  add column if not exists pic_04 text,
  add column if not exists pic_05 text,
  add column if not exists pic_06 text,
  add column if not exists pic_07 text,
  add column if not exists pic_08 text,
  add column if not exists pic_09 text,
  add column if not exists pic_10 text,
  add column if not exists pic_11 text,
  add column if not exists pic_12 text,
  add column if not exists pic_13 text,
  add column if not exists pic_14 text,
  add column if not exists pic_15 text,
  add column if not exists pic_16 text,
  add column if not exists pic_17 text,
  add column if not exists pic_18 text,
  add column if not exists pic_19 text,
  add column if not exists pic_20 text;

create table if not exists public.subproject_comment (
  id uuid primary key default gen_random_uuid(),
  subproject_id uuid not null references public.subproject (id) on delete cascade,
  description text not null default '',
  status text not null default 'Active',
  create_by uuid references public.staff (id),
  create_date timestamptz not null default now(),
  update_by uuid references public.staff (id),
  update_date timestamptz,
  constraint subproject_comment_status_check
    check (status = any (array['Active'::text, 'Deleted'::text]))
);

create index if not exists subproject_comment_subproject_id_idx
  on public.subproject_comment (subproject_id);

alter table public.subproject_comment enable row level security;

drop policy if exists subproject_comment_anon_all on public.subproject_comment;
create policy subproject_comment_anon_all
  on public.subproject_comment
  for all
  to anon
  using (true)
  with check (true);

drop policy if exists subproject_comment_authenticated_all on public.subproject_comment;
create policy subproject_comment_authenticated_all
  on public.subproject_comment
  for all
  to authenticated
  using (true)
  with check (true);

grant select, insert, update, delete
  on public.subproject_comment
  to anon, authenticated;

alter table public.file_attachment
  drop constraint if exists file_attachment_entity_type_check;
alter table public.file_attachment
  add constraint file_attachment_entity_type_check
  check (entity_type = any (array[
    'project'::text,
    'task'::text,
    'subtask'::text,
    'subproject'::text
  ]));

alter table public.url_attachment
  drop constraint if exists url_attachment_entity_type_check;
alter table public.url_attachment
  add constraint url_attachment_entity_type_check
  check (entity_type = any (array[
    'project'::text,
    'task'::text,
    'subtask'::text,
    'subproject'::text
  ]));

alter table public.inline_attachment
  drop constraint if exists inline_attachment_entity_type_check;
alter table public.inline_attachment
  add constraint inline_attachment_entity_type_check
  check (entity_type = any (array[
    'task_description'::text,
    'task_comment'::text,
    'subtask_description'::text,
    'subtask_comment'::text,
    'project_description'::text,
    'project_comment'::text,
    'subproject_description'::text,
    'subproject_comment'::text,
    'forum_post_content'::text
  ]));

notify pgrst, 'reload schema';
