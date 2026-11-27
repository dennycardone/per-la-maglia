-- Per la Maglia · Quanti hanno giocato, contando una volta sola i nomi ripetuti (solo lettura: non modifica niente)
-- Incolla tutto nell'editor SQL di Supabase e premi Run.
-- "Nome" = il soprannome attuale del profilo (se manca, quello dell'ultima partita), senza maiuscole e spazi ai lati:
-- "Sasa", "sasa " e "SASA" valgono come una persona sola.
with par as (
  select case when (extract(isodow from now() at time zone 'Europe/Rome') = 6 and extract(hour from now() at time zone 'Europe/Rome') >= 8)
                or extract(isodow from now() at time zone 'Europe/Rome') = 7
              then week_id(now()) else week_id(now() - interval '7 days') end as chiusa,
         week_id(now()) as ora
),
ultimo as (select distinct on (player_id) player_id, nick from games where nick is not null order by player_id, created_at desc),
gioc as (   -- un profilo che ha giocato almeno una partita in classifica, col suo nome
  select g.player_id,
         lower(trim(coalesce(nullif(p.nick, 'Tifoso'), u.nick, p.nick))) as nome,
         min(g.created_at) as prima, max(g.created_at) as ultima, count(*) as partite,
         count(distinct (g.created_at at time zone 'Europe/Rome')::date) as giorni,
         bool_or(g.season = (select ora from par)) as questa_sett,
         bool_or(g.season = (select chiusa from par)) as sett_chiusa
    from games g left join players p on p.id = g.player_id left join ultimo u on u.player_id = g.player_id
   group by g.player_id, p.nick, u.nick
),
gnome as (   -- giorni diversi in cui ha giocato ogni nome, sommando tutti i suoi profili
  select x.nome, count(distinct (g.created_at at time zone 'Europe/Rome')::date) as giorni
    from games g join gioc x on x.player_id = g.player_id group by x.nome
),
nomi as (   -- una riga per nome: i profili con lo stesso nome diventano una persona
  select x.nome, count(*) as profili, sum(partite) as partite, max(gn.giorni) as giorni, min(prima) as prima, max(ultima) as ultima,
         bool_or(questa_sett) as questa_sett, bool_or(sett_chiusa) as sett_chiusa
    from gioc x join gnome gn on gn.nome = x.nome group by x.nome
),
squadra as (   -- squadra preferita di ogni nome: quella con più partite
  select distinct on (lower(trim(coalesce(nullif(p.nick, 'Tifoso'), u.nick, p.nick))))
         lower(trim(coalesce(nullif(p.nick, 'Tifoso'), u.nick, p.nick))) as nome, g.team, count(*) as n
    from games g left join players p on p.id = g.player_id left join ultimo u on u.player_id = g.player_id
   group by 1, g.team order by 1, count(*) desc
)
select ord, sezione, voce, valore from (
  select 1 ord, '1 Totale' sezione, 'Persone che hanno giocato (nomi diversi)' voce, (select count(*) from nomi)::text valore
  union all select 2, '1 Totale', 'Profili che hanno giocato (con i doppi)', (select count(*) from gioc)::text
  union all select 3, '1 Totale', 'Profili doppi tolti', ((select count(*) from gioc) - (select count(*) from nomi))::text
  union all select 4, '1 Totale', 'Nomi usati da più di un profilo', (select count(*) from nomi where profili > 1)::text
  union all select 5, '1 Totale', 'Partite in classifica in totale', (select sum(partite) from nomi)::text
  union all select 10, '2 Quando', 'Hanno giocato questa settimana', (select count(*) from nomi where questa_sett)::text
  union all select 11, '2 Quando', 'Hanno giocato nella settimana chiusa (' || (select chiusa from par) || ')', (select count(*) from nomi where sett_chiusa)::text
  union all select 12, '2 Quando', 'Hanno giocato nelle ultime 24 ore', (select count(*) from nomi where ultima > now() - interval '1 day')::text
  union all select 13, '2 Quando', 'Hanno giocato negli ultimi 7 giorni', (select count(*) from nomi where ultima > now() - interval '7 days')::text
  union all select 14, '2 Quando', 'Nuovi negli ultimi 7 giorni (prima partita)', (select count(*) from nomi where prima > now() - interval '7 days')::text
  union all select 20, '3 Fedeltà', 'Una partita sola', (select count(*) from nomi where partite = 1)::text
  union all select 21, '3 Fedeltà', 'Da 2 a 9 partite', (select count(*) from nomi where partite between 2 and 9)::text
  union all select 22, '3 Fedeltà', '10 partite o più', (select count(*) from nomi where partite >= 10)::text
  union all select 23, '3 Fedeltà', 'Tornati in almeno 2 giorni diversi', (select count(*) from nomi where giorni >= 2)::text
  union all select 24, '3 Fedeltà', 'Tornati in almeno 5 giorni diversi', (select count(*) from nomi where giorni >= 5)::text
  union all select 100 + row_number() over (order by count(*) desc, team), '4 Per squadra (preferita)', team, count(*)::text
    from squadra group by team
  union all select 300 + row_number() over (order by profili desc, nome), '5 Nomi doppi', nome, profili || ' profili · ' || partite || ' partite'
    from nomi where profili > 1
) x order by ord;
