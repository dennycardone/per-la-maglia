-- Per la Maglia · aggiornamento 7 (URGENTE): ogni partita tiene il soprannome con cui è stata giocata
-- Prima il nome veniva letto dal profilo del telefono: cambiando soprannome cambiavano anche le partite passate.
-- Incolla tutto in Supabase > SQL Editor > New query e premi Run. Richiede 004, 005 e 006. Non cancella nessuna partita.

-- 1) Il nome viene salvato dentro ogni partita
alter table public.games add column if not exists nick text;
-- partite già giocate: se c'è uno sfottò si usa il nome scritto lì (era quello del momento), altrimenti il soprannome attuale
update public.games g set nick = t.nick from public.taunts t where t.game_id = g.id and g.nick is null;
update public.games g set nick = p.nick from public.players p where p.id = g.player_id and g.nick is null;

-- 2) Invio partita: salva il soprannome di QUESTA partita (già ripulito dal filtro)
create or replace function public.submit_game_v2(p_league text, p_team text, p_score int, p_shots int, p_goals int, p_perfect int, p_top int,
                                                 p_best_streak int, p_duration numeric, p_nick text) returns bigint
language plpgsql security definer set search_path = public as $$
declare gid bigint; last_at timestamptz; nk text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_league is null or not (p_league = any (array['serie-a','serie-b','serie-c'])) then raise exception 'bad league'; end if;
  if not (p_team = any (league_teams(p_league))) then raise exception 'bad team'; end if;
  if p_goals < 0 or p_goals > p_shots or p_shots - p_goals > 3 then raise exception 'bad shots'; end if;
  if p_perfect > p_goals or p_top > p_goals or p_best_streak > p_goals then raise exception 'bad details'; end if;
  if p_score > p_goals * 2025 then raise exception 'bad score'; end if;
  if p_duration < p_shots * 1.5 or p_duration > 10800 then raise exception 'bad duration'; end if;
  select max(created_at) into last_at from games where player_id = auth.uid();
  if last_at is not null and now() - last_at < interval '10 seconds' then raise exception 'too fast'; end if;
  nk := left(trim(regexp_replace(coalesce(p_nick, ''), '[<>"''`\\]', '', 'g')), 16);
  if nk = '' or bad_text(nk) then nk := 'Tifoso'; end if;
  perform set_profile(nk, p_team);
  insert into games (player_id, league, team, season, score, shots, goals, perfect, top_bar, best_streak, duration_s, nick)
  values (auth.uid(), p_league, p_team, week_id(now()), p_score, p_shots, p_goals, coalesce(p_perfect, 0), coalesce(p_top, 0), coalesce(p_best_streak, 0), p_duration, nk)
  returning id into gid;
  return gid;
end $$;
revoke all on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) from public, anon;
grant execute on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) to authenticated;

-- 3) Lo sfottò porta il nome della partita a cui appartiene
create or replace function public.post_taunt(p_game_id bigint, p_text text) returns bigint
language plpgsql security definer set search_path = public as $$
declare g games%rowtype; body text; tid bigint;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into g from games where id = p_game_id and player_id = auth.uid();
  if not found then raise exception 'no game'; end if;
  if now() - g.created_at > interval '30 minutes' then raise exception 'too late'; end if;
  if exists (select 1 from taunts where game_id = p_game_id) then raise exception 'already'; end if;
  body := left(trim(regexp_replace(regexp_replace(coalesce(p_text, ''), '[<>"`\\]', '', 'g'), '\s+', ' ', 'g')), 80);
  if char_length(body) < 2 then raise exception 'too short'; end if;
  if bad_text(body) then raise exception 'bad words'; end if;
  insert into taunts (game_id, player_id, league, season, team, nick, body)
  values (p_game_id, auth.uid(), g.league, g.season, g.team, coalesce(g.nick, 'Tifoso'), body)
  returning id into tid;
  return tid;
end $$;
revoke all on function public.post_taunt(bigint, text) from public, anon;
grant execute on function public.post_taunt(bigint, text) to authenticated;

-- 4) Classifiche, record, MVP e albo d'oro usano il nome della partita, non quello attuale del telefono
drop view if exists public.season_winners, public.week_history, public.team_mvp, public.team_record, public.team_fans;

create view public.team_record as
  select distinct on (g.league, g.season, g.team) g.league, g.season, g.team, g.score as pts, coalesce(g.nick, p.nick) as nick
  from public.games g join public.players p on p.id = g.player_id
  order by g.league, g.season, g.team, g.score desc, g.created_at;

-- ogni soprannome è un tifoso a sé, anche se due persone giocano sullo stesso telefono
create view public.team_fans as
  select g.league, g.season, g.team, g.player_id, coalesce(g.nick, p.nick) as nick, sum(g.score)::bigint as pts, count(*)::int as games
  from public.games g join public.players p on p.id = g.player_id
  group by g.league, g.season, g.team, g.player_id, coalesce(g.nick, p.nick);

create view public.team_mvp as
  select distinct on (league, season, team) league, season, team, nick, pts
  from public.team_fans order by league, season, team, pts desc;

create view public.week_history as
  select w.league, w.season, w.team, w.pts, w.fans,
         rank() over (partition by w.league, w.season order by w.pts desc)::int as pos,
         m.nick as mvp_nick, m.pts as mvp_pts, r.pts as rec_pts, r.nick as rec_nick
  from public.team_week w
  left join public.team_mvp m on m.league = w.league and m.season = w.season and m.team = w.team
  left join public.team_record r on r.league = w.league and r.season = w.season and r.team = w.team;

create view public.season_winners as
  select league, season, team, pts, fans, mvp_nick, mvp_pts from public.week_history where pos = 1;

grant select on public.team_record, public.team_fans, public.team_mvp, public.week_history, public.season_winners to anon, authenticated;
