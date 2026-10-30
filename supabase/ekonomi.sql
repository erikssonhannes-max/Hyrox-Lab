-- VARV. – ekonomi på den interna sidan
-- Kör hela filen en gång i Supabase: SQL Editor → New query → klistra in → Run.
-- Går att köra igen utan att något försvinner. Kräver att stats.sql redan körts,
-- eftersom samma hemliga kod används.
--
-- Ekonomin ligger i schemat private, som appens användare aldrig kommer åt.
-- Den interna sidan läser och skriver bara via funktionerna nedan, och de
-- svarar bara den som skickar med rätt kod.

create schema if not exists private;
revoke all on schema private from anon, authenticated;

create table if not exists private.finance_tx (
  id         bigint generated always as identity primary key,
  day        date not null,
  what       text not null check (char_length(what) between 1 and 200),
  amount     numeric(12,2) not null check (amount > 0 and amount < 10000000),
  direction  text not null check (direction in ('in', 'ut')),
  category   text not null default 'Övrigt' check (char_length(category) <= 60),
  who        text check (who is null or char_length(who) <= 60),
  created_at timestamptz not null default now()
);

create table if not exists private.finance_services (
  id           bigint generated always as identity primary key,
  name         text not null check (char_length(name) between 1 and 80),
  purpose      text check (purpose is null or char_length(purpose) <= 200),
  plan         text check (plan is null or char_length(plan) <= 80),
  monthly_cost numeric(12,2) check (monthly_cost is null or (monthly_cost >= 0 and monthly_cost < 1000000)),
  owner        text check (owner is null or char_length(owner) <= 60),
  note         text check (note is null or char_length(note) <= 300),
  created_at   timestamptz not null default now()
);

create table if not exists private.finance_settings (
  key   text primary key,
  value jsonb not null
);

alter table private.finance_tx       enable row level security;
alter table private.finance_services enable row level security;
alter table private.finance_settings enable row level security;

-- Tjänsterna ni använder i dag. Läggs bara in om listan är tom.
insert into private.finance_services (name, purpose, plan, monthly_cost, owner, note)
select * from (values
  ('Squarespace Domains', 'Domänen varvtraining.com', 'Betald, årsvis', null::numeric, 'Hannes', 'Årspriset delat med 12'),
  ('Google Workspace', 'E-post för hannes@ och johan@', 'Betald per användare', null::numeric, 'Hannes', 'Pris per användare gånger antal konton'),
  ('GitHub', 'Koden och hemsidan', 'Gratis', 0, 'Hannes', null),
  ('Supabase', 'Konton, databas och profilbilder', 'Free', 0, 'Johan', 'Gratis upp till 50 000 aktiva användare i månaden'),
  ('Resend', 'Inloggningsmejl', 'Free', 0, 'Hannes', 'Gratis upp till 3 000 mejl i månaden'),
  ('TikTok', '@varvtraining', 'Gratis', 0, 'Johan', null),
  ('LinkedIn', 'Företagssidan', 'Gratis', 0, 'Hannes', null)
) as v
where not exists (select 1 from private.finance_services);

create or replace function public.varv_finance(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from private.stats_token t where t.token = p_token) then
    raise exception 'Fel kod';
  end if;
  return jsonb_build_object(
    'start_balance', coalesce((select (s.value->>'amount')::numeric from private.finance_settings s where s.key = 'start_balance'), 0),
    'start_date',    (select s.value->>'date' from private.finance_settings s where s.key = 'start_balance'),
    'tx',            coalesce((select jsonb_agg(to_jsonb(t) order by t.day desc, t.id desc) from private.finance_tx t), '[]'::jsonb),
    'services',      coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from private.finance_services s), '[]'::jsonb)
  );
end;
$$;

create or replace function public.varv_finance_save(p_token text, p_action text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from private.stats_token t where t.token = p_token) then
    raise exception 'Fel kod';
  end if;

  if p_action = 'tx_add' then
    insert into private.finance_tx (day, what, amount, direction, category, who)
    values ((p_data->>'day')::date,
            trim(p_data->>'what'),
            (p_data->>'amount')::numeric,
            p_data->>'direction',
            coalesce(nullif(trim(p_data->>'category'), ''), 'Övrigt'),
            nullif(trim(p_data->>'who'), ''));
  elsif p_action = 'tx_delete' then
    delete from private.finance_tx where id = (p_data->>'id')::bigint;
  elsif p_action = 'service_save' then
    if nullif(p_data->>'id', '') is not null then
      update private.finance_services set
        name         = coalesce(nullif(trim(p_data->>'name'), ''), name),
        purpose      = nullif(trim(p_data->>'purpose'), ''),
        plan         = nullif(trim(p_data->>'plan'), ''),
        monthly_cost = nullif(p_data->>'monthly_cost', '')::numeric,
        owner        = nullif(trim(p_data->>'owner'), ''),
        note         = nullif(trim(p_data->>'note'), '')
      where id = (p_data->>'id')::bigint;
    else
      insert into private.finance_services (name, purpose, plan, monthly_cost, owner, note)
      values (trim(p_data->>'name'), nullif(trim(p_data->>'purpose'), ''), nullif(trim(p_data->>'plan'), ''),
              nullif(p_data->>'monthly_cost', '')::numeric, nullif(trim(p_data->>'owner'), ''), nullif(trim(p_data->>'note'), ''));
    end if;
  elsif p_action = 'service_delete' then
    delete from private.finance_services where id = (p_data->>'id')::bigint;
  elsif p_action = 'start_balance' then
    insert into private.finance_settings (key, value)
    values ('start_balance', jsonb_build_object('amount', (p_data->>'amount')::numeric, 'date', p_data->>'date'))
    on conflict (key) do update set value = excluded.value;
  else
    raise exception 'Okänd åtgärd';
  end if;

  return public.varv_finance(p_token);
end;
$$;

revoke all on function public.varv_finance(text) from public;
revoke all on function public.varv_finance_save(text, text, jsonb) from public;
grant execute on function public.varv_finance(text) to anon, authenticated;
grant execute on function public.varv_finance_save(text, text, jsonb) to anon, authenticated;

select count(*) as "Tjänster i listan" from private.finance_services;
