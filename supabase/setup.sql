-- Per la Maglia: database della classifica condivisa
-- Incolla tutto in Supabase > SQL Editor > New query, poi premi Run.

-- Squadre ammesse (Serie A 2026/27)
create or replace function public.valid_team(t text) returns boolean
language sql immutable as $$
  select t = any (array['Atalanta','Bologna','Cagliari','Como','Fiorentina','Frosinone','Genoa','Inter','Juventus','Lazio',
                        'Lecce','Milan','Monza','Napoli','Parma','Roma','Sassuolo','Torino','Udinese','Venezia'])
$$;

-- Settimana di gioco (lunedì 00:00 ora di Roma), es. 2026-W43
create or replace function public.week_id(ts timestamptz) returns text
language sql immutable as $$
  select to_char(ts at time zone 'Europe/Rome', 'IYYY') || '-W' || to_char(ts at time zone 'Europe/Rome', 'IW')
$$;

-- Giocatori: uno per telefono (accesso anonimo)
create table if not exists public.players (
  id uuid primary key references auth.users (id) on delete cascade,
  nick text not null default 'Tifoso' check (char_length(nick) between 1 and 16),
  team text check (team is null or public.valid_team(team)),
  updated_at timestamptz not null default now()
);

-- Partite giocate
create table if not exists public.games (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  team text not null check (public.valid_team(team)),
  season text not null,
  score integer not null check (score >= 0),
  shots integer not null check (shots >= 0),
  goals integer not null check (goals >= 0),
  perfect integer not null default 0,
  top_bar integer not null default 0,
  best_streak integer not null default 0,
  duration_s numeric not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists games_season_team on public.games (season, team);
create index if not exists games_player on public.games (player_id);

alter table public.players enable row level security;
alter table public.games enable row level security;

-- Tutti possono leggere (la classifica è pubblica); nessuno scrive direttamente nelle tabelle
drop policy if exists "players leggibili" on public.players;
create policy "players leggibili" on public.players for select using (true);
drop policy if exists "games leggibili" on public.games;
create policy "games leggibili" on public.games for select using (true);
revoke all on public.players, public.games from anon, authenticated;
grant select on public.players, public.games to anon, authenticated;

-- Profilo: soprannome e squadra del giocatore collegato
create or replace function public.set_profile(p_nick text, p_team text) returns void
language plpgsql security definer set search_path = public as $$
declare n text := left(trim(regexp_replace(coalesce(p_nick, ''), '[<>"''`\\]', '', 'g')), 16);
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if n = '' then n := 'Tifoso'; end if;
  insert into players (id, nick, team, updated_at) values (auth.uid(), n, case when valid_team(p_team) then p_team end, now())
  on conflict (id) do update set nick = excluded.nick, team = coalesce(excluded.team, players.team), updated_at = now();
end $$;

-- Invio di una partita, con controlli contro i punteggi impossibili
create or replace function public.submit_game(p_team text, p_score int, p_shots int, p_goals int, p_perfect int, p_top int,
                                              p_best_streak int, p_duration numeric, p_nick text) returns bigint
language plpgsql security definer set search_path = public as $$
declare gid bigint; last_at timestamptz;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not valid_team(p_team) then raise exception 'bad team'; end if;
  -- una partita finisce con 3 errori (o prima, se esci): mai più di 3 tiri sbagliati
  if p_goals < 0 or p_goals > p_shots or p_shots - p_goals > 3 then raise exception 'bad shots'; end if;
  if p_perfect > p_goals or p_top > p_goals or p_best_streak > p_goals then raise exception 'bad details'; end if;
  -- il massimo teorico per gol è 2.025 punti (traversa 300 + bonus 150, arco ×1,5, serie ×3)
  if p_score > p_goals * 2025 then raise exception 'bad score'; end if;
  -- almeno un secondo e mezzo a tiro, e non più di 3 ore
  if p_duration < p_shots * 1.5 or p_duration > 10800 then raise exception 'bad duration'; end if;
  -- al massimo una partita ogni 10 secondi per giocatore
  select max(created_at) into last_at from games where player_id = auth.uid();
  if last_at is not null and now() - last_at < interval '10 seconds' then raise exception 'too fast'; end if;
  perform set_profile(p_nick, p_team);
  insert into games (player_id, team, season, score, shots, goals, perfect, top_bar, best_streak, duration_s)
  values (auth.uid(), p_team, week_id(now()), p_score, p_shots, p_goals, coalesce(p_perfect, 0), coalesce(p_top, 0), coalesce(p_best_streak, 0), p_duration)
  returning id into gid;
  return gid;
end $$;

revoke all on function public.set_profile(text, text) from public, anon;
revoke all on function public.submit_game(text, int, int, int, int, int, int, numeric, text) from public, anon;
grant execute on function public.set_profile(text, text) to authenticated;
grant execute on function public.submit_game(text, int, int, int, int, int, int, numeric, text) to authenticated;

-- Classifica squadre della settimana: punti e numero di tifosi
create or replace view public.team_week as
  select season, team, sum(score)::bigint as pts, count(distinct player_id)::int as fans
  from public.games group by season, team;

-- Record di ogni squadra nella settimana, con chi l'ha fatto
create or replace view public.team_record as
  select distinct on (g.season, g.team) g.season, g.team, g.score as pts, p.nick
  from public.games g join public.players p on p.id = g.player_id
  order by g.season, g.team, g.score desc, g.created_at;

-- Tifosi di ogni squadra nella settimana, con il loro totale per quella squadra
create or replace view public.team_fans as
  select g.season, g.team, g.player_id, p.nick, sum(g.score)::bigint as pts, count(*)::int as games
  from public.games g join public.players p on p.id = g.player_id
  group by g.season, g.team, g.player_id, p.nick;

-- Statistiche di ogni giocatore per squadra (di sempre) e livello (punti totali)
create or replace view public.player_team_stats as
  select player_id, team, count(*)::int as games, sum(score)::bigint as points, max(score) as best, sum(shots)::int as shots,
         sum(goals)::int as goals, sum(perfect)::int as perfect, sum(top_bar)::int as top, max(best_streak) as best_streak
  from public.games group by player_id, team;

-- Albo d'oro: la squadra vincitrice di ogni settimana
create or replace view public.season_winners as
  select distinct on (season) season, team, pts from public.team_week order by season, pts desc;

grant select on public.team_week, public.team_record, public.team_fans, public.player_team_stats, public.season_winners to anon, authenticated;
