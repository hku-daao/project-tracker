create table if not exists public.forum_post_like (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.forum_post(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,
  created_at timestamp with time zone not null default now(),
  constraint forum_post_like_post_staff_unique unique (post_id, staff_id)
);

create index if not exists forum_post_like_post_id_idx
  on public.forum_post_like (post_id);

create index if not exists forum_post_like_staff_id_idx
  on public.forum_post_like (staff_id);

notify pgrst, 'reload schema';
