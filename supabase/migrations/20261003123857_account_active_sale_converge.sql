-- EPIC-11 × EPIC-08 · One definition of an "active sale": the account
-- deletion (deactivate_account, the purge checks) now asks EPIC-08's
-- has_active_sale(owner) (stages mandate_signed, published; EPIC-10 will
-- extend it there only). Without it (older database), the former check of
-- the sales table stays as a fallback.

create or replace function public.account_has_active_sale(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active boolean := false;
begin
  if to_regprocedure('public.has_active_sale(uuid)') is not null then
    execute 'select public.has_active_sale($1)' into v_active using p_user_id;
    return coalesce(v_active, false);
  end if;
  if to_regclass('public.sales') is null then
    return false;
  end if;
  execute 'select exists (select 1 from public.sales s '
    || 'where s.owner_id = $1 and s.stage in '
    || '(''mandate_signed'', ''published''))'
    into v_active
    using p_user_id;
  return v_active;
end;
$$;

revoke all on function public.account_has_active_sale(uuid)
  from public, anon, authenticated;
