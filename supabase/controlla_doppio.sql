-- Per la Maglia · Perché un tifoso compare due volte (solo lettura: non modifica niente)
-- Cambia il nome tra apici se serve, poi premi Run.
-- Se "profilo" è diverso tra le righe → sono due profili (due browser, o una reinstallazione): si uniscono con 009_unisci_profili.sql.
-- L'app del Play Store si apre dentro Chrome (o Samsung Internet): per il server ha la stessa firma di quel browser.
-- Se "profilo" è uguale e cambia solo "nome_usato" → stesso profilo con il nome scritto in due modi.
select left(g.player_id::text, 8) as profilo,
       g.nick as nome_usato,
       g.team as squadra,
       g.league as lega,
       count(*) as partite,
       sum(g.score) as punti,
       to_char(min(g.created_at) at time zone 'Europe/Rome', 'DD/MM HH24:MI') as prima_partita,
       to_char(max(g.created_at) at time zone 'Europe/Rome', 'DD/MM HH24:MI') as ultima_partita,
       to_char(u.created_at at time zone 'Europe/Rome', 'DD/MM HH24:MI') as profilo_creato,
       case
         when s.user_agent ~* 'SamsungBrowser' then 'Samsung Internet'
         when s.user_agent ~* 'Chrome' then 'Chrome o app'
         when s.user_agent ~* 'iPhone|iPad' then 'iPhone/iPad'
         else coalesce(left(s.user_agent, 40), '?')
       end as da_dove
  from games g
  join auth.users u on u.id = g.player_id
  left join lateral (select user_agent from auth.sessions x where x.user_id = g.player_id order by x.created_at desc limit 1) s on true
 where g.nick ilike 'denny%' or g.player_id in (select id from players where nick ilike 'denny%')
 group by g.player_id, g.nick, g.team, g.league, u.created_at, s.user_agent
 order by profilo, ultima_partita;
