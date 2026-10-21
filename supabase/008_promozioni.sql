-- Per la Maglia · aggiornamento 8: promozioni e retrocessioni ogni settimana
-- A fine settimana (lunedì 00:00, ora di Roma) le ultime 3 della Serie A scendono in B e le prime 3 della B salgono in A;
-- lo stesso tra B e C. Sale solo chi ha fatto almeno un punto: se ne salgono meno di 3, ne scendono altrettante.
-- Incolla tutto in Supabase > SQL Editor > New query e premi Run. Richiede 004-007. Non cancella nessuna partita.

-- 1) In quale serie gioca ogni squadra, settimana per settimana
create table if not exists public.league_members (
  season text not null,
  league text not null,
  team text not null,
  primary key (season, team)
);
create index if not exists league_members_season_league on public.league_members (season, league);
alter table public.league_members enable row level security;
drop policy if exists "serie leggibili" on public.league_members;
create policy "serie leggibili" on public.league_members for select using (true);
revoke all on public.league_members from anon, authenticated;
grant select on public.league_members to anon, authenticated;

-- la settimana dopo (es. 2026-W52 -> 2027-W01)
create or replace function public.next_week(w text) returns text
language sql immutable as $$
  select public.week_id((to_date(w, 'IYYY-"W"IW') + 7 + time '12:00') at time zone 'Europe/Rome')
$$;

-- passa da una settimana alla successiva applicando promozioni e retrocessioni
create or replace function public.roll_members(cur text) returns void
language plpgsql security definer set search_path = public as $$
declare nxt text := next_week(cur); pair text[]; up text[]; down text[]; n int;
begin
  insert into league_members (season, league, team) select nxt, league, team from league_members where season = cur
  on conflict do nothing;
  foreach pair slice 1 in array array[array['serie-a','serie-b'], array['serie-b','serie-c']] loop
    -- prime 3 della serie inferiore con almeno un punto (stesso ordine della classifica: punti, poi nome)
    select coalesce(array_agg(team), '{}') into up from (
      select m.team from league_members m
      left join (select team, sum(score) pts from games where season = cur and league = pair[2] group by team) g on g.team = m.team
      where m.season = cur and m.league = pair[2] and coalesce(g.pts, 0) > 0
      order by coalesce(g.pts, 0) desc, m.team asc limit 3) s;
    n := coalesce(array_length(up, 1), 0);
    if n = 0 then continue; end if;
    -- ultime n della serie superiore
    select coalesce(array_agg(team), '{}') into down from (
      select m.team from league_members m
      left join (select team, sum(score) pts from games where season = cur and league = pair[1] group by team) g on g.team = m.team
      where m.season = cur and m.league = pair[1]
      order by coalesce(g.pts, 0) asc, m.team desc limit n) s;
    update league_members set league = pair[1] where season = nxt and team = any (up);
    update league_members set league = pair[2] where season = nxt and team = any (down);
  end loop;
end $$;
revoke all on function public.roll_members(text) from public, anon, authenticated;

-- si assicura che la composizione della settimana w esista (la calcola dalle settimane precedenti, una alla volta)
create or replace function public.ensure_members(w text) returns void
language plpgsql security definer set search_path = public as $$
declare cur text;
begin
  if exists (select 1 from league_members where season = w) then return; end if;
  lock table league_members in exclusive mode;
  if exists (select 1 from league_members where season = w) then return; end if;
  select max(season) into cur from league_members where season < w;
  if cur is null then
    insert into league_members (season, league, team)
    select w, l, unnest(league_teams(l)) from unnest(array['serie-a','serie-b','serie-c']) l;
    return;
  end if;
  while cur < w loop perform roll_members(cur); cur := next_week(cur); end loop;
end $$;
revoke all on function public.ensure_members(text) from public, anon, authenticated;

-- per il gioco: la composizione di questa settimana e di quella prima (per sapere chi è salito e chi è sceso)
create or replace function public.league_members_now() returns table (season text, league text, team text)
language plpgsql security definer set search_path = public as $$
declare w text := week_id(now());
begin
  perform ensure_members(w);
  return query select m.season, m.league, m.team from league_members m
    where m.season = w or m.season = (select max(x.season) from league_members x where x.season < w);
end $$;
grant execute on function public.league_members_now() to anon, authenticated;

-- 2) Invio partita: la serie è quella in cui gioca la squadra QUESTA settimana
create or replace function public.submit_game_v2(p_league text, p_team text, p_score int, p_shots int, p_goals int, p_perfect int, p_top int,
                                                 p_best_streak int, p_duration numeric, p_nick text) returns bigint
language plpgsql security definer set search_path = public as $$
declare gid bigint; last_at timestamptz; nk text; w text := week_id(now()); lg text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  perform ensure_members(w);
  select league into lg from league_members where season = w and team = p_team;
  if lg is null then raise exception 'bad team'; end if;
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
  values (auth.uid(), lg, p_team, w, p_score, p_shots, p_goals, coalesce(p_perfect, 0), coalesce(p_top, 0), coalesce(p_best_streak, 0), p_duration, nk)
  returning id into gid;
  return gid;
end $$;
revoke all on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) from public, anon;
grant execute on function public.submit_game_v2(text, text, int, int, int, int, int, int, numeric, text) to authenticated;

-- 3) La settimana in corso parte dalla composizione reale di oggi
select public.ensure_members(public.week_id(now()));
