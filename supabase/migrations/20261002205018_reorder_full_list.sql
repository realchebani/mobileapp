-- reorder_room_photos (photos_hardening) now requires the FULL order of the
-- room: the array must hold every photo of the room exactly once. A photo
-- added meanwhile (another device) makes the call fail instead of leaving
-- two photos with the same position. Same signature, rights and grants.

create or replace function public.reorder_room_photos(
  p_room_id uuid,
  p_photo_ids uuid[]
)
returns setof public.room_photos
language plpgsql
security invoker
set search_path = ''
as $$
declare
  wanted integer := coalesce(cardinality(p_photo_ids), 0);
  changed integer;
begin
  if wanted > 150 or wanted <> (
    select count(distinct ids.id) from unnest(p_photo_ids) as ids (id)
  ) or wanted <> (
    select count(*) from public.room_photos ph where ph.room_id = p_room_id
  ) then
    raise exception 'room_photos_order_invalid'
      using errcode = 'P0001',
        hint = 'Give every photo of the room exactly once.';
  end if;
  if wanted > 0 then
    update public.room_photos ph
      set sort_order = (o.position - 1)::smallint
      from unnest(p_photo_ids) with ordinality as o (id, position)
      where ph.id = o.id and ph.room_id = p_room_id;
    get diagnostics changed = row_count;
    if changed <> wanted then
      raise exception 'room_photos_order_invalid'
        using errcode = 'P0001',
          hint = 'Every id must be a photo of the room of an open dossier.';
    end if;
  end if;
  return query
    select * from public.room_photos ph
    where ph.room_id = p_room_id
    order by ph.sort_order, ph.created_at;
end;
$$;

revoke all on function public.reorder_room_photos(uuid, uuid[])
  from public, anon;
grant execute on function public.reorder_room_photos(uuid, uuid[])
  to authenticated;
