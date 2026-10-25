-- Per la Maglia · Da quale telefono e browser arrivano i nuovi profili (solo lettura)
-- Serve a distinguere i giocatori veri dai robot di Google e a vedere chi usa Samsung Internet.
select to_char(u.created_at at time zone 'Europe/Rome', 'DD/MM HH24:MI') as creato,
       coalesce(p.nick, '(senza nome)') as nome,
       case
         when s.user_agent ~* 'bot|crawler|spider|headless|lighthouse|google-inspectiontool' then 'ROBOT'
         when s.user_agent ~* 'SamsungBrowser' then 'Samsung Internet'
         when s.user_agent ~* 'wv\)' then 'App (WebView)'
         when s.user_agent ~* 'Chrome' then 'Chrome'
         when s.user_agent ~* 'iPhone|iPad' then 'iPhone/iPad'
         else coalesce(s.user_agent, '?')
       end as browser,
       coalesce(substring(s.user_agent from 'Android [0-9.]+; ([^;)]+)'), '') as telefono,
       regexp_replace(host(s.ip), '\.\d+\.\d+$', '.x.x') as rete,
       left(s.user_agent, 140) as dettaglio
  from auth.users u
  left join players p on p.id = u.id
  left join lateral (select user_agent, ip from auth.sessions x where x.user_id = u.id order by x.created_at limit 1) s on true
 where u.created_at >= timestamptz '2026-10-23 00:00 Europe/Rome'
 order by u.created_at;
