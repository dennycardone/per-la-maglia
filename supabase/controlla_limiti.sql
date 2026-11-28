-- Per la Maglia · prova dei nuovi limiti sulle partite già giocate (solo lettura: non modifica niente)
-- Quante partite vere sarebbero state rifiutate con i limiti dello script 014. Devono essere 0 (o quasi).
with lim as (
  select g.*, coalesce(g.nick, p.nick) as chi,
         case when g.goals <= 0 then 0 when g.goals <= 21 then ceil(675 * (g.goals + 0.1 * g.goals * (g.goals - 1) / 2.0)) + g.goals
              else 675 * 42 + 2025 * (g.goals - 21) + g.goals end as tetto
    from games g left join players p on p.id = g.player_id
)
select 'Partite in totale' as voce, count(*)::text as valore from lim
union all select 'Sotto 2,5 secondi per tiro', count(*)::text from lim where duration_s < shots * 2.5
union all select 'Più punti del nuovo tetto', count(*)::text from lim where score > tetto
union all select 'Il più veloce (secondi per tiro)', (select round(min(duration_s / nullif(shots, 0)), 2)::text from lim where shots >= 10)
union all (select 'Esempio: ' || chi || ' · ' || to_char(created_at at time zone 'Europe/Rome', 'DD/MM HH24:MI'),
                  score || ' punti / tetto ' || tetto || ' · ' || round(duration_s / nullif(shots, 0), 2) || ' s a tiro'
             from lim where duration_s < shots * 2.5 or score > tetto order by created_at desc limit 10);
