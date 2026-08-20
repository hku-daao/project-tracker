create table if not exists public.forum_thread (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'General',
  status text not null default 'Open',
  pinned boolean not null default false,
  locked boolean not null default false,
  created_by uuid references public.staff(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_by uuid references public.staff(id) on delete set null,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.forum_post (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.forum_thread(id) on delete cascade,
  parent_post_id uuid references public.forum_post(id) on delete cascade,
  depth integer not null default 0 check (depth >= 0 and depth <= 2),
  content text not null,
  status text not null default 'Active',
  created_by uuid references public.staff(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_by uuid references public.staff(id) on delete set null,
  updated_at timestamp with time zone
);

create table if not exists public.forum_post_like (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.forum_post(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,
  created_at timestamp with time zone not null default now(),
  constraint forum_post_like_post_staff_unique unique (post_id, staff_id)
);

create index if not exists forum_thread_pinned_updated_idx
  on public.forum_thread (pinned desc, updated_at desc);

create index if not exists forum_thread_created_by_idx
  on public.forum_thread (created_by);

create index if not exists forum_post_thread_depth_created_idx
  on public.forum_post (thread_id, depth, created_at);

create index if not exists forum_post_parent_post_id_idx
  on public.forum_post (parent_post_id);

create index if not exists forum_post_created_by_idx
  on public.forum_post (created_by);

create index if not exists forum_post_like_post_id_idx
  on public.forum_post_like (post_id);

create index if not exists forum_post_like_staff_id_idx
  on public.forum_post_like (staff_id);

grant select, insert, update, delete
  on public.forum_thread, public.forum_post, public.forum_post_like
  to anon, authenticated;

notify pgrst, 'reload schema';
