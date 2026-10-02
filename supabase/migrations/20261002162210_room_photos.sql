-- EPIC-15 · Photos of the rooms (V5c) and the vision AI journal
-- (docs/plans/2026-10-02-photos-du-bien.md §2). Additive only.
--
-- - room_photos: the photos of each room of a dossier, stored in the
--   private property-documents bucket under
--   <owner id>/<property id>/photos/<room id>/<photo id>.jpg (the existing
--   Storage policies of lock_document_files already check the owner folder
--   and that the property is open). Same lock as the other child tables:
--   writable only while the property is a draft or submitted.
-- - rooms.photos_count is kept by the database (the value the app sends is
--   ignored).
-- - vision_requests: the journal and daily quotas of the Edge Functions
--   vision-room and plan-reader (read-only for clients; written with the
--   service role, like agent_turns).

-- rooms ---------------------------------------------------------------------------

-- Target of the composite foreign key of room_photos: a photo's room
-- belongs to the photo's property.
alter table public.rooms
  add constraint rooms_id_property_id_key unique (id, property_id);

-- room_photos ---------------------------------------------------------------------

create table public.room_photos (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  room_id uuid not null,
  storage_path text not null unique
    check (char_length(storage_path) <= 500),
  width smallint check (width > 0),
  height smallint check (height > 0),
  size_bytes integer check (size_bytes between 1 and 20971520),
  sort_order smallint not null default 0 check (sort_order >= 0),
  source text not null default 'camera'
    check (source in ('camera', 'library')),
  -- On-device checks: {brightness, sharpness, tilt_deg, issues[]}.
  quality jsonb check (quality is null or jsonb_typeof(quality) = 'object'),
  -- Vision AI suggestions (Edge Function vision-room, service role only).
  analysis jsonb check (analysis is null or jsonb_typeof(analysis) = 'object'),
  taken_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint room_photos_room_fkey foreign key (room_id, property_id)
    references public.rooms (id, property_id) on delete cascade
);

comment on table public.room_photos is
  'EPIC-15 · photos of the rooms of a seller dossier (V5c), for the expert '
  'and the future listing.';

create index room_photos_property_id_idx on public.room_photos (property_id);
create index room_photos_room_idx on public.room_photos (room_id, sort_order);

create trigger room_photos_set_updated_at
  before update on public.room_photos
  for each row execute function public.seller_tunnel_set_updated_at();

-- Limits: 12 photos per room, 150 per property. The advisory lock
-- serializes the inserts of one property so that the counts cannot be
-- bypassed by parallel uploads.
create function public.room_photos_check_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(
    hashtext('room_photos_property_' || new.property_id::text)
  );
  if (
    select count(*) from public.room_photos ph where ph.room_id = new.room_id
  ) >= 12 or (
    select count(*) from public.room_photos ph
    where ph.property_id = new.property_id
  ) >= 150 then
    raise exception 'room_photo_limit_reached'
      using errcode = 'P0001',
        hint = 'At most 12 photos per room and 150 per property.';
  end if;
  return new;
end;
$$;

revoke execute on function public.room_photos_check_limits()
  from public, anon, authenticated;

create trigger room_photos_check_limits
  before insert on public.room_photos
  for each row execute function public.room_photos_check_limits();

-- rooms.photos_count: recomputed on every write of a room (whatever the
-- app sends), and refreshed when a photo is added, moved or deleted.
create function public.rooms_set_photos_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.photos_count := (
    select count(*) from public.room_photos ph where ph.room_id = new.id
  );
  return new;
end;
$$;

revoke execute on function public.rooms_set_photos_count()
  from public, anon, authenticated;

create trigger rooms_set_photos_count
  before insert or update on public.rooms
  for each row execute function public.rooms_set_photos_count();

create function public.room_photos_refresh_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The value is recomputed by rooms_set_photos_count.
  if tg_op in ('INSERT', 'UPDATE') then
    update public.rooms set photos_count = 0 where id = new.room_id;
  end if;
  if tg_op in ('DELETE', 'UPDATE') then
    update public.rooms set photos_count = 0 where id = old.room_id;
  end if;
  return null;
end;
$$;

revoke execute on function public.room_photos_refresh_count()
  from public, anon, authenticated;

create trigger room_photos_refresh_count
  after insert or delete or update of room_id on public.room_photos
  for each row execute function public.room_photos_refresh_count();

-- RLS: like the other child tables of the seller tunnel (owner only,
-- writes while the property is a draft or submitted).
alter table public.room_photos enable row level security;

create policy "Owners can view the room_photos of their properties"
  on public.room_photos for select
  to authenticated
  using (exists (
    select 1 from public.properties p
    where p.id = property_id and p.owner_id = (select auth.uid())
  ));

create policy "Owners can add room_photos to open properties"
  on public.room_photos for insert
  to authenticated
  with check (exists (
    select 1 from public.properties p
    where p.id = property_id and p.owner_id = (select auth.uid())
      and p.status in ('draft', 'submitted')
  ));

create policy "Owners can update the room_photos of open properties"
  on public.room_photos for update
  to authenticated
  using (exists (
    select 1 from public.properties p
    where p.id = property_id and p.owner_id = (select auth.uid())
      and p.status in ('draft', 'submitted')
  ))
  with check (exists (
    select 1 from public.properties p
    where p.id = property_id and p.owner_id = (select auth.uid())
      and p.status in ('draft', 'submitted')
  ));

create policy "Owners can delete the room_photos of open properties"
  on public.room_photos for delete
  to authenticated
  using (exists (
    select 1 from public.properties p
    where p.id = property_id and p.owner_id = (select auth.uid())
      and p.status in ('draft', 'submitted')
  ));

-- A photo row must point into the photos folder of its own property.
create policy "Room photos are stored in the property photos folder"
  on public.room_photos as restrictive for insert
  to authenticated
  with check (
    storage_path like (select auth.uid())::text || '/'
      || property_id::text || '/photos/%'
  );

-- Grants: the analysis is backend-only; only the order can change.
revoke all on table public.room_photos from anon, authenticated;
grant select, delete on table public.room_photos to authenticated;
grant insert (
  id, property_id, room_id, storage_path, width, height, size_bytes,
  sort_order, source, quality, taken_at
) on table public.room_photos to authenticated;
grant update (sort_order) on table public.room_photos to authenticated;

-- vision_requests -------------------------------------------------------------------

create table public.vision_requests (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  property_id uuid not null references public.properties (id)
    on delete cascade,
  kind text not null check (kind in ('room_photo', 'plan')),
  -- The room photo or the plan document.
  target_id uuid not null,
  model text check (char_length(model) <= 100),
  tokens_in integer,
  tokens_out integer,
  cost_usd numeric(8, 5),
  ms integer,
  error text check (char_length(error) <= 500),
  created_at timestamptz not null default now()
);

comment on table public.vision_requests is
  'EPIC-15 · calls of the vision AI (vision-room, plan-reader): quotas, cost '
  'and errors. Written by the Edge Functions with the service role.';

create index vision_requests_owner_day
  on public.vision_requests (owner_id, kind, created_at);
create index vision_requests_property_id_idx
  on public.vision_requests (property_id);

alter table public.vision_requests enable row level security;

create policy "Owners can view their vision requests"
  on public.vision_requests for select
  to authenticated
  using (owner_id = (select auth.uid()));

-- No insert / update / delete policy: writes go through the service role.
revoke all on table public.vision_requests from anon, authenticated;
grant select on table public.vision_requests to authenticated;

-- Checks the caller's daily quota of [p_kind] and records a new request in
-- ONE transaction, serialised per user (advisory lock): parallel requests
-- cannot all pass the check. Returns the new request id, or null when the
-- quota is used up. The request starts claimed (error = 'in_progress').
create function public.vision_reserve_request(
  p_owner_id uuid,
  p_property_id uuid,
  p_kind text,
  p_target_id uuid,
  p_since timestamptz,
  p_max integer
)
returns uuid
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
  select count(*) into used
    from public.vision_requests
    where owner_id = p_owner_id and kind = p_kind and created_at >= p_since;
  if used + 1 > p_max then
    return null;
  end if;
  insert into public.vision_requests (
    owner_id, property_id, kind, target_id, error
  ) values (p_owner_id, p_property_id, p_kind, p_target_id, 'in_progress')
    returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.vision_reserve_request(
  uuid, uuid, text, uuid, timestamptz, integer
) from public, anon, authenticated;
grant execute on function public.vision_reserve_request(
  uuid, uuid, text, uuid, timestamptz, integer
) to service_role;
