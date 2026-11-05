-- Per la Maglia · 011 · Registro degli errori
-- Quando il gioco si rompe sul telefono di qualcuno, il messaggio di errore arriva qui (al massimo 20 al giorno per giocatore).
-- Si tengono 60 giorni. Nessun dato personale: messaggio, riga del codice, tipo di browser, momento del gioco.
-- Esegui tutto una volta nell'editor SQL di Supabase.

create table if not exists public.client_errors (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  player_id uuid,
  msg text not null,
  src text, line int, col int, stack text,
  ver text, ua text, place text
);
create index if not exists client_errors_at on public.client_errors (at);
create index if not exists client_errors_player on public.client_errors (player_id, at);
alter table public.client_errors enable row level security;   -- nessuna regola: il gioco scrive solo con la funzione qui sotto
revoke all on public.client_errors from anon, authenticated;

create or replace function public.log_error(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p is null then return; end if;
  if (select count(*) from client_errors where player_id = auth.uid() and at > now() - interval '1 day') >= 20 then return; end if;
  insert into client_errors (player_id, msg, src, line, col, stack, ver, ua, place)
  values (auth.uid(), left(coalesce(p ->> 'msg', '?'), 300), left(p ->> 'src', 200),
          case when (p ->> 'line') ~ '^\d{1,7}$' then (p ->> 'line')::int end,
          case when (p ->> 'col') ~ '^\d{1,7}$' then (p ->> 'col')::int end,
          left(p ->> 'stack', 1500), left(p ->> 'ver', 20), left(p ->> 'ua', 160), left(p ->> 'where', 60));
  -- pulizia: via quelli più vecchi di 60 giorni
  delete from client_errors where at < now() - interval '60 days';
end $$;
revoke all on function public.log_error(jsonb) from public, anon;
grant execute on function public.log_error(jsonb) to authenticated;
