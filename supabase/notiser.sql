-- VARV. – notiser och vänners aktivitet
-- Kör hela filen en gång i Supabase: SQL Editor → New query → klistra in → Run.
-- Går att köra igen utan att något försvinner. Kräver att profiler.sql redan är körd.
--
-- Det här skapas:
--   activity    – pass och lopp som visas för vänner och skickas som notis
--   push_subs   – telefoner och datorer som har slagit på notiser
--   ett jobb som varje timme skickar dagens påminnelser
--   en trigger som skickar en notis till vänner när någon tävlar eller loggar
--
-- Innan du kör: byt ut HEMLIG_NYCKEL längst ned mot samma hemlighet som du
-- sätter som CRON_SECRET på funktionen varv-push (se README).

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ---------- Aktivitet ----------
create table if not exists public.activity (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade default auth.uid(),
  kind       text not null check (kind in ('pass', 'lopp', 'rekord')),
  title      text not null check (char_length(title) <= 80),
  detail     text check (detail is null or char_length(detail) <= 160),
  created_at timestamptz not null default now()
);
create index if not exists activity_user_time on public.activity (user_id, created_at desc);

alter table public.activity enable row level security;
drop policy if exists "Se aktivitet" on public.activity;
drop policy if exists "Skapa egen aktivitet" on public.activity;
drop policy if exists "Ta bort egen aktivitet" on public.activity;
-- Du ser din egen aktivitet och aktivitet från dem som har lagt till dig som vän.
create policy "Se aktivitet" on public.activity
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.friends f
               where f.user_id = activity.user_id and f.friend_id = (select auth.uid()))
  );
create policy "Skapa egen aktivitet" on public.activity
  for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Ta bort egen aktivitet" on public.activity
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------- Notiser ----------
create table if not exists public.push_subs (
  endpoint   text primary key check (char_length(endpoint) < 1000),
  user_id    uuid not null references auth.users (id) on delete cascade default auth.uid(),
  sub        jsonb not null check (pg_column_size(sub) < 2000),
  tz         text not null default 'Europe/Stockholm' check (char_length(tz) < 60),
  hour       integer not null default 8 check (hour between 0 and 23),
  prefs      jsonb not null default '{"plan":true,"race":true,"friends":true}'::jsonb check (pg_column_size(prefs) < 500),
  schedule   jsonb not null default '{}'::jsonb check (pg_column_size(schedule) < 8000),
  last_daily date,
  updated_at timestamptz not null default now()
);
create index if not exists push_subs_user on public.push_subs (user_id);

alter table public.push_subs enable row level security;
drop policy if exists "Egna notiser" on public.push_subs;
create policy "Egna notiser" on public.push_subs
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------- Inställningar för funktionen ----------
create schema if not exists private;
create table if not exists private.push_config (
  id     integer primary key default 1 check (id = 1),
  url    text not null,
  secret text not null
);
revoke all on private.push_config from public, anon, authenticated;

insert into private.push_config (id, url, secret)
values (1, 'https://kwjnezbazyahyzsmpuyg.supabase.co/functions/v1/varv-push', 'HEMLIG_NYCKEL')
on conflict (id) do update set url = excluded.url, secret = excluded.secret;

create or replace function private.varv_push_call(body jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare c record;
begin
  select url, secret into c from private.push_config where id = 1;
  if c.url is null then return; end if;
  perform net.http_post(
    url := c.url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-varv-secret', c.secret),
    body := body
  );
end;
$$;
revoke all on function private.varv_push_call(jsonb) from public, anon, authenticated;

-- Notis till vänner när någon loggar ett pass eller tävlar.
create or replace function public.varv_on_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.varv_push_call(jsonb_build_object('kind', 'activity', 'id', new.id));
  return new;
end;
$$;
revoke all on function public.varv_on_activity() from public, anon, authenticated;

drop trigger if exists varv_activity_push on public.activity;
create trigger varv_activity_push
  after insert on public.activity
  for each row execute function public.varv_on_activity();

-- Dagens påminnelser: funktionen körs varje timme och skickar till dem
-- vars valda klockslag är nu i deras egen tidszon.
select cron.unschedule('varv-daily') where exists (select 1 from cron.job where jobname = 'varv-daily');
select cron.schedule('varv-daily', '2 * * * *', $$ select private.varv_push_call('{"kind":"daily"}'::jsonb) $$);

-- Gammal aktivitet städas bort efter 60 dagar.
select cron.unschedule('varv-activity-clean') where exists (select 1 from cron.job where jobname = 'varv-activity-clean');
select cron.schedule('varv-activity-clean', '30 3 * * *', $$ delete from public.activity where created_at < now() - interval '60 days' $$);

-- ---------- Kalender att prenumerera på ----------
-- Appen sparar planen som en kalenderfil här. Kalender på telefonen hämtar den
-- via funktionen varv-cal med en hemlig länk, och tar bort den med ett tryck.
create table if not exists public.cal_feeds (
  user_id    uuid primary key references auth.users (id) on delete cascade default auth.uid(),
  token      text not null unique default replace(gen_random_uuid()::text, '-', ''),
  ics        text not null default '' check (char_length(ics) < 300000),
  updated_at timestamptz not null default now()
);
alter table public.cal_feeds enable row level security;
drop policy if exists "Egen kalender" on public.cal_feeds;
create policy "Egen kalender" on public.cal_feeds
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
