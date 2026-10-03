-- EPIC-11 · Purge of the deactivated accounts: account_purge_finish also
-- deletes the auth user when the Auth admin API did not find it (a user
-- the API does not know, e.g. created by SQL, would otherwise survive the
-- purge). The deletion cascades like the API's.

create or replace function public.account_purge_finish(
  p_user_id uuid,
  p_files_count integer
)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.users where id = p_user_id;
  update public.account_deletions
  set deleted_at = now(),
      files_count = files_count + greatest(p_files_count, 0)
  where user_id = p_user_id;
$$;

revoke all on function public.account_purge_finish(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.account_purge_finish(uuid, integer)
  to service_role;
