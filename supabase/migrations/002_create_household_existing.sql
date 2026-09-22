-- 家庭をつくるとき、既存メンバーなら新しい招待コードを黙って捨てない。
-- クライアントは already in a household を見て、新しい匿名ユーザーで作り直す。

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
