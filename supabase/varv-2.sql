-- VARV. – tummar upp, loppkalender och felrapporter
-- Kör hela filen en gång i Supabase: SQL Editor → New query → klistra in → Run.
-- Kräver att profiler.sql och notiser.sql redan är körda. Går att köra igen.

-- ---------- Tummar upp ----------
create table if not exists public.activity_likes (
  activity_id bigint not null references public.activity (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade default auth.uid(),
  created_at  timestamptz not null default now(),
  primary key (activity_id, user_id)
);
alter table public.activity_likes enable row level security;
drop policy if exists "Se tummar" on public.activity_likes;
drop policy if exists "Ge tumme" on public.activity_likes;
drop policy if exists "Ta bort tumme" on public.activity_likes;
-- Du ser tummar på aktivitet som du själv får se.
create policy "Se tummar" on public.activity_likes for select to authenticated
  using (exists (select 1 from public.activity a where a.id = activity_likes.activity_id));
create policy "Ge tumme" on public.activity_likes for insert to authenticated
  with check (user_id = (select auth.uid())
    and exists (select 1 from public.activity a where a.id = activity_likes.activity_id and a.user_id <> (select auth.uid())));
create policy "Ta bort tumme" on public.activity_likes for delete to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.varv_on_like()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.varv_push_call(jsonb_build_object('kind', 'like', 'activity', new.activity_id, 'user', new.user_id));
  return new;
end; $$;
revoke all on function public.varv_on_like() from public, anon, authenticated;
drop trigger if exists varv_like_push on public.activity_likes;
create trigger varv_like_push after insert on public.activity_likes
  for each row execute function public.varv_on_like();

-- ---------- Loppkalender ----------
-- Teamet lägger in och ändrar lopp här (Table Editor → events), utan att röra koden.
-- Appen visar dessa lopp i stället för listan i koden så fort tabellen har innehåll.
create table if not exists public.events (
  id         bigint generated always as identity primary key,
  city       text not null check (char_length(city) <= 60),
  country    text not null check (char_length(country) <= 60),
  region     text not null default 'varlden' check (region in ('norden', 'europa', 'varlden')),
  starts     date not null,
  ends       date not null,
  venue      text check (venue is null or char_length(venue) <= 120),
  kind       text check (kind is null or kind in ('pre', 'vm')),
  url        text check (url is null or char_length(url) <= 300),
  hidden     boolean not null default false,
  created_at timestamptz not null default now(),
  check (ends >= starts)
);
alter table public.events enable row level security;
drop policy if exists "Alla ser lopp" on public.events;
create policy "Alla ser lopp" on public.events for select to anon, authenticated using (not hidden);

-- ---------- Felrapporter ----------
create table if not exists public.errors (
  id         bigint generated always as identity primary key,
  msg        text not null check (char_length(msg) <= 300),
  src        text check (src is null or char_length(src) <= 200),
  view       text check (view is null or char_length(view) <= 30),
  ua         text check (ua is null or char_length(ua) <= 200),
  ver        text check (ver is null or char_length(ver) <= 20),
  created_at timestamptz not null default now()
);
alter table public.errors enable row level security;
drop policy if exists "Rapportera fel" on public.errors;
-- Alla kan skicka in en felrapport, ingen kan läsa dem via appen.
create policy "Rapportera fel" on public.errors for insert to anon, authenticated with check (true);

select cron.unschedule('varv-errors-clean') where exists (select 1 from cron.job where jobname = 'varv-errors-clean');
select cron.schedule('varv-errors-clean', '40 3 * * *', $$ delete from public.errors where created_at < now() - interval '30 days' $$);

-- Felrapporterna visas på teamets sida med samma kod som statistiken.
create or replace function public.varv_errors(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from private.stats_token t where t.token = p_token) then
    raise exception 'Fel kod';
  end if;
  return jsonb_build_object(
    'total_7d', (select count(*) from public.errors where created_at > now() - interval '7 days'),
    'top', coalesce((select jsonb_agg(x) from (
        select msg, count(*) as n, max(created_at) as last, (array_agg(view order by created_at desc))[1] as view,
               (array_agg(ver order by created_at desc))[1] as ver
        from public.errors where created_at > now() - interval '30 days'
        group by msg order by count(*) desc, max(created_at) desc limit 25) x), '[]'::jsonb));
end; $$;
revoke all on function public.varv_errors(text) from public;
grant execute on function public.varv_errors(text) to anon, authenticated;

-- Startlista: loppen som finns i appen i dag. Läggs bara in om tabellen är tom.
insert into public.events (city, country, region, starts, ends, venue, kind)
select v.city, v.country, v.region, v.starts::date, v.ends::date, v.venue, v.kind from (values
  ('Stockholm', 'Sverige', 'norden', '2026-12-10', '2026-12-13', 'Strawberry Arena, Solna', null),
  ('Helsingfors', 'Finland', 'norden', '2026-12-18', '2026-12-20', null, null),
  ('Köpenhamn', 'Danmark', 'norden', '2027-03-25', '2027-03-28', null, 'pre'),
  ('Birmingham', 'Storbritannien', 'europa', '2026-10-27', '2026-11-01', null, null),
  ('Hamburg', 'Tyskland', 'europa', '2026-10-28', '2026-11-01', null, null),
  ('Nice', 'Frankrike', 'europa', '2026-10-29', '2026-11-01', null, null),
  ('Dublin', 'Irland', 'europa', '2026-11-11', '2026-11-15', null, null),
  ('Düsseldorf', 'Tyskland', 'europa', '2026-11-11', '2026-11-15', null, null),
  ('Barcelona', 'Spanien', 'europa', '2026-11-12', '2026-11-15', null, null),
  ('Poznań', 'Polen', 'europa', '2026-11-20', '2026-11-22', null, null),
  ('Utrecht', 'Nederländerna', 'europa', '2026-11-26', '2026-11-29', null, null),
  ('London', 'Storbritannien', 'europa', '2026-12-02', '2026-12-06', 'ExCeL', null),
  ('Milano', 'Italien', 'europa', '2026-12-05', '2026-12-06', null, null),
  ('Frankfurt', 'Tyskland', 'europa', '2026-12-10', '2026-12-13', null, null),
  ('Paris', 'Frankrike', 'europa', '2026-12-12', '2026-12-20', null, null),
  ('Gent', 'Belgien', 'europa', '2026-12-17', '2026-12-20', null, null),
  ('Mexico City', 'Mexiko', 'varlden', '2026-10-30', '2026-11-01', null, null),
  ('Denver', 'USA', 'varlden', '2026-11-13', '2026-11-16', null, null),
  ('Seoul', 'Sydkorea', 'varlden', '2026-11-14', '2026-11-15', null, null),
  ('Kairo', 'Egypten', 'varlden', '2026-11-14', '2026-11-15', null, null),
  ('Dallas', 'USA', 'varlden', '2026-11-18', '2026-11-22', null, null),
  ('Rio de Janeiro', 'Brasilien', 'varlden', '2026-11-21', '2026-11-21', null, null),
  ('Guangzhou', 'Kina', 'varlden', '2026-11-21', '2026-11-22', null, null),
  ('Gujarat', 'Indien', 'varlden', '2026-11-26', '2026-11-28', null, null),
  ('Singapore', 'Singapore', 'varlden', '2026-11-26', '2026-11-29', null, null),
  ('Dubai', 'Förenade Arabemiraten', 'varlden', '2026-11-27', '2026-11-28', null, null),
  ('Johannesburg', 'Sydafrika', 'varlden', '2026-11-27', '2026-11-29', null, null),
  ('Anaheim', 'USA', 'varlden', '2026-12-03', '2026-12-06', null, null),
  ('Sanya', 'Kina', 'varlden', '2026-12-05', '2026-12-06', null, null),
  ('Melbourne', 'Australien', 'varlden', '2026-12-09', '2026-12-13', null, null),
  ('Kuala Lumpur', 'Malaysia', 'varlden', '2026-12-10', '2026-12-13', null, null),
  ('Nashville', 'USA', 'varlden', '2026-12-10', '2026-12-13', null, null),
  ('Vancouver', 'Kanada', 'varlden', '2026-12-18', '2026-12-20', null, null),
  ('Chicago', 'USA', 'varlden', '2027-02-11', '2027-02-15', null, 'pre'),
  ('Cancún', 'Mexiko', 'varlden', '2027-02-19', '2027-02-21', null, 'pre'),
  ('Phoenix', 'USA', 'varlden', '2027-02-25', '2027-02-28', null, 'pre'),
  ('Las Vegas', 'USA', 'varlden', '2027-03-12', '2027-03-14', null, 'pre'),
  ('Guadalajara', 'Mexiko', 'varlden', '2027-03-19', '2027-03-21', null, 'pre'),
  ('Miami Beach', 'USA', 'varlden', '2027-03-26', '2027-03-28', null, 'pre'),
  ('Houston', 'USA', 'varlden', '2027-04-01', '2027-04-04', null, 'pre'),
  ('Monterrey', 'Mexiko', 'varlden', '2027-04-16', '2027-04-18', null, 'pre'),
  ('Ottawa', 'Kanada', 'varlden', '2027-04-21', '2027-04-25', null, 'pre'),
  ('Atlanta', 'USA', 'varlden', '2027-04-23', '2027-04-25', null, 'pre'),
  ('San Diego', 'USA', 'varlden', '2027-05-13', '2027-05-16', null, 'pre'),
  ('Portland', 'USA', 'varlden', '2027-05-21', '2027-05-23', null, 'pre'),
  ('Puebla', 'Mexiko', 'varlden', '2027-05-28', '2027-05-30', null, 'pre'),
  ('Hongkong', 'Kina', 'varlden', '2027-06-10', '2027-06-13', 'AsiaWorld-Expo', 'vm')
) as v(city, country, region, starts, ends, venue, kind)
where not exists (select 1 from public.events);
