-- 叩き台：要件確定後に見直す
-- 予定はログイン済みメンバー全員に公開（非公開・「予定あり」だけ表示は未対応）
-- 最初の管理者は Supabase の SQL Editor で作成する：
--   insert into public.members (id, display_name, is_admin) values ('<auth.users の id>', '名前', true);
-- members：OTOMIZU 関係者（個人事業主）
create table public.members (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- projects：案件・事業（例：みつきプロジェクト）
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- assignments：誰がどの案件にどの役割で配置されているか（1人が複数案件・複数役割）
create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  role text not null,
  unique (member_id, project_id, role)
);

-- events：各自が入力する予定
create table public.events (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id) on delete cascade,
  project_id uuid references public.projects (id) on delete set null,
  title text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  note text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index events_member_starts_idx on public.events (member_id, starts_at);

alter table public.members enable row level security;
alter table public.projects enable row level security;
alter table public.assignments enable row level security;
alter table public.events enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.members where id = auth.uid()), false);
$$;

-- 閲覧：ログイン済みメンバー全員
create policy members_read on public.members for select to authenticated using (true);
create policy projects_read on public.projects for select to authenticated using (true);
create policy assignments_read on public.assignments for select to authenticated using (true);
create policy events_read on public.events for select to authenticated using (true);

-- 編集：自分のプロフィールと予定は本人、案件・配置は管理者
create policy members_update_self on public.members for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid() and is_admin = (select m.is_admin from public.members m where m.id = auth.uid()));
create policy events_write_own on public.events for all to authenticated
  using (member_id = auth.uid()) with check (member_id = auth.uid());
create policy projects_admin on public.projects for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy assignments_admin on public.assignments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy members_admin on public.members for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
