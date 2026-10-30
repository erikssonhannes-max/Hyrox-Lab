-- VARV. – databas för inloggade användare
-- Kör hela filen en gång i Supabase: SQL Editor → New query → klistra in → Run.
--
-- Varje användare har egna rader: pass (id = passets id), rekord (id = "meta")
-- och inställningar (id = "settings"). Radnivåskyddet gör att man bara kan
-- läsa och ändra sina egna rader.

create table if not exists public.user_docs (
  user_id    uuid        not null references auth.users (id) on delete cascade,
  id         text        not null check (char_length(id) between 1 and 80),
  data       jsonb       not null default '{}'::jsonb check (pg_column_size(data) < 200000),
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

alter table public.user_docs enable row level security;

drop policy if exists "Läsa egna" on public.user_docs;
drop policy if exists "Skapa egna" on public.user_docs;
drop policy if exists "Ändra egna" on public.user_docs;
drop policy if exists "Ta bort egna" on public.user_docs;

create policy "Läsa egna" on public.user_docs
  for select to authenticated using ((select auth.uid()) = user_id);

create policy "Skapa egna" on public.user_docs
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy "Ändra egna" on public.user_docs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Ta bort egna" on public.user_docs
  for delete to authenticated using ((select auth.uid()) = user_id);
