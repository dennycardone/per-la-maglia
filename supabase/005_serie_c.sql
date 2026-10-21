-- Per la Maglia · aggiornamento 5: arriva la Serie C (le 20 piazze più grandi)
-- Incolla tutto in Supabase > SQL Editor > New query e premi Run. Richiede di aver già eseguito 004. Non cancella nessuna partita.

create or replace function public.league_teams(l text) returns text[]
language sql immutable as $$
  select case l
    when 'serie-a' then array['Atalanta','Bologna','Cagliari','Como','Fiorentina','Frosinone','Genoa','Inter','Juventus','Lazio',
                              'Lecce','Milan','Monza','Napoli','Parma','Roma','Sassuolo','Torino','Udinese','Venezia']
    when 'serie-b' then array['Arezzo','Ascoli','Avellino','Benevento','Carrarese','Catanzaro','Cesena','Cremonese','Empoli','Hellas Verona',
                              'Juve Stabia','Mantova','Modena','Padova','Palermo','Pisa','Sampdoria','Südtirol','Vicenza','Virtus Entella']
    when 'serie-c' then array['Bari','Casertana','Catania','Cosenza','Crotone','Foggia','Lecco','Livorno','Monopoli','Novara',
                              'Perugia','Pescara','Potenza','Pro Vercelli','Ravenna','Salernitana','Sambenedettese','Spezia','Treviso','Union Brescia']
    else array[]::text[] end
$$;

create or replace function public.valid_team(t text) returns boolean
language sql immutable as $$
  select t = any (public.league_teams('serie-a') || public.league_teams('serie-b') || public.league_teams('serie-c'))
$$;

create or replace function public.submit_game_v2(p_league text, p_team text, p_score int, p_shots int, p_goals int, p_perfect int, p_top int,
                                                 p_best_streak int, p_duration numeric, p_nick text) returns bigint
language plpgsql security definer set search_path = public as $$
declare gid bigint; last_at timestamptz;
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
  perform set_profile(p_nick, p_team);
  insert into games (player_id, league, team, season, score, shots, goals, perfect, top_bar, best_streak, duration_s)
  values (auth.uid(), p_league, p_team, week_id(now()), p_score, p_shots, p_goals, coalesce(p_perfect, 0), coalesce(p_top, 0), coalesce(p_best_streak, 0), p_duration)
  returning id into gid;
  return gid;
end $$;
revoke all on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) from public, anon;
grant execute on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) to authenticated;
