-- Per la Maglia · Errori degli ultimi 7 giorni (solo lettura)
-- Un errore per riga: quante volte è capitato, a quanti giocatori, su che telefoni e in che momento del gioco.
select msg as errore,
       count(*) as volte,
       count(distinct player_id) as giocatori,
       max(line) as riga,
       to_char(max(at) at time zone 'Europe/Rome', 'DD/MM HH24:MI') as ultima_volta,
       string_agg(distinct place, ' | ') as dove,
       string_agg(distinct case
         when ua ~* 'SamsungBrowser' then 'Samsung Internet'
         when ua ~* 'iPhone|iPad' then 'iPhone/iPad'
         when ua ~* 'Android' then 'Android Chrome'
         else 'computer' end, ', ') as telefoni,
       max(ver) as versione
  from client_errors
 where at > now() - interval '7 days'
 group by msg
 order by volte desc
 limit 50;
