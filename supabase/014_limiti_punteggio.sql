-- Per la Maglia · 014 · controlli più stretti sulle partite inviate (contro i punteggi finti)
-- Cambia solo i controlli: le partite già salvate restano come sono.
-- 1) almeno 2,5 secondi per tiro (prima 1,5): il giocatore più veloce di sempre fa circa 3,2 secondi a tiro
-- 2) tetto ai punti calcolato come nel gioco: un gol vale al massimo 675 punti (3 × 100 + 150 di bonus, × 1,5 per la parabola tesa)
--    moltiplicati per la serie (×1,0 al primo gol di fila, +0,1 a gol, fino a ×3 dal 21° gol di fila)
create or replace function public.max_game_score(g int) returns bigint language sql immutable as $$
  select case when g <= 0 then 0
              when g <= 21 then ceil(675 * (g + 0.1 * g * (g - 1) / 2.0))::bigint + g
              else (675 * 42 + 2025 * (g - 21))::bigint + g end
$$;

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
  if p_score < 0 or p_score > max_game_score(p_goals) then raise exception 'bad score'; end if;
  if p_duration < p_shots * 2.5 or p_duration > 10800 then raise exception 'bad duration'; end if;
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
