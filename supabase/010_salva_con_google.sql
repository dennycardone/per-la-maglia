-- Per la Maglia · 010 · Salva con Google
-- Quando un giocatore tocca «Salva con Google» il suo profilo anonimo diventa permanente (stesso profilo, non si sposta niente).
-- Se quell'account Google ha già un profilo salvato su un altro telefono, il giocatore entra in quello
-- e le partite fatte sul telefono nuovo vengono aggiunte lì (usa merge_players del file 009, che deve esserci già).
-- Esegui tutto una volta nell'editor SQL di Supabase.

create table if not exists public.merge_tickets (
  ticket uuid primary key default gen_random_uuid(),
  old_id uuid not null unique,
  created_at timestamptz not null default now()
);
alter table public.merge_tickets enable row level security;   -- nessuna regola: il gioco non la legge mai direttamente
revoke all on public.merge_tickets from anon, authenticated;

-- 1) sul telefono nuovo, prima di andare da Google: «le partite di questo profilo anonimo vanno a chi entra adesso»
create or replace function public.merge_start() returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false then return null; end if;   -- solo un profilo anonimo
  delete from merge_tickets where old_id = auth.uid() or created_at < now() - interval '1 day';
  insert into merge_tickets (old_id) values (auth.uid()) returning ticket into v;
  return v;
end $$;
revoke all on function public.merge_start() from public, anon;
grant execute on function public.merge_start() to authenticated;

-- 2) tornati da Google, già dentro il profilo salvato: le partite del profilo anonimo passano qui
create or replace function public.merge_finish(p_ticket uuid) returns text
language plpgsql security definer set search_path = public, auth as $$
declare v_old uuid; me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, true) then return 'Il profilo non è salvato'; end if;
  delete from public.merge_tickets where ticket = p_ticket and created_at > now() - interval '30 minutes' returning old_id into v_old;
  if v_old is null or v_old = me then return 'Niente da unire'; end if;
  -- un profilo già salvato non viene mai assorbito da un altro
  if exists (select 1 from auth.users where id = v_old and coalesce(is_anonymous, false) = false) then return 'Niente da unire'; end if;
  if not exists (select 1 from public.players where id = v_old) then return 'Niente da unire'; end if;
  if not exists (select 1 from public.players where id = me) then
    insert into public.players (id, nick, team) select me, nick, team from public.players where id = v_old;
  end if;
  return public.merge_players(v_old, me);
end $$;
revoke all on function public.merge_finish(uuid) from public, anon;
grant execute on function public.merge_finish(uuid) to authenticated;
