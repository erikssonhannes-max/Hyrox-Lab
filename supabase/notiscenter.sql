-- VARV. – vänförfrågningar och notiscenter
-- Kräver profiler.sql, notiser.sql och varv-2.sql. Går att köra igen.
--
-- Vänskap är nu ömsesidig: man skickar en förfrågan, den andra godkänner eller
-- avböjer. Alla notiser sparas också i notifications, som visas under ringklockan.

-- ---------- Vänförfrågningar ----------
create table if not exists public.friend_requests (
  from_user  uuid not null references auth.users (id) on delete cascade default auth.uid(),
  to_user    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);
create index if not exists friend_requests_to on public.friend_requests (to_user);
alter table public.friend_requests enable row level security;
drop policy if exists "Se egna förfrågningar" on public.friend_requests;
drop policy if exists "Ta bort förfrågan" on public.friend_requests;
create policy "Se egna förfrågningar" on public.friend_requests for select to authenticated
  using (from_user = (select auth.uid()) or to_user = (select auth.uid()));
-- Ångra en skickad förfrågan eller avböj en som kommit in.
create policy "Ta bort förfrågan" on public.friend_requests for delete to authenticated
  using (from_user = (select auth.uid()) or to_user = (select auth.uid()));

-- Vänner läggs bara till via funktionerna nedan, så att båda alltid har sagt ja.
drop policy if exists "Lägga till vän" on public.friends;
drop policy if exists "Ta bort vän" on public.friends;

create or replace function public.varv_answer_friend(p_from uuid, p_accept boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Inte inloggad'; end if;
  delete from public.friend_requests where from_user = p_from and to_user = me;
  if not found then return 'none'; end if;
  if not p_accept then return 'declined'; end if;
  insert into public.friends (user_id, friend_id) values (me, p_from), (p_from, me) on conflict do nothing;
  perform private.varv_push_call(jsonb_build_object('kind', 'accept', 'from', me, 'to', p_from));
  return 'accepted';
end; $$;

create or replace function public.varv_request_friend(p_to uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Inte inloggad'; end if;
  if p_to = me then return 'self'; end if;
  if not exists (select 1 from public.profiles where user_id = p_to) then return 'none'; end if;
  if exists (select 1 from public.friends where user_id = me and friend_id = p_to)
     and exists (select 1 from public.friends where user_id = p_to and friend_id = me) then return 'friends'; end if;
  -- Har den andra redan frågat dig blir ni vänner direkt.
  if exists (select 1 from public.friend_requests where from_user = p_to and to_user = me) then
    return public.varv_answer_friend(p_to, true);
  end if;
  insert into public.friend_requests (from_user, to_user) values (me, p_to) on conflict do nothing;
  return case when found then 'sent' else 'pending' end;
end; $$;

create or replace function public.varv_remove_friend(p_other uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Inte inloggad'; end if;
  delete from public.friends where (user_id = me and friend_id = p_other) or (user_id = p_other and friend_id = me);
  delete from public.friend_requests where (from_user = me and to_user = p_other) or (from_user = p_other and to_user = me);
  update public.profiles set partner_id = null where user_id = me and partner_id = p_other;
end; $$;

revoke all on function public.varv_answer_friend(uuid, boolean) from public, anon;
revoke all on function public.varv_request_friend(uuid) from public, anon;
revoke all on function public.varv_remove_friend(uuid) from public, anon;
grant execute on function public.varv_answer_friend(uuid, boolean) to authenticated;
grant execute on function public.varv_request_friend(uuid) to authenticated;
grant execute on function public.varv_remove_friend(uuid) to authenticated;

create or replace function public.varv_on_request()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.varv_push_call(jsonb_build_object('kind', 'request', 'from', new.from_user, 'to', new.to_user));
  return new;
end; $$;
revoke all on function public.varv_on_request() from public, anon, authenticated;
drop trigger if exists varv_request_push on public.friend_requests;
create trigger varv_request_push after insert on public.friend_requests
  for each row execute function public.varv_on_request();

-- ---------- Notiscenter ----------
create table if not exists public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  kind       text not null check (char_length(kind) <= 20),
  title      text not null check (char_length(title) <= 120),
  body       text check (body is null or char_length(body) <= 240),
  url        text check (url is null or char_length(url) <= 120),
  actor      uuid references auth.users (id) on delete set null,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_time on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "Se egna notiser" on public.notifications;
drop policy if exists "Läsa egna notiser" on public.notifications;
drop policy if exists "Ta bort egna notiser" on public.notifications;
create policy "Se egna notiser" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Läsa egna notiser" on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Ta bort egna notiser" on public.notifications for delete to authenticated
  using (user_id = (select auth.uid()));

select cron.unschedule('varv-notis-clean') where exists (select 1 from cron.job where jobname = 'varv-notis-clean');
select cron.schedule('varv-notis-clean', '50 3 * * *', $$ delete from public.notifications where created_at < now() - interval '60 days' $$);

-- ---------- Gamla vänner som bara gick åt ett håll blir förfrågningar ----------
insert into public.friend_requests (from_user, to_user, created_at)
select f.user_id, f.friend_id, f.created_at from public.friends f
where not exists (select 1 from public.friends g where g.user_id = f.friend_id and g.friend_id = f.user_id)
on conflict do nothing;
delete from public.friends f
where not exists (select 1 from public.friends g where g.user_id = f.friend_id and g.friend_id = f.user_id);
