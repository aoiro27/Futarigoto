-- 約束単位ではなく、その日の振り返り全体へのひとこと。
create table if not exists public.review_comments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  review_date timestamptz not null,
  text text not null check (char_length(text) <= 500),
  updated_at timestamptz not null default now(),
  unique (household_id, user_id, review_date)
);
alter table public.review_comments enable row level security;

-- 既存の振り返り回答と同じ家庭内共有範囲。
-- アプリでは、ふたりの回答がそろった結果画面で相手のひとことを表示する。
drop policy if exists review_comments_select on public.review_comments;
create policy review_comments_select on public.review_comments for select to authenticated
using (public.is_household_member(household_id));

drop policy if exists review_comments_insert on public.review_comments;
create policy review_comments_insert on public.review_comments for insert to authenticated
with check (user_id = auth.uid() and public.is_household_member(household_id));

drop policy if exists review_comments_update on public.review_comments;
create policy review_comments_update on public.review_comments for update to authenticated
using (user_id = auth.uid() and public.is_household_member(household_id))
with check (user_id = auth.uid() and public.is_household_member(household_id));

grant select, insert, update on public.review_comments to authenticated;
