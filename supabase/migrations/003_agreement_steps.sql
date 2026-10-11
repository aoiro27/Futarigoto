-- 約束に紐づく「やってみること」。既存の約束・メモは変更しない。
create table if not exists public.agreement_steps (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  text text not null check (char_length(btrim(text)) between 1 and 500),
  review_date timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists agreement_steps_agreement_id_idx on public.agreement_steps(agreement_id);
alter table public.agreement_steps enable row level security;

drop policy if exists agreement_steps_select on public.agreement_steps;
create policy agreement_steps_select on public.agreement_steps for select to authenticated
using (exists (select 1 from public.agreements a where a.id = agreement_id and public.is_household_member(a.household_id)));

drop policy if exists agreement_steps_insert on public.agreement_steps;
create policy agreement_steps_insert on public.agreement_steps for insert to authenticated
with check (author_id = auth.uid() and exists (
  select 1 from public.agreements a where a.id = agreement_id and a.deleted_at is null and public.is_household_member(a.household_id)
));

-- 再同期時の同一IDのupsertを許可。アプリでは追記のみ。
drop policy if exists agreement_steps_update on public.agreement_steps;
create policy agreement_steps_update on public.agreement_steps for update to authenticated
using (author_id = auth.uid() and exists (select 1 from public.agreements a where a.id = agreement_id and public.is_household_member(a.household_id)))
with check (author_id = auth.uid() and exists (select 1 from public.agreements a where a.id = agreement_id and public.is_household_member(a.household_id)));

grant select, insert, update on public.agreement_steps to authenticated;
