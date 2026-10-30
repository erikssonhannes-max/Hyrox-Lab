-- VARV. – radera konto
-- Kör en gång i Supabase: SQL Editor → New query → klistra in → Run.
-- Gör att en inloggad användare kan radera sitt eget konto och allt som sparats
-- i det, direkt från appen (Profil → Konto → Radera konto). Krävs av GDPR och App Store.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Inte inloggad';
  end if;
  delete from public.user_docs where user_id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
