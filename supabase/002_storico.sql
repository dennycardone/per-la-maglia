-- Per la Maglia · aggiornamento 2: campionati, MVP e albo d'oro storico
-- Incolla tutto in Supabase > SQL Editor > New query e premi Run. Non cancella nessuna partita.

-- Ogni partita appartiene a un campionato (oggi solo Serie A; in futuro altri)
alter table public.games add column if not exists league text not null default 'serie-a';
create index if not exists games_league_season_team on public.games (league, season, team);

-- Invio partita con il campionato
create or replace function public.submit_game_v2(p_league text, p_team text, p_score int, p_shots int, p_goals int, p_perfect int, p_top int,
                                                 p_best_streak int, p_duration numeric, p_nick text) returns bigint
language plpgsql security definer set search_path = public as $$
declare gid bigint; last_at timestamptz;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_league is distinct from 'serie-a' then raise exception 'bad league'; end if;
  if not valid_team(p_team) then raise exception 'bad team'; end if;
  if p_goals < 0 or p_goals > p_shots or p_shots - p_goals > 3 then raise exception 'bad shots'; end if;
  if p_perfect > p_goals or p_top > p_goals or p_best_streak > p_goals then raise exception 'bad details'; end if;
  if p_score > p_goals * 2025 then raise exception 'bad score'; end if;
  if p_duration < p_shots * 1.5 or p_duration > 10800 then raise exception 'bad duration'; end if;
  select max(created_at) into last_at from games where player_id = auth.uid();
  if last_at is not null and now() - last_at < interval '10 seconds' then raise exception 'too fast'; end if;
  perform set_profile(p_nick, p_team);
  insert into games (player_id, league, team, season, score, shots, goals, perfect, top_bar, best_streak, duration_s)
  values (auth.uid(), p_league, p_team, week_id(now()), p_score, p_shots, p_goals, coalesce(p_perfect, 0), coalesce(p_top, 0), coalesce(p_best_streak, 0), p_duration)
  returning id into gid;
  return gid;
end $$;
revoke all on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) from public, anon;
grant execute on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) to authenticated;

-- Le viste ripartono con il campionato
drop view if exists public.season_winners, public.week_history, public.team_mvp, public.team_week, public.team_record, public.team_fans, public.player_team_stats;

create view public.team_week as
  select league, season, team, sum(score)::bigint as pts, count(distinct player_id)::int as fans
  from public.games group by league, season, team;

create view public.team_record as
  select distinct on (g.league, g.season, g.team) g.league, g.season, g.team, g.score as pts, p.nick
  from public.games g join public.players p on p.id = g.player_id
  order by g.league, g.season, g.team, g.score desc, g.created_at;

create view public.team_fans as
  select g.league, g.season, g.team, g.player_id, p.nick, sum(g.score)::bigint as pts, count(*)::int as games
  from public.games g join public.players p on p.id = g.player_id
  group by g.league, g.season, g.team, g.player_id, p.nick;

-- MVP: il tifoso che ha portato più punti alla sua squadra nella settimana
create view public.team_mvp as
  select distinct on (league, season, team) league, season, team, nick, pts
  from public.team_fans order by league, season, team, pts desc;

create view public.player_team_stats as
  select player_id, league, team, count(*)::int as games, sum(score)::bigint as points, max(score) as best, sum(shots)::int as shots,
         sum(goals)::int as goals, sum(perfect)::int as perfect, sum(top_bar)::int as top, max(best_streak) as best_streak
  from public.games group by player_id, league, team;

-- Storico completo: ogni squadra di ogni settimana, con posizione, MVP e record
create view public.week_history as
  select w.league, w.season, w.team, w.pts, w.fans,
         rank() over (partition by w.league, w.season order by w.pts desc)::int as pos,
         m.nick as mvp_nick, m.pts as mvp_pts, r.pts as rec_pts, r.nick as rec_nick
  from public.team_week w
  left join public.team_mvp m on m.league = w.league and m.season = w.season and m.team = w.team
  left join public.team_record r on r.league = w.league and r.season = w.season and r.team = w.team;

-- Albo d'oro: la squadra vincitrice di ogni settimana con il suo MVP
create view public.season_winners as
  select league, season, team, pts, fans, mvp_nick, mvp_pts from public.week_history where pos = 1;

grant select on public.team_week, public.team_record, public.team_fans, public.team_mvp, public.player_team_stats,
                public.week_history, public.season_winners to anon, authenticated;
