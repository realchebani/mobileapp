-- EPIC-13 · Hardening of the sale lots (review of 20261002091529_multi_biens):
-- - property_lot_is_frozen only answers about the caller's own lots (it is
--   executable by app users for the RLS policies, and must not reveal
--   anything about another seller's lot);
-- - create_property_lot creates a lot and puts its properties in it in one
--   transaction (no partial lot when one of them cannot join), retry-safe;
-- - a property of a frozen lot cannot be deleted (it would change a lot the
--   expert is valuing).
-- Additive: no data is changed.

create or replace function public.property_lot_is_frozen(p_lot_id uuid, p_except uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.properties p
    where p.lot_id = p_lot_id
      and p.id is distinct from p_except
      and p.status in ('in_review', 'certified')
      -- App users only learn about their own lots; staff (no JWT) about all.
      and ((select auth.uid()) is null or p.owner_id = (select auth.uid()))
  );
$$;

-- Creates the lot p_lot_id of the caller (or reuses it: retry-safe) with
-- p_property_ids as members, the first one as main property. Everything is
-- done or nothing (row level security and the lot triggers apply: same
-- owner, open properties, lot not frozen).
create function public.create_property_lot(
  p_lot_id uuid,
  p_property_ids uuid[],
  p_sale_mode text default 'ensemble',
  p_name text default null
)
returns public.property_lots
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_lot public.property_lots;
  v_joined integer;
begin
  if coalesce(array_length(p_property_ids, 1), 0) = 0 then
    raise exception 'lot_without_property' using errcode = 'P0001';
  end if;

  insert into public.property_lots (id, owner_id, name, sale_mode)
  values (p_lot_id, (select auth.uid()), p_name, p_sale_mode)
  on conflict (id) do nothing;

  update public.properties
  set lot_id = p_lot_id
  where id = any(p_property_ids) and lot_id is distinct from p_lot_id;

  select count(*) into v_joined
  from public.properties
  where id = any(p_property_ids) and lot_id = p_lot_id;
  if v_joined <> array_length(p_property_ids, 1) then
    raise exception 'lot_member_not_found' using errcode = 'P0001';
  end if;

  update public.property_lots
  set main_property_id = coalesce(main_property_id, p_property_ids[1])
  where id = p_lot_id
  returning * into v_lot;

  if v_lot.id is null then
    raise exception 'lot_not_found' using errcode = 'P0001';
  end if;
  return v_lot;
end;
$$;

revoke execute on function public.create_property_lot(uuid, uuid[], text, text)
  from public, anon;
grant execute on function public.create_property_lot(uuid, uuid[], text, text)
  to authenticated;

-- A property of a frozen lot cannot be deleted by its owner.
create function public.properties_check_lot_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.lot_id is not null
    and (select auth.uid()) is not null
    and public.property_lot_is_frozen(old.lot_id, old.id) then
    raise exception 'lot_frozen' using errcode = 'P0001';
  end if;
  return old;
end;
$$;

revoke execute on function public.properties_check_lot_delete()
  from public, anon, authenticated;

create trigger properties_check_lot_delete
  before delete on public.properties
  for each row execute function public.properties_check_lot_delete();
