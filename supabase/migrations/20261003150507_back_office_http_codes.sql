-- EPIC-12: HTTP-friendly error codes for the bo_* functions.
--
-- 40001 (serialization_failure) made PostgREST retry bo_save_draft on a
-- draft conflict until the request timed out, and P0002 / 55000 came back
-- as HTTP 500. PostgREST maps the SQLSTATE 'PTxyz' to the HTTP status xyz:
-- not found → PT404, conflicts and wrong states → PT409. Messages
-- (dossier_not_found, draft_conflict…) are unchanged; the staff_* runbook
-- functions are not touched.

do $$
declare
  v_fn record;
  v_def text;
begin
  for v_fn in
    select p.oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'bo\_%' or p.proname like '\_bo\_%')
  loop
    v_def := pg_get_functiondef(v_fn.oid);
    if v_def ~ 'errcode = ''(P0002|40001|55000)''' then
      v_def := replace(v_def, 'errcode = ''P0002''', 'errcode = ''PT404''');
      v_def := replace(v_def, 'errcode = ''40001''', 'errcode = ''PT409''');
      v_def := replace(v_def, 'errcode = ''55000''', 'errcode = ''PT409''');
      execute v_def;
    end if;
  end loop;
end;
$$;
