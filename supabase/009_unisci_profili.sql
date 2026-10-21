-- Per la Maglia · 009 · Unire due profili dello stesso giocatore
-- Serve quando un giocatore cambia telefono o indirizzo e il gioco gli crea un profilo nuovo:
-- partite, punti, sfottò e tifosi portati del profilo vecchio passano a quello nuovo.
-- La funzione la può usare solo chi gestisce il database (qui, nell'editor SQL), mai il gioco.

create or replace function public.merge_players(p_old uuid, p_new uuid) returns text
language plpgsql security definer set search_path = public as $$
declare n_games int; v_code text;
begin
  if p_old = p_new then return 'Sono lo stesso profilo: niente da fare'; end if;
  if not exists (select 1 from players where id = p_old) then return 'Profilo vecchio non trovato'; end if;
  if not exists (select 1 from players where id = p_new) then return 'Profilo nuovo non trovato'; end if;

  update games set player_id = p_new where player_id = p_old;
  get diagnostics n_games = row_count;
  update taunts set player_id = p_new where player_id = p_old;
  delete from taunt_reports r where r.reporter = p_old and exists (select 1 from taunt_reports x where x.reporter = p_new and x.taunt_id = r.taunt_id);
  update taunt_reports set reporter = p_new where reporter = p_old;

  -- tifosi portati: quelli invitati dal vecchio profilo ora contano per il nuovo
  update referrals set inviter = p_new where inviter = p_old;
  delete from referrals where invitee = p_new and inviter = p_new;
  if not exists (select 1 from referrals where invitee = p_new) then
    update referrals set invitee = p_new where invitee = p_old;
  else
    delete from referrals where invitee = p_old;
  end if;
  -- il link d'invito vecchio continua a funzionare
  select ref_code into v_code from players where id = p_old;
  if v_code is not null and (select ref_code from players where id = p_new) is null then
    update players set ref_code = null where id = p_old;
    update players set ref_code = v_code where id = p_new;
  end if;
  -- il nome: se sul nuovo è ancora quello di partenza, prende quello vecchio
  update players n set nick = o.nick, team = coalesce(n.team, o.team)
    from players o where o.id = p_old and n.id = p_new and n.nick = 'Tifoso';
  delete from presence where player_id = p_old;

  return 'Fatto: ' || n_games || ' partite spostate sul profilo nuovo';
end $$;
revoke all on function public.merge_players(uuid, uuid) from public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────────────────
-- COME SI USA (dopo aver eseguito una volta tutto quello sopra)
-- 1) Sul telefono nuovo metti lo stesso nome di prima e gioca una partita.
-- 2) Esegui solo la query qui sotto, togliendo i "--" davanti (cambia il nome tra apici se serve).
--    "profili" deve essere 2 (il vecchio e il nuovo); "comando" è già pronto.
-- 3) Copia il testo di "comando", incollalo qui ed eseguilo: deve rispondere "Fatto: … partite spostate".
--
-- with p as (
--   select pl.id, u.created_at, (select count(*) from games g where g.player_id = pl.id) as n
--     from players pl join auth.users u on u.id = pl.id
--    where pl.nick ilike 'Denny' or exists (select 1 from games g where g.player_id = pl.id and g.nick ilike 'Denny'))
-- select (select count(*) from p) as profili,
--        'select public.merge_players(''' || (select id from p order by n desc, created_at limit 1) || ''', '''
--          || (select id from p order by created_at desc limit 1) || ''');' as comando;
