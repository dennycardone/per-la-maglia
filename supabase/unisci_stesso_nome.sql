-- Per la Maglia · Unire i profili doppi di uno stesso giocatore (stesso nome, stessa squadra)
-- Serve quando un giocatore ha perso il profilo più volte (per esempio cancellando i dati del browser).
-- Richiede lo script 009 (funzione merge_players), già eseguito.
-- Nome e squadra sono scritti in due punti per ogni passo: 'sasa' e 'Monza'. Maiuscole e minuscole del nome non contano.
--
-- PASSO 1 · GUARDA (non modifica niente). Esegui solo questo blocco e controlla l'elenco:
--   "RESTA" è il profilo che rimane (quello salvato con Google, altrimenti quello con la partita più recente);
--   gli altri verranno uniti a lui. Se nell'elenco c'è una persona diversa, fermati.
with cand as (
  select pl.id, coalesce(u.is_anonymous, false) as anon, u.created_at,
         (select max(g.created_at) from games g where g.player_id = pl.id) as ultima
    from players pl join auth.users u on u.id = pl.id
   where (pl.team = 'Monza' and pl.nick ilike 'sasa')
      or exists (select 1 from games g where g.player_id = pl.id and g.team = 'Monza' and g.nick ilike 'sasa')),
keep as (select id from cand order by anon, ultima desc nulls last, created_at desc limit 1)
select left(c.id::text, 8) as profilo, pl.nick as nome, pl.team as squadra,
       to_char(c.created_at at time zone 'Europe/Rome', 'DD/MM HH24:MI') as creato,
       case when c.anon then 'senza Google' else 'salvato con Google' end as tipo,
       (select count(*) from games g where g.player_id = c.id) as partite,
       (select coalesce(sum(g.score), 0) from games g where g.player_id = c.id) as punti,
       coalesce(to_char(c.ultima at time zone 'Europe/Rome', 'DD/MM HH24:MI'), '') as ultima_partita,
       case when c.id = (select id from keep) then 'RESTA' when c.anon then 'verrà unito' else 'salvato con Google: non si tocca' end as cosa_succede
  from cand c join players pl on pl.id = c.id
 order by c.created_at;

-- PASSO 2 · UNISCI. Solo dopo aver controllato l'elenco: togli i "--" davanti alle righe qui sotto ed esegui solo queste.
-- Per ogni profilo doppio risponde "Fatto: N partite spostate sul profilo nuovo".
--
-- with cand as (
--   select pl.id, coalesce(u.is_anonymous, false) as anon, u.created_at,
--          (select max(g.created_at) from games g where g.player_id = pl.id) as ultima
--     from players pl join auth.users u on u.id = pl.id
--    where (pl.team = 'Monza' and pl.nick ilike 'sasa')
--       or exists (select 1 from games g where g.player_id = pl.id and g.team = 'Monza' and g.nick ilike 'sasa')),
-- keep as (select id from cand order by anon, ultima desc nulls last, created_at desc limit 1)
-- select left(c.id::text, 8) as profilo, public.merge_players(c.id, (select id from keep)) as esito
--   from cand c
--  where c.anon and c.id <> (select id from keep);
