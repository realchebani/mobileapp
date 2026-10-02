-- Hardening of the room photos and the vision AI (EPIC-15 backlog,
-- docs/plans/2026-10-02-photos-du-bien.md §6 and § « Durcissement »).
-- Additive only: new functions and one trigger.
--
-- - reorder_room_photos: the order of the photos of a room in ONE
--   transaction (no partial order when a write fails).
-- - room_photos_keep_main_photo: once a dossier is submitted, the seller
--   cannot delete the last photo of a main room (same rule as V7, which
--   blocks sending without it). Staff (no JWT) are not concerned.
-- - vision_reserve_target: like vision_reserve_request, but refuses a
--   second analysis of the same photo / plan while one is in progress.
-- - vision_save_photo_analysis / vision_save_plan_reading: store a result
--   only if the property is still a draft, checked at write time (the
--   property row is share-locked: a submission waits for the write).
-- - staff_orphan_files: files of the property-documents bucket that no
--   row references any more (documents — plans included — and room
--   photos), for the cleanup runbook. Lists only, never deletes.

-- reorder_room_photos ---------------------------------------------------------------

-- Gives the photos [p_photo_ids] of the room [p_room_id] the order of the
-- array (sort_order 0, 1, …) and returns the photos of the room in their
-- new order. Runs with the caller's rights (RLS: owner, open dossier);
-- raises room_photos_order_invalid, and changes nothing, when an id is
-- repeated or is not a photo of the room the caller may change.
create function public.reorder_room_photos(
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
  ) then
    raise exception 'room_photos_order_invalid'
      using errcode = 'P0001', hint = 'Each photo id must appear once.';
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

-- room_photos_keep_main_photo -------------------------------------------------------

-- After a photo is deleted by a seller (JWT), a main room of a submitted
-- dossier of a type with rooms (null, maison, appartement, autre — the
-- PropertyTypeProfile.requiresRoomPhotos of the app) must still have a
-- photo. A photo deleted with its room or its property (cascade) is not
-- concerned: the room is gone.
create function public.room_photos_keep_main_photo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return null;
  end if;
  if exists (
    select 1
    from public.rooms r
    join public.properties p on p.id = r.property_id
    where r.id = old.room_id
      and r.is_main
      and p.status = 'submitted'
      and (p.property_type is null
        or p.property_type in ('maison', 'appartement', 'autre'))
  ) and not exists (
    select 1 from public.room_photos ph where ph.room_id = old.room_id
  ) then
    raise exception 'room_photo_required'
      using errcode = 'P0001',
        hint = 'A main room of a submitted dossier keeps at least one photo.';
  end if;
  return null;
end;
$$;

revoke execute on function public.room_photos_keep_main_photo()
  from public, anon, authenticated;

create trigger room_photos_keep_main_photo
  after delete on public.room_photos
  for each row execute function public.room_photos_keep_main_photo();

-- vision_reserve_target -------------------------------------------------------------

-- vision_reserve_request + deduplication: in ONE transaction serialised per
-- user, (1) 'busy' when a request for the same target started less than
-- [p_busy_seconds] ago and is still in progress, (2) 'quota' when the
-- daily quota of [p_kind] is used up, else (3) 'reserved' with the new
-- request id (error = 'in_progress' until the function finishes it).
create function public.vision_reserve_target(
  p_owner_id uuid,
  p_property_id uuid,
  p_kind text,
  p_target_id uuid,
  p_since timestamptz,
  p_max integer,
  p_busy_seconds integer
)
returns table (request_id uuid, outcome text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  used integer;
  new_id uuid;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('vision_quota:' || p_owner_id::text, 0)
  );
  if exists (
    select 1 from public.vision_requests vr
    where vr.owner_id = p_owner_id and vr.kind = p_kind
      and vr.target_id = p_target_id and vr.error = 'in_progress'
      and vr.created_at > now() - make_interval(secs => p_busy_seconds)
  ) then
    return query select null::uuid, 'busy'::text;
    return;
  end if;
  select count(*) into used
    from public.vision_requests vr
    where vr.owner_id = p_owner_id and vr.kind = p_kind
      and vr.created_at >= p_since;
  if used + 1 > p_max then
    return query select null::uuid, 'quota'::text;
    return;
  end if;
  insert into public.vision_requests (
    owner_id, property_id, kind, target_id, error
  ) values (p_owner_id, p_property_id, p_kind, p_target_id, 'in_progress')
    returning id into new_id;
  return query select new_id, 'reserved'::text;
end;
$$;

revoke all on function public.vision_reserve_target(
  uuid, uuid, text, uuid, timestamptz, integer, integer
) from public, anon, authenticated;
grant execute on function public.vision_reserve_target(
  uuid, uuid, text, uuid, timestamptz, integer, integer
) to service_role;

-- vision_save_photo_analysis / vision_save_plan_reading -----------------------------

-- Stores the analysis of the photo [p_photo_id] of [p_owner_id] if its
-- property is still a draft (checked under a share lock of the property
-- row); false otherwise (nothing written).
create function public.vision_save_photo_analysis(
  p_owner_id uuid,
  p_photo_id uuid,
  p_analysis jsonb
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1
    from public.properties p
    join public.room_photos ph on ph.property_id = p.id
    where ph.id = p_photo_id and p.owner_id = p_owner_id
      and p.status = 'draft'
    for share of p;
  if not found then
    return false;
  end if;
  update public.room_photos set analysis = p_analysis where id = p_photo_id;
  return true;
end;
$$;

-- Stores the reading of the plan [p_document_id] of [p_owner_id] in
-- extracted.plan_reading (other keys kept, merged in the database) if its
-- property is still a draft; false otherwise.
create function public.vision_save_plan_reading(
  p_owner_id uuid,
  p_document_id uuid,
  p_reading jsonb
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform 1
    from public.properties p
    join public.property_documents d on d.property_id = p.id
    where d.id = p_document_id and p.owner_id = p_owner_id
      and p.status = 'draft'
    for share of p;
  if not found then
    return false;
  end if;
  update public.property_documents
    set extracted = case
        when jsonb_typeof(extracted) = 'object' then extracted
        else '{}'::jsonb
      end || jsonb_build_object('plan_reading', p_reading)
    where id = p_document_id;
  return true;
end;
$$;

revoke all on function public.vision_save_photo_analysis(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.vision_save_photo_analysis(uuid, uuid, jsonb)
  to service_role;
revoke all on function public.vision_save_plan_reading(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.vision_save_plan_reading(uuid, uuid, jsonb)
  to service_role;

-- staff_orphan_files ----------------------------------------------------------------

-- Files of the property-documents bucket older than [p_min_age] (uploads
-- in flight are left out) that no property_documents row (plans included)
-- nor room_photos row references. property_exists tells whether the
-- property of the folder still exists. Read-only: deleting goes through
-- the Storage API (runbook certifier-un-dossier.md, « Fichiers orphelins »).
create function public.staff_orphan_files(
  p_min_age interval default interval '1 day'
)
returns table (
  path text,
  size_bytes bigint,
  created_at timestamptz,
  owner_folder text,
  property_folder text,
  property_exists boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    o.name,
    (o.metadata ->> 'size')::bigint,
    o.created_at,
    split_part(o.name, '/', 1),
    split_part(o.name, '/', 2),
    exists (
      select 1 from public.properties p
      where p.id::text = split_part(o.name, '/', 2)
    )
  from storage.objects o
  where o.bucket_id = 'property-documents'
    and o.created_at < now() - p_min_age
    and o.name not like '%/.emptyFolderPlaceholder'
    and not exists (
      select 1 from public.property_documents d where d.storage_path = o.name
    )
    and not exists (
      select 1 from public.room_photos ph where ph.storage_path = o.name
    )
  order by o.created_at;
$$;

revoke execute on function public.staff_orphan_files(interval)
  from public, anon, authenticated;
grant execute on function public.staff_orphan_files(interval) to service_role;
