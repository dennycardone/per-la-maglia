-- Per la Maglia · 012 · Promozioni e retrocessioni
-- Ogni settimana, alla chiusura del campionato: le ultime 3 della Serie A scendono in B e le prime 3 della B salgono in A;
-- le ultime 3 della B scendono in C e le prime 3 della C salgono in B. Le ultime della C restano in C.
-- A parità di punti conta chi ha avuto più tifosi in settimana, poi i punti di tutte le settimane passate.
-- Chi gioca per una squadra la segue nella nuova serie. Le partite già giocate restano dove sono (storico e Albo d'oro intatti).
-- La settimana in cui esegui questo file è la formazione di partenza: i primi cambi avvengono il lunedì successivo.
-- Esegui tutto una volta nell'editor SQL di Supabase. Non cancella nessuna partita.

-- 1) in che serie gioca ogni squadra, settimana per settimana
create table if not exists public.league_members (
  season text not null,
  league text not null check (league in ('serie-a', 'serie-b', 'serie-c')),
  team text not null,
  primary key (season, team)
);
create index if not exists league_members_season_league on public.league_members (season, league);
alter table public.league_members enable row level security;   -- il gioco legge solo con leagues_now()
revoke all on public.league_members from anon, authenticated;

-- 2) chi sale e chi scende alla fine di una settimana
create or replace function public.lt_moves(p_season text)
returns table (team text, from_league text, to_league text)
language sql stable security definer set search_path = public as $$
  with m as (select league, team from league_members where season = p_season),
  pts as (
    select m.league, m.team,
           coalesce((select sum(g.score) from games g where g.season = p_season and g.league = m.league and g.team = m.team), 0) as p,
           coalesce((select count(distinct g.player_id) from games g where g.season = p_season and g.league = m.league and g.team = m.team), 0) as f,
           coalesce((select sum(g.score) from games g where g.season < p_season and g.team = m.team), 0) as h
      from m),
  r as (
    select *, row_number() over (partition by league order by p desc, f desc, h desc, team) as up,
              row_number() over (partition by league order by p asc, f asc, h asc, team desc) as dn
      from pts)
  select team, league, 'serie-b' from r where league = 'serie-a' and dn <= 3
  union all select team, league, 'serie-a' from r where league = 'serie-b' and up <= 3
  union all select team, league, 'serie-c' from r where league = 'serie-b' and dn <= 3
  union all select team, league, 'serie-b' from r where league = 'serie-c' and up <= 3
$$;
revoke all on function public.lt_moves(text) from public, anon, authenticated;

-- 3) prepara la settimana: la prima volta la formazione di partenza, poi i cambi della settimana precedente
create or replace function public.lt_ensure(p_ts timestamptz) returns text
language plpgsql security definer set search_path = public as $$
declare s text := week_id(p_ts); prev text;
begin
  if exists (select 1 from league_members where season = s) then return s; end if;
  perform pg_advisory_xact_lock(4242012);
  if exists (select 1 from league_members where season = s) then return s; end if;
  select max(season) into prev from league_members where season < s;
  if prev is null then
    insert into league_members (season, league, team)
    select s, l, unnest(league_teams(l)) from unnest(array['serie-a', 'serie-b', 'serie-c']) as l;
  else
    insert into league_members (season, league, team)
    select s, coalesce(mv.to_league, m.league), m.team
      from league_members m left join lt_moves(prev) mv on mv.team = m.team
     where m.season = prev;
  end if;
  return s;
end $$;
revoke all on function public.lt_ensure(timestamptz) from public, anon, authenticated;

-- 4) per il gioco: le squadre di ogni serie adesso, i cambi di inizio settimana e (a campionato chiuso) quelli in arrivo
create or replace function public.leagues_now() returns json
language plpgsql security definer set search_path = public as $$
declare s text := lt_ensure(now()); prev text;
begin
  select max(season) into prev from league_members where season < s;
  return json_build_object(
    'season', s,
    'teams', (select json_agg(json_build_array(league, team) order by league, team) from league_members where season = s),
    'moved', case when prev is null then '[]'::json else coalesce((select json_agg(json_build_array(team, from_league, to_league)) from lt_moves(prev)), '[]'::json) end,
    'next', case when is_open(now()) then null else coalesce((select json_agg(json_build_array(team, from_league, to_league)) from lt_moves(s)), '[]'::json) end
  );
end $$;
revoke all on function public.leagues_now() from public;
grant execute on function public.leagues_now() to anon, authenticated;

-- 5) invio partita: la serie è quella in cui la squadra gioca questa settimana (non quella che dice il telefono)
create or replace function public.submit_game_v2(p_league text, p_team text, p_score int, p_shots int, p_goals int, p_perfect int, p_top int,
                                                 p_best_streak int, p_duration numeric, p_nick text) returns bigint
language plpgsql security definer set search_path = public as $$
declare gid bigint; last_at timestamptz; nk text; lg text; s text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  s := lt_ensure(now());
  select league into lg from league_members where season = s and team = p_team;
  if lg is null then raise exception 'bad team'; end if;
  if p_goals < 0 or p_goals > p_shots or p_shots - p_goals > 3 then raise exception 'bad shots'; end if;
  if p_perfect > p_goals or p_top > p_goals or p_best_streak > p_goals then raise exception 'bad details'; end if;
  if p_score > p_goals * 2025 then raise exception 'bad score'; end if;
  if p_duration < p_shots * 1.5 or p_duration > 10800 then raise exception 'bad duration'; end if;
  if not is_open(now() - make_interval(secs => p_duration::double precision))
     or not (is_open(now()) or is_open(now() - interval '30 minutes')) then raise exception 'closed'; end if;
  select max(created_at) into last_at from games where player_id = auth.uid();
  if last_at is not null and now() - last_at < interval '10 seconds' then raise exception 'too fast'; end if;
  nk := left(trim(regexp_replace(coalesce(p_nick, ''), '[<>"''`\\]', '', 'g')), 16);
  if nk = '' or bad_text(nk) then nk := 'Tifoso'; end if;
  perform set_profile(nk, p_team);
  insert into games (player_id, league, team, season, score, shots, goals, perfect, top_bar, best_streak, duration_s, nick)
  values (auth.uid(), lg, p_team, s, p_score, p_shots, p_goals, coalesce(p_perfect, 0), coalesce(p_top, 0), coalesce(p_best_streak, 0), p_duration, nk)
  returning id into gid;
  return gid;
end $$;
revoke all on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) from public, anon;
grant execute on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) to authenticated;

-- 6) la formazione di partenza per questa settimana
select public.lt_ensure(now());
