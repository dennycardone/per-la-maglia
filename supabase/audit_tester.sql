-- Per la Maglia · Controllo dei nuovi giocatori (solo lettura: non modifica niente)
-- Incolla tutto nell'editor SQL di Supabase e premi Run. Cambia la data qui sotto se serve.
with par as (select timestamptz '2026-10-23 00:00 Europe/Rome' as da),
nuovi as (
  select u.id, u.created_at, u.last_sign_in_at, p.nick, p.team, p.ref_code,
         (select count(*) from games g where g.player_id = u.id) as partite,
         (select max(g.created_at) from games g where g.player_id = u.id) as ultima_partita,
         (select max(seen_at) from presence s where s.player_id = u.id) as visto,
         exists (select 1 from referrals r where r.invitee = u.id) as invitato
    from auth.users u left join players p on p.id = u.id, par
   where u.created_at >= par.da
),
g_nuovi as (select g.* from games g join nuovi n on n.id = g.player_id)
select ord, sezione, voce, valore from (
  select 1 ord, '1 Riepilogo' sezione, 'Nuovi profili creati' voce, count(*)::text valore from nuovi
  union all select 2, '1 Riepilogo', 'Con nome scelto (non "Tifoso")', count(*) filter (where nick is not null and nick <> 'Tifoso')::text from nuovi
  union all select 3, '1 Riepilogo', 'Con squadra scelta', count(*) filter (where team is not null)::text from nuovi
  union all select 4, '1 Riepilogo', 'Con almeno 1 partita in classifica', count(*) filter (where partite > 0)::text from nuovi
  union all select 5, '1 Riepilogo', 'Aperto il gioco nelle ultime 24 ore', count(*) filter (where visto > now() - interval '1 day')::text from nuovi
  union all select 6, '1 Riepilogo', 'Arrivati da un invito', count(*) filter (where invitato)::text from nuovi
  union all select 7, '1 Riepilogo', 'Profili senza nome salvato (solo aperto il gioco)', count(*) filter (where nick is null)::text from nuovi
  -- 2) partite dei nuovi
  union all select 10, '2 Partite', 'Partite totali dei nuovi', count(*)::text from g_nuovi
  union all select 11, '2 Partite', 'Gol medi per partita', coalesce(round(avg(goals), 1)::text, '-') from g_nuovi
  union all select 12, '2 Partite', 'Partite chiuse con 0 gol', count(*) filter (where goals = 0)::text from g_nuovi
  union all select 13, '2 Partite', 'Durata media (secondi)', coalesce(round(avg(duration_s))::text, '-') from g_nuovi
  union all select 14, '2 Partite', 'Partite sotto i 20 secondi', count(*) filter (where duration_s < 20)::text from g_nuovi
  union all select 15, '2 Partite', 'Punteggio medio', coalesce(round(avg(score))::text, '-') from g_nuovi
  -- 3) segnali di problemi
  union all select 20, '3 Possibili problemi', 'Nomi usati da più profili (reinstallazioni o due browser)',
    coalesce(string_agg(nick || ' ×' || n, ', '), 'nessuno') from (
      select nick, count(*) n from players where nick <> 'Tifoso' group by nick having count(*) > 1) d
  union all select 21, '3 Possibili problemi', 'Profili con lo stesso nome creati dal 23/10',
    coalesce(string_agg(distinct n1.nick, ', '), 'nessuno') from nuovi n1
      where n1.nick <> 'Tifoso' and exists (select 1 from players p where p.nick = n1.nick and p.id <> n1.id)
  union all select 22, '3 Possibili problemi', 'Sfottò nascosti per segnalazioni', count(*)::text from taunts where hidden
  union all select 23, '3 Possibili problemi', 'Segnalazioni ricevute dal 23/10', count(*)::text from taunt_reports, par where taunt_reports.created_at >= par.da
  -- 4) uno per uno
  union all select 100 + row_number() over (order by created_at), '4 Giocatori',
    coalesce(nick, '(senza nome)') || ' · ' || coalesce(team, 'nessuna squadra'),
    partite || ' partite · creato ' || to_char(created_at at time zone 'Europe/Rome', 'DD/MM HH24:MI')
      || ' · ultimo segno di vita ' || coalesce(to_char(greatest(visto, ultima_partita, last_sign_in_at) at time zone 'Europe/Rome', 'DD/MM HH24:MI'), '-')
    from nuovi
) t order by ord;
