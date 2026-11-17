-- Per la Maglia · 013 · Parità di punti: decidono i punti storici della squadra (non più il numero di tifosi)
-- Regola scritta nel gioco: "A parità di punti contano i punti storici della squadra."
-- Cambia solo l'ordine in caso di parità. Si può eseguire più volte. Richiede lo script 012.
-- Esegui tutto il file in Supabase → SQL Editor → Run.

create or replace function public.lt_moves(p_season text)
returns table (team text, from_league text, to_league text)
language sql stable security definer set search_path = public as $$
  with m as (select league, team from league_members where season = p_season),
  pts as (
    select m.league, m.team,
           coalesce((select sum(g.score) from games g where g.season = p_season and g.league = m.league and g.team = m.team), 0) as p,
           coalesce((select sum(g.score) from games g where g.season < p_season and g.team = m.team), 0) as h
      from m),
  r as (
    select *, row_number() over (partition by league order by p desc, h desc, team) as up,
              row_number() over (partition by league order by p asc, h asc, team desc) as dn
      from pts),
  -- sale solo chi ha fatto punti (al massimo 3) e ne scendono altrettante: se in C fa punti una sola squadra, sale una e scende una
  k as (select least(3, count(*) filter (where league = 'serie-b' and p > 0)) as ab,
               least(3, count(*) filter (where league = 'serie-c' and p > 0)) as bc from pts)
  select team, league, 'serie-b' from r, k where league = 'serie-a' and dn <= k.ab
  union all select team, league, 'serie-a' from r, k where league = 'serie-b' and up <= k.ab
  union all select team, league, 'serie-c' from r, k where league = 'serie-b' and dn <= k.bc
  union all select team, league, 'serie-b' from r, k where league = 'serie-c' and up <= k.bc
$$;
revoke all on function public.lt_moves(text) from public, anon, authenticated;

create or replace function public.leagues_now() returns json
language plpgsql security definer set search_path = public as $$
declare s text := lt_ensure(now()); prev text;
begin
  select max(season) into prev from league_members where season < s;
  return json_build_object(
    'season', s,
    'teams', (select json_agg(json_build_array(league, team) order by league, team) from league_members where season = s),
    'start', lt_start(),
    -- i punti storici di ogni squadra (tutte le settimane prima di questa): decidono le parità, anche nella classifica del gioco
    'hist', (select json_object_agg(m.team, coalesce((select sum(g.score) from games g where g.season < s and g.team = m.team), 0)) from league_members m where m.season = s),
    'moved', case when prev is null or s <= lt_start() then '[]'::json else coalesce((select json_agg(json_build_array(team, from_league, to_league)) from lt_moves(prev)), '[]'::json) end,
    'next', case when is_open(now()) or s < lt_start() then null else coalesce((select json_agg(json_build_array(team, from_league, to_league)) from lt_moves(s)), '[]'::json) end,
    -- quante squadre si scambiano adesso tra A e B e tra B e C (quelle della serie sotto che hanno fatto punti, al massimo 3)
    'swaps', case when s < lt_start() then null else (select json_build_object(
                'ab', least(3, count(distinct team) filter (where league = 'serie-b')),
                'bc', least(3, count(distinct team) filter (where league = 'serie-c')))
              from (select g.league, g.team from games g join league_members m on m.season = s and m.team = g.team and m.league = g.league
                     where g.season = s group by g.league, g.team having sum(g.score) > 0) x) end
  );
end $$;
revoke all on function public.leagues_now() from public;
grant execute on function public.leagues_now() to anon, authenticated;

-- controllo: deve rispondere "ok" e il numero di squadre con i punti storici
select case when (public.leagues_now() -> 'hist') is not null then 'ok' else 'manca hist' end as esito,
       (select count(*) from json_object_keys(public.leagues_now() -> 'hist')) as squadre;
