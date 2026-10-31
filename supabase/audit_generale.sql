-- Per la Maglia · Controllo generale (solo lettura: non modifica niente)
-- Incolla tutto nell'editor SQL di Supabase, premi Run e scarica il risultato in CSV.
-- "Settimana chiusa" = come nel gioco: da sabato alle 8 è la settimana appena giocata, prima è quella precedente.
with par as (
  select week_id(now()) as ora,
         -- come nel gioco: dal sabato alle 8 la settimana in corso è chiusa, prima vale quella precedente
         case when (extract(isodow from now() at time zone 'Europe/Rome') = 6 and extract(hour from now() at time zone 'Europe/Rome') >= 8)
                or extract(isodow from now() at time zone 'Europe/Rome') = 7
              then week_id(now()) else week_id(now() - interval '7 days') end as chiusa,
         timestamptz '2026-10-23 00:00 Europe/Rome' as test_da
),
giorni as (select player_id, count(distinct (created_at at time zone 'Europe/Rome')::date) as n from games group by player_id),
sett as (select g.*, coalesce(g.nick, p.nick) as chi from games g left join players p on p.id = g.player_id, par where g.season = par.chiusa),
classifica as (
  select league, team, sum(score)::bigint as pts, count(distinct player_id) as tifosi, count(*) as partite,
         rank() over (partition by league order by sum(score) desc) as pos
    from sett group by league, team
),
mvp as (select distinct on (league, team) league, team, chi, sum(score) over (partition by league, team, player_id) as pts
          from sett order by league, team, sum(score) over (partition by league, team, player_id) desc),
per_ora as (select player_id, date_trunc('hour', created_at) h, count(*) n from games group by 1, 2)
select ord, sezione, voce, valore from (
  -- 1) panoramica
  select 1 ord, '1 Panoramica' sezione, 'Settimana chiusa analizzata' voce, (select chiusa from par) valore
  union all select 2, '1 Panoramica', 'Profili creati in totale', (select count(*) from auth.users)::text
  union all select 3, '1 Panoramica', 'Profili con nome e squadra', (select count(*) from players where nick <> 'Tifoso' and team is not null)::text
  union all select 4, '1 Panoramica', 'Profili vuoti (solo aperto il sito, robot compresi)', (select count(*) from auth.users u where not exists (select 1 from players p where p.id = u.id and p.nick <> 'Tifoso'))::text
  union all select 5, '1 Panoramica', 'Giocatori con almeno 1 partita in classifica', (select count(distinct player_id) from games)::text
  union all select 6, '1 Panoramica', 'Partite in classifica in totale', (select count(*) from games)::text
  union all select 7, '1 Panoramica', 'Partite nella settimana chiusa', (select count(*) from sett)::text
  union all select 8, '1 Panoramica', 'Giocatori nella settimana chiusa', (select count(distinct player_id) from sett)::text
  union all select 9, '1 Panoramica', 'Giocatori tornati in almeno 2 giorni diversi', (select count(*) from giorni where n >= 2)::text
  union all select 10, '1 Panoramica', 'Giocatori tornati in almeno 3 giorni diversi', (select count(*) from giorni where n >= 3)::text
  union all select 11, '1 Panoramica', 'Aperto il gioco nelle ultime 24 ore', (select count(distinct player_id) from presence where seen_at > now() - interval '1 day')::text
  union all select 12, '1 Panoramica', 'Aperto il gioco negli ultimi 7 giorni', (select count(distinct player_id) from presence where seen_at > now() - interval '7 days')::text
  union all select 13, '1 Panoramica', 'Arrivati da un invito «Chiama la curva»', (select count(*) from referrals)::text
  -- 2) campioni della settimana chiusa, uno per lega
  union all select 20 + row_number() over (order by c.league), '2 Campioni', c.league,
    c.team || ' · ' || replace(to_char(c.pts, 'FM999G999G999'), ',', '.') || ' punti · ' || c.tifosi || ' tifosi · ' || c.partite || ' partite · MVP ' || coalesce(m.chi, '-') || ' (' || replace(to_char(coalesce(m.pts, 0), 'FM999G999G999'), ',', '.') || ')'
    from classifica c left join mvp m on m.league = c.league and m.team = c.team where c.pos = 1
  -- 3) classifica della settimana chiusa: squadre con punti
  union all select 100 + row_number() over (order by c.league, c.pos), '3 Classifica settimana chiusa', c.league || ' · ' || c.pos || '° ' || c.team,
    replace(to_char(c.pts, 'FM999G999G999'), ',', '.') || ' punti · ' || c.tifosi || ' tifosi · ' || c.partite || ' partite'
    from classifica c
  -- 4) i 15 giocatori che hanno portato più punti nella settimana chiusa
  union all (select 200 + row_number() over (order by sum(score) desc), '4 Migliori giocatori settimana chiusa', max(chi) || ' · ' || max(team),
    replace(to_char(sum(score), 'FM999G999G999'), ',', '.') || ' punti · ' || count(*) || ' partite · max ' || max(score) || ' · serie max ' || max(best_streak) || ' · ' ||
    count(distinct (created_at at time zone 'Europe/Rome')::date) || ' giorni'
    from sett group by player_id order by sum(score) desc limit 15)
  -- 5) segnali da guardare
  union all select 300, '5 Da controllare', 'Partite con più di 15.000 punti', (select count(*) from games where score > 15000)::text
  union all select 301, '5 Da controllare', 'Partite con serie di 30 gol o più', (select count(*) from games where best_streak >= 30)::text
  union all select 302, '5 Da controllare', 'Partite con meno di 2 secondi per tiro', (select count(*) from games where duration_s < shots * 2)::text
  union all select 303, '5 Da controllare', 'Ore con più di 40 partite dello stesso giocatore', (select count(*) from per_ora where n > 40)::text
  union all select 304, '5 Da controllare', 'Nomi usati da più profili',
    coalesce((select string_agg(nick || ' ×' || n, ', ') from (select nick, count(*) n from players where nick <> 'Tifoso' group by nick having count(*) > 1) d), 'nessuno')
  union all select 305, '5 Da controllare', 'Profili creati negli ultimi 7 giorni', (select count(*) from auth.users where created_at > now() - interval '7 days')::text
  union all select 306, '5 Da controllare', 'di cui vuoti (probabili robot)', (select count(*) from auth.users u where u.created_at > now() - interval '7 days' and not exists (select 1 from players p where p.id = u.id and p.nick <> 'Tifoso'))::text
  union all (select 310 + row_number() over (order by g.score desc), '5 Da controllare', 'Partita record: ' || coalesce(g.nick, p.nick, '?') || ' · ' || g.team,
    g.score || ' punti · ' || g.goals || ' gol · serie ' || g.best_streak || ' · ' || round(g.duration_s) || ' s · ' || to_char(g.created_at at time zone 'Europe/Rome', 'DD/MM HH24:MI')
    from games g left join players p on p.id = g.player_id order by g.score desc limit 5)
  -- 6) sfottò
  union all select 400, '6 Sfottò', 'Sfottò scritti in totale', (select count(*) from taunts)::text
  union all select 401, '6 Sfottò', 'Sfottò nella settimana chiusa', (select count(*) from taunts, par where taunts.season = par.chiusa)::text
  union all select 402, '6 Sfottò', 'Nascosti per segnalazioni', (select count(*) from taunts where hidden)::text
  union all select 403, '6 Sfottò', 'Segnalazioni ricevute', (select count(*) from taunt_reports)::text
  -- 7) partite giorno per giorno, ultimi 14 giorni
  union all select 500 + row_number() over (order by d), '7 Partite per giorno', (array['lun','mar','mer','gio','ven','sab','dom'])[extract(isodow from d)::int] || ' ' || to_char(d, 'DD/MM'), n::text || ' partite · ' || g::text || ' giocatori'
    from (select (created_at at time zone 'Europe/Rome')::date d, count(*) n, count(distinct player_id) g from games
           where created_at > now() - interval '14 days' group by 1) x
) t order by ord;
