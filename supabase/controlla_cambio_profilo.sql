-- Per la Maglia · Perché a un giocatore è cambiato il profilo (solo lettura: non modifica niente)
-- Cambia il nome tra apici (due volte) se serve, poi premi Run. Una riga per ogni profilo che ha usato quel nome.
-- Come si legge:
--   "sessione" = VIVA    → per il server quel profilo è ancora valido: è il telefono che ha perso i dati salvati
--                          (dati del browser cancellati, altro browser, app al posto del sito o viceversa)
--   "sessione" = CHIUSA  → è il server che ha rifiutato quel telefono: va corretto nel gioco
--   "browser" diverso tra le righe → i profili sono nati in due browser diversi dello stesso telefono
select left(u.id::text, 8) as profilo,
       to_char(u.created_at at time zone 'Europe/Rome', 'DD/MM HH24:MI') as creato,
       case when coalesce(u.is_anonymous, false) then 'senza Google' else 'salvato con Google' end as tipo,
       coalesce(p.nick, '(senza nome)') as nome,
       coalesce(g.partite, 0) as partite,
       coalesce(g.prima, '') as prima_partita,
       coalesce(g.ultima, '') as ultima_partita,
       coalesce(s.quante, 0) as accessi,
       coalesce(s.ultimo, '') as ultimo_rinnovo,
       case when exists (select 1 from auth.refresh_tokens r where r.user_id = u.id::text and not coalesce(r.revoked, false)) then 'VIVA' else 'CHIUSA' end as sessione,
       coalesce(s.browser, '?') as browser,
       coalesce(s.telefono, '') as telefono,
       coalesce(s.rete, '') as rete
  from auth.users u
  left join players p on p.id = u.id
  left join lateral (
    select count(*) as partite,
           to_char(min(x.created_at) at time zone 'Europe/Rome', 'DD/MM HH24:MI') as prima,
           to_char(max(x.created_at) at time zone 'Europe/Rome', 'DD/MM HH24:MI') as ultima
      from games x where x.player_id = u.id) g on true
  left join lateral (
    select count(*) as quante,
           to_char(max(coalesce(x.refreshed_at at time zone 'UTC', x.updated_at, x.created_at)) at time zone 'Europe/Rome', 'DD/MM HH24:MI') as ultimo,
           string_agg(distinct case
             when x.user_agent ~* 'SamsungBrowser' then 'Samsung Internet'
             when x.user_agent ~* 'wv\)' then 'dentro un''altra app (WhatsApp, Instagram…)'
             when x.user_agent ~* 'iPhone|iPad' then 'iPhone/iPad'
             when x.user_agent ~* 'Chrome' then 'Chrome o app'
             else coalesce(left(x.user_agent, 40), '?') end, ' + ') as browser,
           string_agg(distinct substring(x.user_agent from 'Android [0-9.]+; ([^;)]+)'), ' + ') as telefono,
           string_agg(distinct regexp_replace(host(x.ip), '\.\d+\.\d+$', '.x.x'), ' + ') as rete
      from auth.sessions x where x.user_id = u.id) s on true
 where u.id in (select id from players where nick ilike 'sasa%'
                union select player_id from games where nick ilike 'sasa%')
 order by u.created_at;
