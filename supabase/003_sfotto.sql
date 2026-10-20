-- Per la Maglia · aggiornamento 3: sfottò (una frase per partita) e filtro delle parolacce
-- Incolla tutto in Supabase > SQL Editor > New query e premi Run.

-- Riconosce parolacce e insulti, anche scritti con numeri o simboli (c4zz0) o spezzati da spazi (c a z z o)
create or replace function public.bad_text(t text) returns boolean
language sql immutable as $$
  with n as (select translate(lower(coalesce(t, '')), '0134578@$€!|', 'oieastbaseii') as s)
  select s ~ '(cazz|minchi|vaffanc|stronz|puttan|troi[ae]|merd|coglion|bastard|froci|ricchion|negr[oi]|zoccol|porcodi|porcamadon|diocan|dioporc|culatton|bocchin|pompin|fott|incul|mignott|baldracc|fuck|shit|bitch|cunt|dick|pussy|asshole|nigg|faggot|whore|slut|motherf|wank|twat|retard)'
      or regexp_replace(s, '[^a-z]', '', 'g') ~ '(cazz|minchi|vaffanc|puttan|stronz|fuck|cunt|nigg|froci|diocan|porcodi|dioporc|merda|coglion)'
  from n
$$;

-- Il soprannome passa dallo stesso filtro: se non va bene diventa "Tifoso"
create or replace function public.set_profile(p_nick text, p_team text) returns void
language plpgsql security definer set search_path = public as $$
declare n text := left(trim(regexp_replace(coalesce(p_nick, ''), '[<>"''`\\]', '', 'g')), 16);
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if n = '' or bad_text(n) then n := 'Tifoso'; end if;
  insert into players (id, nick, team, updated_at) values (auth.uid(), n, case when valid_team(p_team) then p_team end, now())
  on conflict (id) do update set nick = excluded.nick, team = coalesce(excluded.team, players.team), updated_at = now();
end $$;

-- Gli sfottò: uno per partita, scritto subito dopo averla giocata
create table if not exists public.taunts (
  id bigint generated always as identity primary key,
  game_id bigint not null unique references public.games (id) on delete cascade,
  player_id uuid not null references public.players (id) on delete cascade,
  league text not null, season text not null, team text not null, nick text not null,
  body text not null check (char_length(body) between 2 and 80),
  created_at timestamptz not null default now()
);
create index if not exists taunts_league_season on public.taunts (league, season, created_at desc);
alter table public.taunts enable row level security;
drop policy if exists "sfotto leggibili" on public.taunts;
create policy "sfotto leggibili" on public.taunts for select using (true);
revoke all on public.taunts from anon, authenticated;
grant select on public.taunts to anon, authenticated;

create or replace function public.post_taunt(p_game_id bigint, p_text text) returns bigint
language plpgsql security definer set search_path = public as $$
declare g games%rowtype; body text; nk text; tid bigint;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into g from games where id = p_game_id and player_id = auth.uid();
  if not found then raise exception 'no game'; end if;
  if now() - g.created_at > interval '30 minutes' then raise exception 'too late'; end if;
  if exists (select 1 from taunts where game_id = p_game_id) then raise exception 'already'; end if;
  body := left(trim(regexp_replace(regexp_replace(coalesce(p_text, ''), '[<>"`\\]', '', 'g'), '\s+', ' ', 'g')), 80);
  if char_length(body) < 2 then raise exception 'too short'; end if;
  if bad_text(body) then raise exception 'bad words'; end if;
  select nick into nk from players where id = auth.uid();
  insert into taunts (game_id, player_id, league, season, team, nick, body)
  values (p_game_id, auth.uid(), g.league, g.season, g.team, coalesce(nk, 'Tifoso'), body)
  returning id into tid;
  return tid;
end $$;
revoke all on function public.post_taunt(bigint, text) from public, anon;
grant execute on function public.post_taunt(bigint, text) to authenticated;
