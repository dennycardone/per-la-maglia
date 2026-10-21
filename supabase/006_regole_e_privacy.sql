-- Per la Maglia · aggiornamento 6: Reggiana in Serie C, segnalazioni degli sfottò, eliminazione dei dati
-- Incolla tutto in Supabase > SQL Editor > New query e premi Run. Richiede di aver già eseguito 004 e 005.

-- 1) Serie C: la Reggiana al posto della Sambenedettese
create or replace function public.league_teams(l text) returns text[]
language sql immutable as $$
  select case l
    when 'serie-a' then array['Atalanta','Bologna','Cagliari','Como','Fiorentina','Frosinone','Genoa','Inter','Juventus','Lazio',
                              'Lecce','Milan','Monza','Napoli','Parma','Roma','Sassuolo','Torino','Udinese','Venezia']
    when 'serie-b' then array['Arezzo','Ascoli','Avellino','Benevento','Carrarese','Catanzaro','Cesena','Cremonese','Empoli','Hellas Verona',
                              'Juve Stabia','Mantova','Modena','Padova','Palermo','Pisa','Sampdoria','Südtirol','Vicenza','Virtus Entella']
    when 'serie-c' then array['Bari','Casertana','Catania','Cosenza','Crotone','Foggia','Lecco','Livorno','Monopoli','Novara',
                              'Perugia','Pescara','Potenza','Pro Vercelli','Ravenna','Reggiana','Salernitana','Spezia','Treviso','Union Brescia']
    else array[]::text[] end
$$;

-- 2) Segnalazioni: con 3 segnalazioni di tifosi diversi lo sfottò sparisce per tutti
alter table public.taunts add column if not exists hidden boolean not null default false;
create table if not exists public.taunt_reports (
  taunt_id bigint not null references public.taunts (id) on delete cascade,
  reporter uuid not null references public.players (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (taunt_id, reporter)
);
alter table public.taunt_reports enable row level security;
revoke all on public.taunt_reports from anon, authenticated;

drop policy if exists "sfotto leggibili" on public.taunts;
create policy "sfotto leggibili" on public.taunts for select using (not hidden);

create or replace function public.report_taunt(p_taunt_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from players where id = auth.uid()) then
    insert into players (id, nick, updated_at) values (auth.uid(), 'Tifoso', now()) on conflict do nothing;
  end if;
  insert into taunt_reports (taunt_id, reporter) values (p_taunt_id, auth.uid()) on conflict do nothing;
  update taunts set hidden = true
   where id = p_taunt_id and (select count(*) from taunt_reports where taunt_id = p_taunt_id) >= 3;
end $$;
revoke all on function public.report_taunt(bigint) from public, anon;
grant execute on function public.report_taunt(bigint) to authenticated;

-- 3) Elimina i miei dati: cancella l'account anonimo e, a cascata, profilo, partite, sfottò e segnalazioni
create or replace function public.delete_my_data() returns void
language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  delete from public.taunts where player_id = me;
  delete from public.games where player_id = me;
  delete from public.players where id = me;
  delete from auth.users where id = me;
end $$;
revoke all on function public.delete_my_data() from public, anon;
grant execute on function public.delete_my_data() to authenticated;
