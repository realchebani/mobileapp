-- EPIC-07 · staff_attach_valuation_report only links a PDF that belongs to
-- the valuation's property: the path must be
-- <owner id>/<property id>/<file> (the folder the owner can read) and the
-- object must already exist in the valuation-reports bucket. Otherwise a
-- report could point at another user's folder (unreadable by the owner) or
-- at a missing file.

create or replace function public.staff_attach_valuation_report(
  p_valuation_id uuid,
  p_storage_path text,
  p_pages smallint
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_prefix text;
begin
  select p.owner_id::text || '/' || p.id::text || '/'
  into v_prefix
  from public.valuations v
  join public.properties p on p.id = v.property_id
  where v.id = p_valuation_id;

  if v_prefix is null then
    raise exception 'Valuation % not found', p_valuation_id
      using errcode = 'P0002';
  end if;

  if p_storage_path is null
    or left(p_storage_path, char_length(v_prefix)) <> v_prefix
    or char_length(p_storage_path) <= char_length(v_prefix) then
    raise exception 'The report path must start with %', v_prefix
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'valuation-reports' and o.name = p_storage_path
  ) then
    raise exception 'No file % in the valuation-reports bucket', p_storage_path
      using errcode = 'P0002';
  end if;

  update public.valuations
  set report_storage_path = p_storage_path, report_pages = p_pages
  where id = p_valuation_id;
end;
$$;

-- create or replace keeps the existing grants; restated for clarity.
revoke execute on function public.staff_attach_valuation_report(uuid, text, smallint)
  from public, anon, authenticated;
