-- Per la Maglia · Controllo delle novità (solo lettura: non modifica niente)
-- Promozioni e retrocessioni (012), registro errori (011), Salva con Google (010). Incolla tutto, premi Run.
with q as (select
  to_regclass('public.league_members') is not null as p012,
  to_regclass('public.client_errors') is not null as p011,
  to_regclass('public.merge_tickets') is not null as p010)
select ord, sezione, voce, valore from (
  select 1 ord, '1 Promozioni' sezione, 'File 012 eseguito' voce, case when p012 then 'sì' else 'NO: esegui 012_promozioni_retrocessioni.sql' end valore from q
  union all select 2, '1 Promozioni', 'Settimane già preparate', case when p012 then (xpath('//c/text()', query_to_xml($$select string_agg(distinct season, ', ' order by season) as c from public.league_members$$, false, true, '')))[1]::text end from q
  union all select 3, '1 Promozioni', 'Squadre per serie questa settimana', case when p012 then (xpath('//c/text()', query_to_xml($$select string_agg(league || ' ' || n, ' · ' order by league) as c from (select league, count(*) n from public.league_members where season = public.week_id(now()) group by league) x$$, false, true, '')))[1]::text end from q
  union all select 4, '1 Promozioni', 'Prima settimana con verdetti', case when p012 then (xpath('//c/text()', query_to_xml($$select public.lt_start() as c$$, false, true, '')))[1]::text end from q
  union all select 5, '1 Promozioni', 'Se finisse adesso (anteprima)', case when p012 then coalesce((xpath('//c/text()', query_to_xml($$select case when public.week_id(now()) < public.lt_start() then 'i verdetti partono dalla settimana ' || public.lt_start() else string_agg(team || ' ' || replace(from_league, 'serie-', '') || '→' || replace(to_league, 'serie-', ''), ', ' order by from_league, to_league) end as c from public.lt_moves(public.week_id(now()))$$, false, true, '')))[1]::text, 'nessuno si muove (nessuna squadra della serie sotto ha punti)') end from q
  union all select 10, '2 Errori', 'File 011 eseguito', case when p011 then 'sì' else 'NO: esegui 011_registro_errori.sql' end from q
  union all select 11, '2 Errori', 'Errori negli ultimi 7 giorni', case when p011 then (xpath('//c/text()', query_to_xml($$select count(*) || ' errori · ' || count(distinct player_id) || ' giocatori' as c from public.client_errors where at > now() - interval '7 days'$$, false, true, '')))[1]::text end from q
  union all select 12, '2 Errori', 'Il più frequente', case when p011 then coalesce((xpath('//c/text()', query_to_xml($$select msg || ' (' || count(*) || ' volte)' as c from public.client_errors where at > now() - interval '7 days' group by msg order by count(*) desc limit 1$$, false, true, '')))[1]::text, 'nessuno') end from q
  union all select 20, '3 Google', 'File 010 eseguito', case when p010 then 'sì' else 'NO: esegui 010_salva_con_google.sql' end from q
  union all select 21, '3 Google', 'Profili salvati con Google', (select count(*)::text from auth.users where coalesce(is_anonymous, false) = false)
  union all select 22, '3 Google', 'di cui salvati negli ultimi 7 giorni', (select count(*)::text from auth.identities where provider = 'google' and created_at > now() - interval '7 days')
  union all select 30, '4 Oggi', 'Partite oggi', (select count(*)::text from public.games where (created_at at time zone 'Europe/Rome')::date = (now() at time zone 'Europe/Rome')::date)
  union all select 31, '4 Oggi', 'Giocatori questa settimana', (select count(distinct player_id)::text from public.games where season = public.week_id(now()))
) t order by ord;
