-- Per la Maglia · aggiornamento 8: orari del campionato, tifosi online, "Chiama la curva" (inviti e distintivi)
-- Incolla tutto in Supabase > SQL Editor > New query e premi Run. Richiede 004-007. Non cancella nessuna partita.

-- 1) ORARI: il campionato è aperto da lunedì alle 08:00 a venerdì alle 20:00 (ora di Roma)
create or replace function public.is_open(ts timestamptz) returns boolean
language sql immutable as $$
  with r as (select (ts at time zone 'Europe/Rome') as t)
  select case extract(isodow from t)::int
           when 1 then t::time >= time '08:00'
           when 2 then true when 3 then true when 4 then true
           when 5 then t::time < time '20:00'
           else false end
  from r
$$;
grant execute on function public.is_open(timestamptz) to anon, authenticated;

-- invio partita: vale solo se è iniziata con il campionato aperto (chi sta giocando alle 20:00 ha 30 minuti per finire)
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
  if not is_open(now() - make_interval(secs => p_duration::double precision))
     or not (is_open(now()) or is_open(now() - interval '30 minutes')) then raise exception 'closed'; end if;
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

-- 2) TIFOSI ONLINE: ogni telefono con il gioco aperto dà un segno di vita al minuto
create table if not exists public.presence (
  player_id uuid primary key references auth.users (id) on delete cascade,
  league text, team text,
  seen_at timestamptz not null default now()
);
create index if not exists presence_seen on public.presence (seen_at);
alter table public.presence enable row level security;
revoke all on public.presence from anon, authenticated;

create or replace function public.ping(p_league text, p_team text) returns json
language plpgsql security definer set search_path = public as $$
declare res json;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into presence (player_id, league, team, seen_at)
  values (auth.uid(), left(p_league, 20), case when valid_team(p_team) then p_team end, now())
  on conflict (player_id) do update set league = excluded.league, team = excluded.team, seen_at = now();
  delete from presence where seen_at < now() - interval '1 day';
  select json_build_object(
    'online', count(*),
    'team', count(*) filter (where team = p_team)
  ) into res from presence where seen_at > now() - interval '2 minutes';
  return res;
end $$;
revoke all on function public.ping(text, text) from public, anon;
grant execute on function public.ping(text, text) to authenticated;

-- 3) CHIAMA LA CURVA: ogni giocatore ha un codice invito; chi arriva dal tuo link e gioca una partita conta come "tifoso portato"
alter table public.players add column if not exists ref_code text unique;
create table if not exists public.referrals (
  invitee uuid primary key references auth.users (id) on delete cascade,
  inviter uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists referrals_inviter on public.referrals (inviter);
alter table public.referrals enable row level security;
revoke all on public.referrals from anon, authenticated;

-- il mio codice invito (lo crea la prima volta)
create or replace function public.my_ref_code() returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into players (id, nick, updated_at) values (auth.uid(), 'Tifoso', now()) on conflict (id) do nothing;
  select ref_code into c from players where id = auth.uid();
  while c is null loop
    c := substr(translate(md5(random()::text || clock_timestamp()::text), '01', ''), 1, 6);
    if length(c) < 6 or exists (select 1 from players where ref_code = c) then c := null; continue; end if;
    update players set ref_code = c where id = auth.uid();
  end loop;
  return c;
end $$;
revoke all on function public.my_ref_code() from public, anon;
grant execute on function public.my_ref_code() to authenticated;

-- chi è arrivato da un invito lo registra dopo la sua prima partita (una volta sola, solo per account nuovi)
create or replace function public.claim_referral(p_code text) returns boolean
language plpgsql security definer set search_path = public, auth as $$
declare inv uuid; born timestamptz;
begin
  if auth.uid() is null then return false; end if;
  select id into inv from players where ref_code = lower(trim(p_code));
  if inv is null or inv = auth.uid() then return false; end if;
  if exists (select 1 from referrals where invitee = auth.uid()) then return false; end if;
  if not exists (select 1 from games where player_id = auth.uid()) then return false; end if;
  select created_at into born from auth.users where id = auth.uid();
  if born is not null and born < now() - interval '14 days' then return false; end if;
  insert into referrals (invitee, inviter) values (auth.uid(), inv) on conflict do nothing;
  return true;
end $$;
revoke all on function public.claim_referral(text) from public, anon;
grant execute on function public.claim_referral(text) to authenticated;

-- quanti tifosi ho portato
create or replace function public.my_referrals() returns int
language sql security definer set search_path = public as $$
  select count(*)::int from referrals where inviter = auth.uid()
$$;
revoke all on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;

-- 4) La classifica dei tifosi mostra anche quanti tifosi ha portato ognuno (per il distintivo)
drop view if exists public.season_winners, public.week_history, public.team_mvp, public.team_record, public.team_fans;

create view public.team_record as
  select distinct on (g.league, g.season, g.team) g.league, g.season, g.team, g.score as pts, coalesce(g.nick, p.nick) as nick
  from public.games g join public.players p on p.id = g.player_id
  order by g.league, g.season, g.team, g.score desc, g.created_at;

create view public.team_fans as
  select g.league, g.season, g.team, g.player_id, coalesce(g.nick, p.nick) as nick, sum(g.score)::bigint as pts, count(*)::int as games,
         coalesce(max(r.n), 0)::int as refs
  from public.games g join public.players p on p.id = g.player_id
  left join (select inviter, count(*) as n from public.referrals group by inviter) r on r.inviter = g.player_id
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
