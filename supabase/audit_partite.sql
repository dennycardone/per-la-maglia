-- Per la Maglia · Come giocano i nuovi giocatori (solo lettura: non modifica niente)
-- Una riga per giocatore arrivato dal 23/10, più una riga TOTALE in fondo.
with nuovi as (
  select u.id, coalesce(p.nick, '(senza nome)') as nick, p.team
    from auth.users u left join players p on p.id = u.id
   where u.created_at >= timestamptz '2026-10-23 00:00 Europe/Rome'
),
g as (select g.*, n.nick as pnick, n.team as pteam from games g join nuovi n on n.id = g.player_id)
select * from (
  select pnick as giocatore, pteam as squadra,
         count(*) as partite,
         round(avg(goals), 1) as gol_medi,
         max(goals) as gol_max,
         round(100.0 * count(*) filter (where goals = 0) / count(*)) as perc_zero_gol,
         round(100.0 * sum(perfect) / nullif(sum(goals), 0)) as perc_perfetti,
         max(best_streak) as serie_max,
         round(avg(duration_s)) as durata_media_s,
         max(score) as punteggio_max,
         sum(score) as punti_totali,
         count(distinct (created_at at time zone 'Europe/Rome')::date) as giorni_giocati,
         to_char(max(created_at) at time zone 'Europe/Rome', 'DD/MM HH24:MI') as ultima_partita,
         0 as ord
    from g group by pnick, pteam
  union all
  select 'TOTALE', count(distinct player_id) || ' giocatori', count(*), round(avg(goals), 1), max(goals),
         round(100.0 * count(*) filter (where goals = 0) / nullif(count(*), 0)),
         round(100.0 * sum(perfect) / nullif(sum(goals), 0)), max(best_streak), round(avg(duration_s)),
         max(score), sum(score), count(distinct (created_at at time zone 'Europe/Rome')::date),
         to_char(max(created_at) at time zone 'Europe/Rome', 'DD/MM HH24:MI'), 1
    from g
) t order by ord, partite desc;
