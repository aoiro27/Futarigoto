-- ふたりごと / Supabase
--
-- ダッシュボードでの作業:
-- 1. Authentication → Providers → Anonymous を ON
-- 2. このファイルを SQL Editor で実行
-- 3. Settings → API の Project URL と anon public key を
--    Futarigoto/Services/SupabaseConfig.swift に貼る

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  created_at timestamptz not null default now()
);

create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  invite_code text not null unique check (invite_code ~ '^[A-Z0-9]{6}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.household_members (
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create unique index if not exists household_members_user_id_key
  on public.household_members (user_id);

create table if not exists public.agreements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 100),
  scope_type_raw text not null,
  specific_user_id uuid references public.profiles (id),
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists agreements_household_id_idx
  on public.agreements (household_id);

create table if not exists public.observations (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements (id) on delete cascade,
  author_id uuid not null references public.profiles (id),
  type_raw text not null,
  note text,
  image_path text,
  image_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  published_at timestamptz
);

create index if not exists observations_agreement_id_idx
  on public.observations (agreement_id);
create index if not exists observations_author_id_idx
  on public.observations (author_id);
create index if not exists observations_image_expires_at_idx
  on public.observations (image_expires_at)
  where image_path is not null;

create table if not exists public.reflections (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references public.agreements (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  week_start_date timestamptz not null,
  applicable boolean not null,
  self_reflection_raw text,
  other_applicable boolean,
  other_reflection_raw text,
  completed_at timestamptz not null default now(),
  unique (agreement_id, user_id, week_start_date)
);

create index if not exists reflections_user_week_idx
  on public.reflections (user_id, week_start_date);

-- ---------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER so RLS does not recurse)
-- ---------------------------------------------------------------------------

create or replace function public.current_uid()
returns uuid
language sql
stable
as $$
  select auth.uid();
$$;

create or replace function public.is_household_member(_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members
    where household_id = _household_id
      and user_id = auth.uid()
  );
$$;

create or replace function public.current_household_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select household_id
  from public.household_members
  where user_id = auth.uid()
  limit 1;
$$;

create or replace function public.observation_household_id(_observation public.observations)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select a.household_id
  from public.agreements a
  where a.id = _observation.agreement_id;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.agreements enable row level security;
alter table public.observations enable row level security;
alter table public.reflections enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.household_members mine
      join public.household_members other
        on other.household_id = mine.household_id
      where mine.user_id = (select auth.uid())
        and other.user_id = profiles.id
    )
  );

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists households_select on public.households;
create policy households_select on public.households
  for select to authenticated
  using (public.is_household_member(id));

drop policy if exists members_select on public.household_members;
create policy members_select on public.household_members
  for select to authenticated
  using (public.is_household_member(household_id));

drop policy if exists agreements_select on public.agreements;
create policy agreements_select on public.agreements
  for select to authenticated
  using (public.is_household_member(household_id));

drop policy if exists agreements_insert on public.agreements;
create policy agreements_insert on public.agreements
  for insert to authenticated
  with check (public.is_household_member(household_id));

drop policy if exists agreements_update on public.agreements;
create policy agreements_update on public.agreements
  for update to authenticated
  using (public.is_household_member(household_id))
  with check (public.is_household_member(household_id));

drop policy if exists observations_select on public.observations;
create policy observations_select on public.observations
  for select to authenticated
  using (
    public.is_household_member(public.observation_household_id(observations))
    and (
      author_id = (select auth.uid())
      or published_at is not null
    )
  );

drop policy if exists observations_insert on public.observations;
create policy observations_insert on public.observations
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and public.is_household_member(public.observation_household_id(observations))
  );

drop policy if exists observations_update on public.observations;
create policy observations_update on public.observations
  for update to authenticated
  using (
    author_id = (select auth.uid())
    and public.is_household_member(public.observation_household_id(observations))
  )
  with check (
    author_id = (select auth.uid())
    and public.is_household_member(public.observation_household_id(observations))
  );

drop policy if exists reflections_select on public.reflections;
create policy reflections_select on public.reflections
  for select to authenticated
  using (
    exists (
      select 1
      from public.agreements a
      where a.id = reflections.agreement_id
        and public.is_household_member(a.household_id)
    )
  );

drop policy if exists reflections_insert on public.reflections;
create policy reflections_insert on public.reflections
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.agreements a
      where a.id = reflections.agreement_id
        and public.is_household_member(a.household_id)
    )
  );

drop policy if exists reflections_update on public.reflections;
create policy reflections_update on public.reflections
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create or replace function public.create_household(
  p_household_id uuid,
  p_invite_code text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_existing uuid;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into public.profiles (id, display_name)
  values (v_user, p_display_name)
  on conflict (id) do update
    set display_name = excluded.display_name;

  select household_id into v_existing
  from public.household_members
  where user_id = v_user;

  if v_existing is not null then
    raise exception 'already in a household';
  end if;

  insert into public.households (id, invite_code)
  values (p_household_id, upper(p_invite_code))
  on conflict (id) do nothing;

  if not exists (select 1 from public.households where id = p_household_id) then
    raise exception 'could not create household';
  end if;

  if (
    select count(*) from public.household_members where household_id = p_household_id
  ) >= 2 then
    raise exception 'household full';
  end if;

  insert into public.household_members (household_id, user_id)
  values (p_household_id, v_user)
  on conflict do nothing;

  if exists (
    select 1 from public.household_members
    where household_id = p_household_id and user_id = v_user
  ) then
    return p_household_id;
  end if;

  select household_id into v_existing
  from public.household_members
  where user_id = v_user;
  if v_existing is not null then
    raise exception 'already in a household';
  end if;

  raise exception 'could not create household';
end;
$$;

create or replace function public.join_household(
  p_invite_code text,
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_household uuid;
  v_count integer;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into public.profiles (id, display_name)
  values (v_user, p_display_name)
  on conflict (id) do update
    set display_name = excluded.display_name;

  select id into v_household
  from public.households
  where invite_code = upper(trim(p_invite_code))
  for update;

  if v_household is null then
    raise exception 'invalid invite';
  end if;

  if exists (
    select 1 from public.household_members
    where household_id = v_household and user_id = v_user
  ) then
    return v_household;
  end if;

  if exists (select 1 from public.household_members where user_id = v_user) then
    raise exception 'already in a household';
  end if;

  select count(*) into v_count
  from public.household_members
  where household_id = v_household;

  if v_count >= 2 then
    raise exception 'household full';
  end if;

  insert into public.household_members (household_id, user_id)
  values (v_household, v_user);

  return v_household;
end;
$$;

create or replace function public.fetch_household_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_household uuid := public.current_household_id();
begin
  if v_household is null then
    return null;
  end if;

  return jsonb_build_object(
    'household', (
      select to_jsonb(h) from public.households h where h.id = v_household
    ),
    'users', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.created_at)
      from public.profiles p
      join public.household_members m on m.user_id = p.id
      where m.household_id = v_household
    ), '[]'::jsonb),
    'members', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.joined_at)
      from public.household_members m
      where m.household_id = v_household
    ), '[]'::jsonb),
    'agreements', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at)
      from public.agreements a
      where a.household_id = v_household
    ), '[]'::jsonb),
    'observations', coalesce((
      select jsonb_agg(to_jsonb(o) order by o.created_at)
      from public.observations o
      join public.agreements a on a.id = o.agreement_id
      where a.household_id = v_household
        and (
          o.author_id = auth.uid()
          or o.published_at is not null
        )
    ), '[]'::jsonb),
    'reflections', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.completed_at)
      from public.reflections r
      join public.agreements a on a.id = r.agreement_id
      where a.household_id = v_household
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.publish_household_observations()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household uuid := public.current_household_id();
begin
  if v_household is null then
    return;
  end if;

  update public.observations o
  set
    published_at = coalesce(o.published_at, now()),
    updated_at = now()
  from public.agreements a
  where o.agreement_id = a.id
    and a.household_id = v_household
    and o.deleted_at is null
    and o.published_at is null;
end;
$$;

create or replace function public.cleanup_expired_observation_photos()
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_household uuid := public.current_household_id();
begin
  if v_household is null then
    return;
  end if;

  delete from storage.objects obj
  using public.observations o
  join public.agreements a on a.id = o.agreement_id
  where obj.bucket_id = 'observation-photos'
    and obj.name = o.image_path
    and a.household_id = v_household
    and o.image_path is not null
    and o.image_expires_at is not null
    and o.image_expires_at <= now();

  update public.observations o
  set
    image_path = null,
    image_expires_at = null,
    updated_at = now()
  from public.agreements a
  where o.agreement_id = a.id
    and a.household_id = v_household
    and o.image_path is not null
    and o.image_expires_at is not null
    and o.image_expires_at <= now();
end;
$$;

grant execute on function public.current_uid() to authenticated;
grant execute on function public.is_household_member(uuid) to authenticated;
grant execute on function public.current_household_id() to authenticated;
grant execute on function public.create_household(uuid, text, text) to authenticated;
grant execute on function public.join_household(text, text) to authenticated;
grant execute on function public.fetch_household_state() to authenticated;
grant execute on function public.publish_household_observations() to authenticated;
grant execute on function public.cleanup_expired_observation_photos() to authenticated;

revoke execute on function public.create_household(uuid, text, text) from public, anon;
revoke execute on function public.join_household(text, text) from public, anon;
revoke execute on function public.fetch_household_state() from public, anon;
revoke execute on function public.publish_household_observations() from public, anon;
revoke execute on function public.cleanup_expired_observation_photos() from public, anon;

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'observation-photos',
  'observation-photos',
  false,
  5242880,
  array['image/jpeg']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists observation_photos_select on storage.objects;
create policy observation_photos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'observation-photos'
    and public.is_household_member(nullif(split_part(name, '/', 1), '')::uuid)
    and exists (
      select 1
      from public.observations o
      where o.id = nullif(replace(split_part(name, '/', 2), '.jpg', ''), '')::uuid
        and (
          o.author_id = (select auth.uid())
          or o.published_at is not null
        )
    )
  );

drop policy if exists observation_photos_insert on storage.objects;
create policy observation_photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'observation-photos'
    and public.is_household_member(nullif(split_part(name, '/', 1), '')::uuid)
  );

drop policy if exists observation_photos_update on storage.objects;
create policy observation_photos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'observation-photos'
    and public.is_household_member(nullif(split_part(name, '/', 1), '')::uuid)
  )
  with check (
    bucket_id = 'observation-photos'
    and public.is_household_member(nullif(split_part(name, '/', 1), '')::uuid)
  );

drop policy if exists observation_photos_delete on storage.objects;
create policy observation_photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'observation-photos'
    and public.is_household_member(nullif(split_part(name, '/', 1), '')::uuid)
  );
