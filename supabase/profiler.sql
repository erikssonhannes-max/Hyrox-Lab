-- VARV. – profiler, användarnamn#kod, vänner och profilbilder
-- Kör hela filen en gång i Supabase: SQL Editor → New query → klistra in → Run.
-- Går att köra igen utan att något försvinner.
--
-- Varje konto får automatiskt en profil med ett användarnamn och en fyrsiffrig
-- kod, till exempel Hannes#4821. Koden sätts av databasen och kan inte ändras
-- av användaren. En profil syns för de vänner som ägaren har lagt till. Den som
-- vill kan göra profilen synlig för alla inloggade.

-- ---------- Profiler ----------
create table if not exists public.profiles (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  username      text not null check (username ~ '^[A-Za-z0-9ÅÄÖåäöÉé_.]{2,20}$'),
  tag           text not null check (tag ~ '^[0-9]{4}$'),
  avatar_url    text check (avatar_url is null or char_length(avatar_url) < 500),
  experience    text check (experience in ('ny', 'motionar', 'erfaren', 'elit')),
  races_count   integer not null default 0 check (races_count between 0 and 500),
  best_time     integer check (best_time is null or best_time between 600 and 36000),
  best_division text check (best_division is null or char_length(best_division) <= 60),
  prs           jsonb not null default '{}'::jsonb check (pg_column_size(prs) < 4000),
  next_race     jsonb check (next_race is null or pg_column_size(next_race) < 1000),
  stats         jsonb not null default '{}'::jsonb check (pg_column_size(stats) < 4000),
  partner_id    uuid references auth.users (id) on delete set null,
  is_public     boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index if not exists profiles_name_tag on public.profiles (lower(username), tag);

-- ---------- Vänner ----------
create table if not exists public.friends (
  user_id    uuid not null references auth.users (id) on delete cascade,
  friend_id  uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

alter table public.profiles enable row level security;
alter table public.friends  enable row level security;

drop policy if exists "Se profiler" on public.profiles;
drop policy if exists "Ändra egen profil" on public.profiles;
create policy "Se profiler" on public.profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or is_public
    or exists (select 1 from public.friends f
               where f.user_id = profiles.user_id and f.friend_id = (select auth.uid()))
  );
create policy "Ändra egen profil" on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Se egna vänner" on public.friends;
drop policy if exists "Lägga till vän" on public.friends;
drop policy if exists "Ta bort vän" on public.friends;
create policy "Se egna vänner" on public.friends
  for select to authenticated
  using (user_id = (select auth.uid()) or friend_id = (select auth.uid()));
create policy "Lägga till vän" on public.friends
  for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Ta bort vän" on public.friends
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Koden, ägaren och skapad-datum går aldrig att ändra.
create or replace function public.varv_profiles_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.user_id    := old.user_id;
  new.tag        := old.tag;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists varv_profiles_guard on public.profiles;
create trigger varv_profiles_guard
  before update on public.profiles
  for each row execute function public.varv_profiles_guard();

-- Skapa profil med användarnamn och en ledig fyrsiffrig kod.
create or replace function public.varv_create_profile(p_id uuid, p_email text, p_meta jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  base  text;
  t     text;
  tries integer := 0;
begin
  if exists (select 1 from public.profiles where user_id = p_id) then
    return;
  end if;
  base := regexp_replace(coalesce(nullif(p_meta->>'username', ''), split_part(coalesce(p_email, ''), '@', 1)),
                         '[^A-Za-z0-9ÅÄÖåäöÉé_.]', '', 'g');
  base := left(base, 20);
  if char_length(base) < 2 then
    base := 'Varv' || base;
  end if;
  loop
    t := lpad(floor(random() * 10000)::integer::text, 4, '0');
    exit when not exists (select 1 from public.profiles p
                          where lower(p.username) = lower(base) and p.tag = t);
    tries := tries + 1;
    if tries > 40 then
      base := left(base, 17) || floor(random() * 1000)::integer::text;
      tries := 0;
    end if;
  end loop;
  insert into public.profiles (user_id, username, tag) values (p_id, base, t)
  on conflict (user_id) do nothing;
end;
$$;

create or replace function public.varv_on_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.varv_create_profile(new.id, new.email, new.raw_user_meta_data);
  return new;
end;
$$;

drop trigger if exists varv_on_auth_user_created on auth.users;
create trigger varv_on_auth_user_created
  after insert on auth.users
  for each row execute function public.varv_on_new_user();

revoke all on function public.varv_create_profile(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.varv_on_new_user() from public, anon, authenticated;

-- Profiler till konton som redan finns.
select public.varv_create_profile(u.id, u.email, u.raw_user_meta_data)
from auth.users u
where not exists (select 1 from public.profiles p where p.user_id = u.id);

-- Hitta en användare med namn#kod, även om profilen bara visas för vänner.
-- Ger bara namn, kod och profilbild.
create or replace function public.varv_find_user(p_username text, p_tag text)
returns table (user_id uuid, username text, tag text, avatar_url text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.user_id, p.username, p.tag, p.avatar_url
  from public.profiles p
  where (select auth.uid()) is not null
    and lower(p.username) = lower(p_username)
    and p.tag = p_tag
  limit 1;
$$;

revoke all on function public.varv_find_user(text, text) from public, anon;
grant execute on function public.varv_find_user(text, text) to authenticated;

-- Namn och kod för en lista av användare (vänner och partner), även privata.
create or replace function public.varv_names(p_ids uuid[])
returns table (user_id uuid, username text, tag text, avatar_url text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.user_id, p.username, p.tag, p.avatar_url
  from public.profiles p
  where (select auth.uid()) is not null
    and p.user_id = any (p_ids[1:200]);
$$;

revoke all on function public.varv_names(uuid[]) from public, anon;
grant execute on function public.varv_names(uuid[]) to authenticated;

-- ---------- Profilbilder ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 524288, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "Profilbild: se egen" on storage.objects;
drop policy if exists "Profilbild: ladda upp" on storage.objects;
drop policy if exists "Profilbild: byta" on storage.objects;
drop policy if exists "Profilbild: ta bort" on storage.objects;
create policy "Profilbild: se egen" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Profilbild: ladda upp" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Profilbild: byta" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Profilbild: ta bort" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Visa alla profiler med kod, för kontroll.
select username || '#' || tag as "Användare" from public.profiles order by created_at;
