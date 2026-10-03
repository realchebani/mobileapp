-- EPIC-08 · Formules & mise en vente (docs/plans/2026-10-03-offres-et-mise-en-vente.md
-- §2, owner decisions of 2026-10-03). Additive only.
--
-- - sales: a sale of one property OR of one sale lot (the lot as a whole,
--   or its properties one by one when its mode is ensemble_ou_separe; a lot
--   can be put on sale as soon as its main property is certified). The
--   state columns are only written by the RPCs below (security definer).
-- - mandates / mandate_signatures: TEST mandates only (is_test, drawn
--   signature, PDF "SPÉCIMEN" rendered by the Edge Function render-mandate
--   into the sale-documents bucket).
-- - sale_requests: services asked without payment (callback for Premium,
--   photo shoot, diagnostics), handled by the team.
-- - listing_photos + bucket listing-media: the photos of the listing,
--   copied from the dossier (room_photos, all of them, owner decision) or
--   taken for the listing; never the identity document or other documents.
-- - property_owners.identity_verified_at (team only).
-- - notifications.kind: the fixed list becomes a format check (idempotent,
--   shared with the sibling epics).
-- - has_active_sale(owner): used by EPIC-11 (account deletion).
-- - staff_* functions (SQL editor until the back office, EPIC-12).

-- ---------------------------------------------------------------------------
-- Notifications: any snake_case kind (the app reads unknown kinds as other).
-- ---------------------------------------------------------------------------

-- Same statement as EPIC-11 / EPIC-12 (whichever runs last wins, same
-- check).
alter table public.notifications
  drop constraint if exists notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check
  check (kind ~ '^[a-z][a-z_]{2,39}$');

-- ---------------------------------------------------------------------------
-- Identity of the owners, verified by the team.
-- ---------------------------------------------------------------------------

alter table public.property_owners
  add column identity_verified_at timestamptz,
  add column identity_verified_by uuid references auth.users (id)
    on delete set null;

comment on column public.property_owners.identity_verified_at is
  'EPIC-08 · identity checked by the team (staff_verify_identity); '
  'required before signing an Expert mandate.';

-- The table has a table-wide update grant: app users cannot change the
-- verification (kept as it was); staff (no JWT) can.
create function public.property_owners_keep_verification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null then
    if tg_op = 'INSERT' then
      new.identity_verified_at := null;
      new.identity_verified_by := null;
    else
      new.identity_verified_at := old.identity_verified_at;
      new.identity_verified_by := old.identity_verified_by;
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.property_owners_keep_verification()
  from public, anon, authenticated;

create trigger property_owners_keep_verification
  before insert or update on public.property_owners
  for each row execute function public.property_owners_keep_verification();

-- ---------------------------------------------------------------------------
-- sales
-- ---------------------------------------------------------------------------

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  property_id uuid references public.properties (id) on delete cascade,
  lot_id uuid references public.property_lots (id) on delete cascade,
  formula text not null check (formula in ('essentiel', 'premium', 'expert')),
  stage text not null default 'plan_chosen' check (stage in (
    'plan_chosen', 'mandate_signed', 'published', 'withdrawn'
  )),
  asking_price_eur integer
    check (asking_price_eur between 1000 and 100000000),
  listing_title text check (char_length(listing_title) <= 120),
  listing_description text check (char_length(listing_description) <= 2000),
  description_source text
    check (description_source in ('template', 'ai', 'seller')),
  ai_retouch_wanted boolean not null default false,
  home_staging_wanted boolean not null default false,
  -- The dossier photos were copied into the listing once (later removals
  -- by the seller are kept).
  photos_imported_at timestamptz,
  is_test boolean not null default true,
  formula_chosen_at timestamptz not null default now(),
  mandate_signed_at timestamptz,
  published_at timestamptz,
  withdrawn_at timestamptz,
  withdraw_reason text check (char_length(withdraw_reason) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_one_target check (num_nonnulls(property_id, lot_id) = 1)
);

comment on table public.sales is
  'EPIC-08 · sale of a property or of a sale lot (formula, mandate stage, '
  'listing). State columns are written by RPCs only.';

create index sales_owner_id_idx on public.sales (owner_id);
create unique index sales_one_active_per_property
  on public.sales (property_id) where stage <> 'withdrawn';
create unique index sales_one_active_per_lot
  on public.sales (lot_id) where stage <> 'withdrawn';

create trigger sales_set_updated_at
  before update on public.sales
  for each row execute function public.seller_tunnel_set_updated_at();

alter table public.sales enable row level security;

create policy "Owners can view their sales"
  on public.sales for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can edit the listing of their active sales"
  on public.sales for update
  to authenticated
  using (
    (select auth.uid()) = owner_id
    and stage in ('plan_chosen', 'mandate_signed', 'published')
  )
  with check ((select auth.uid()) = owner_id);

revoke all on table public.sales from anon, authenticated;
grant select on table public.sales to authenticated;
grant update (
  asking_price_eur, listing_title, listing_description, description_source,
  ai_retouch_wanted, home_staging_wanted, photos_imported_at
) on table public.sales to authenticated;

-- ---------------------------------------------------------------------------
-- mandates, mandate_signatures
-- ---------------------------------------------------------------------------

create table public.mandates (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  formula text not null check (formula in ('essentiel', 'premium', 'expert')),
  kind text not null
    check (kind in ('exclusif_sans_engagement', 'exclusif_3_mois')),
  terms_version text not null check (char_length(terms_version) <= 40),
  presentation_price_eur integer
    check (presentation_price_eur between 1000 and 100000000),
  fee_rate numeric(4, 2) not null check (fee_rate > 0 and fee_rate < 10),
  duration_months smallint check (duration_months between 1 and 24),
  status text not null default 'signed'
    check (status in ('signed', 'terminated')),
  is_test boolean not null default true,
  document_path text check (char_length(document_path) <= 500),
  document_sha256 text check (document_sha256 ~ '^[0-9a-f]{64}$'),
  signed_at timestamptz not null default now(),
  terminated_at timestamptz,
  created_at timestamptz not null default now()
);

create index mandates_sale_id_idx on public.mandates (sale_id);

create table public.mandate_signatures (
  id uuid primary key default gen_random_uuid(),
  mandate_id uuid not null references public.mandates (id) on delete cascade,
  signer_user_id uuid references auth.users (id) on delete set null,
  property_owner_id uuid references public.property_owners (id)
    on delete set null,
  signer_name text not null check (char_length(signer_name) between 1 and 200),
  method text not null check (method in ('drawn_test', 'offline')),
  signature_path text check (char_length(signature_path) <= 500),
  accepted_terms boolean not null,
  signed_at timestamptz not null default now(),
  user_agent text check (char_length(user_agent) <= 200),
  app_version text check (char_length(app_version) <= 40)
);

create index mandate_signatures_mandate_id_idx
  on public.mandate_signatures (mandate_id);

alter table public.mandates enable row level security;
alter table public.mandate_signatures enable row level security;

create policy "Owners can view the mandates of their sales"
  on public.mandates for select
  to authenticated
  using (exists (
    select 1 from public.sales s
    where s.id = sale_id and s.owner_id = (select auth.uid())
  ));

create policy "Owners can view the signatures of their mandates"
  on public.mandate_signatures for select
  to authenticated
  using (exists (
    select 1 from public.mandates m
    join public.sales s on s.id = m.sale_id
    where m.id = mandate_id and s.owner_id = (select auth.uid())
  ));

revoke all on table public.mandates, public.mandate_signatures
  from anon, authenticated;
grant select on table public.mandates, public.mandate_signatures
  to authenticated;

-- ---------------------------------------------------------------------------
-- sale_requests
-- ---------------------------------------------------------------------------

create table public.sale_requests (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  kind text not null check (kind in (
    'premium_setup', 'shooting_photo', 'shooting_photo_video', 'diagnostics'
  )),
  diagnostics text[] not null default '{}' check (diagnostics <@ array[
    'dpe', 'electricite', 'gaz', 'amiante', 'plomb', 'termites', 'erp'
  ]::text[]),
  preferred_slots timestamptz[] not null default '{}'
    check (coalesce(array_length(preferred_slots, 1), 0) <= 3),
  status text not null default 'requested'
    check (status in ('requested', 'scheduled', 'done', 'cancelled')),
  scheduled_at timestamptz,
  -- Indicative price shown to the seller (nothing is charged in the app).
  price_eur_ttc integer check (price_eur_ttc >= 0),
  staff_note text check (char_length(staff_note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index sale_requests_sale_id_idx on public.sale_requests (sale_id);

create trigger sale_requests_set_updated_at
  before update on public.sale_requests
  for each row execute function public.seller_tunnel_set_updated_at();

alter table public.sale_requests enable row level security;

create policy "Owners can view the requests of their sales"
  on public.sale_requests for select
  to authenticated
  using (exists (
    select 1 from public.sales s
    where s.id = sale_id and s.owner_id = (select auth.uid())
  ));

revoke all on table public.sale_requests from anon, authenticated;
grant select (
  id, sale_id, kind, diagnostics, preferred_slots, status, scheduled_at,
  price_eur_ttc, created_at, updated_at
) on table public.sale_requests to authenticated;

-- ---------------------------------------------------------------------------
-- listing_photos (the first one, by sort_order, is the cover)
-- ---------------------------------------------------------------------------

create table public.listing_photos (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  property_id uuid references public.properties (id) on delete set null,
  room_id uuid references public.rooms (id) on delete set null,
  source_room_photo_id uuid references public.room_photos (id)
    on delete set null,
  storage_path text not null unique check (char_length(storage_path) <= 500),
  width smallint check (width > 0),
  height smallint check (height > 0),
  size_bytes integer check (size_bytes between 1 and 20971520),
  sort_order smallint not null default 0 check (sort_order >= 0),
  caption text check (char_length(caption) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.listing_photos is
  'EPIC-08 · photos of a listing (bucket listing-media), copied from the '
  'dossier or taken for the listing; the first one is the cover.';

create index listing_photos_sale_idx
  on public.listing_photos (sale_id, sort_order);
create unique index listing_photos_one_copy_per_source
  on public.listing_photos (sale_id, source_room_photo_id)
  where source_room_photo_id is not null;

create trigger listing_photos_set_updated_at
  before update on public.listing_photos
  for each row execute function public.seller_tunnel_set_updated_at();

-- At most 40 photos per listing (serialized per sale).
create function public.listing_photos_check_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(
    hashtext('listing_photos_sale_' || new.sale_id::text)
  );
  if (
    select count(*) from public.listing_photos lp where lp.sale_id = new.sale_id
  ) >= 40 then
    raise exception 'listing_photo_limit_reached'
      using errcode = 'P0001', hint = 'At most 40 photos per listing.';
  end if;
  return new;
end;
$$;

revoke execute on function public.listing_photos_check_limit()
  from public, anon, authenticated;

create trigger listing_photos_check_limit
  before insert on public.listing_photos
  for each row execute function public.listing_photos_check_limit();

-- Whether the sale p_sale_id belongs to the caller and is active.
create function public.sale_is_open(p_sale_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sales s
    where s.id = p_sale_id
      and s.owner_id = (select auth.uid())
      and s.stage in ('plan_chosen', 'mandate_signed', 'published')
  );
$$;

revoke execute on function public.sale_is_open(uuid) from public, anon;
grant execute on function public.sale_is_open(uuid) to authenticated;

alter table public.listing_photos enable row level security;

create policy "Owners can view their listing photos"
  on public.listing_photos for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can add photos to their open listings"
  on public.listing_photos for insert
  to authenticated
  with check (
    (select auth.uid()) = owner_id
    and public.sale_is_open(sale_id)
    and storage_path like (select auth.uid())::text || '/'
      || sale_id::text || '/%'
    and (property_id is null or exists (
      select 1 from public.properties p
      where p.id = property_id and p.owner_id = (select auth.uid())
    ))
  );

create policy "Owners can update the photos of their open listings"
  on public.listing_photos for update
  to authenticated
  using ((select auth.uid()) = owner_id and public.sale_is_open(sale_id))
  with check ((select auth.uid()) = owner_id);

create policy "Owners can delete the photos of their open listings"
  on public.listing_photos for delete
  to authenticated
  using ((select auth.uid()) = owner_id and public.sale_is_open(sale_id));

revoke all on table public.listing_photos from anon, authenticated;
grant select, delete on table public.listing_photos to authenticated;
grant insert (
  id, sale_id, owner_id, property_id, room_id, source_room_photo_id,
  storage_path, width, height, size_bytes, sort_order, caption
) on table public.listing_photos to authenticated;
grant update (sort_order, caption) on table public.listing_photos
  to authenticated;

-- Puts the photos of the listing in the order p_photo_ids (the whole list:
-- the first one becomes the cover) and returns them.
create function public.reorder_listing_photos(
  p_sale_id uuid,
  p_photo_ids uuid[]
)
returns setof public.listing_photos
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.sale_is_open(p_sale_id) then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
  if (
    select count(*) from public.listing_photos lp where lp.sale_id = p_sale_id
  ) <> coalesce(array_length(p_photo_ids, 1), 0)
    or exists (
      select 1 from public.listing_photos lp
      where lp.sale_id = p_sale_id and lp.id <> all(p_photo_ids)
    ) then
    raise exception 'listing_photos_changed' using errcode = 'P0001';
  end if;
  update public.listing_photos lp
  set sort_order = o.position - 1
  from unnest(p_photo_ids) with ordinality as o(id, position)
  where lp.id = o.id and lp.sale_id = p_sale_id;
  return query
    select * from public.listing_photos lp
    where lp.sale_id = p_sale_id
    order by lp.sort_order, lp.created_at;
end;
$$;

revoke execute on function public.reorder_listing_photos(uuid, uuid[])
  from public, anon;
grant execute on function public.reorder_listing_photos(uuid, uuid[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- Storage buckets
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('listing-media', 'listing-media', false, 15728640,
    array['image/jpeg', 'image/png', 'image/heic']),
  ('mandate-signatures', 'mandate-signatures', false, 1048576,
    array['image/png']),
  ('sale-documents', 'sale-documents', false, 20971520,
    array['application/pdf'])
on conflict (id) do nothing;

create policy "Owners can read their listing media"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'listing-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Owners can add media to their open listings"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'listing-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.sales s
      where s.id::text = (storage.foldername(name))[2]
        and s.owner_id = (select auth.uid())
        and s.stage in ('plan_chosen', 'mandate_signed', 'published')
    )
  );

create policy "Owners can replace media of their open listings"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'listing-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.sales s
      where s.id::text = (storage.foldername(name))[2]
        and s.owner_id = (select auth.uid())
        and s.stage in ('plan_chosen', 'mandate_signed', 'published')
    )
  );

create policy "Owners can delete media of their open listings"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'listing-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.sales s
      where s.id::text = (storage.foldername(name))[2]
        and s.owner_id = (select auth.uid())
        and s.stage in ('plan_chosen', 'mandate_signed', 'published')
    )
  );

create policy "Owners can read their mandate signatures"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'mandate-signatures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- A signature is added once, before the mandate is signed (no update, no
-- delete).
create policy "Owners can add the signature of their mandate"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'mandate-signatures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.sales s
      where s.id::text = (storage.foldername(name))[2]
        and s.owner_id = (select auth.uid())
        and s.stage = 'plan_chosen'
    )
  );

-- Written by the Edge Function render-mandate only (service role).
create policy "Owners can read their sale documents"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'sale-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- Helpers (internal: not executable by app users)
-- ---------------------------------------------------------------------------

-- The main property of a lot: its main_property_id, else its first member.
create function public.sale_lot_main_property(p_lot_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select l.main_property_id from public.property_lots l where l.id = p_lot_id),
    (select p.id from public.properties p
      where p.lot_id = p_lot_id order by p.created_at, p.id limit 1)
  );
$$;

-- The property whose owners sign the mandate of a sale (the property, or
-- the main property of the lot).
create function public.sale_main_property(p_sale public.sales)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_sale.property_id, public.sale_lot_main_property(p_sale.lot_id));
$$;

-- Sum of the latest certified values of the certified properties of the
-- target (a property, or the members of a lot); null when none.
create function public.sale_certified_value(p_property_id uuid, p_lot_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select sum(v.value_eur)::integer
  from public.properties p
  cross join lateral (
    select va.value_eur from public.valuations va
    where va.property_id = p.id
    order by va.certified_at desc limit 1
  ) v
  where p.status = 'certified'
    and (p.id = p_property_id or (p_lot_id is not null and p.lot_id = p_lot_id));
$$;

-- Raises when the target cannot be put on sale by p_owner: the property is
-- certified, not in a lot sold only as a whole, and neither it nor its lot
-- is on sale; the lot's main property is certified and none of its members
-- is on sale on its own.
create function public.sales_check_target(
  p_owner uuid,
  p_property_id uuid,
  p_lot_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_property public.properties;
  v_lot public.property_lots;
  v_main uuid;
begin
  if num_nonnulls(p_property_id, p_lot_id) <> 1 then
    raise exception 'sale_target_invalid' using errcode = 'P0001';
  end if;
  if p_property_id is not null then
    select * into v_property from public.properties
    where id = p_property_id and owner_id = p_owner;
    if v_property.id is null then
      raise exception 'sale_target_not_found' using errcode = 'P0001';
    end if;
    if v_property.status <> 'certified' then
      raise exception 'property_not_certified' using errcode = 'P0001';
    end if;
    if v_property.lot_id is not null then
      select * into v_lot from public.property_lots where id = v_property.lot_id;
      if v_lot.sale_mode = 'ensemble' then
        raise exception 'lot_sold_together' using errcode = 'P0001';
      end if;
      if exists (
        select 1 from public.sales s
        where s.lot_id = v_property.lot_id and s.stage <> 'withdrawn'
      ) then
        raise exception 'lot_on_sale' using errcode = 'P0001';
      end if;
    end if;
  else
    select * into v_lot from public.property_lots
    where id = p_lot_id and owner_id = p_owner;
    if v_lot.id is null then
      raise exception 'sale_target_not_found' using errcode = 'P0001';
    end if;
    v_main := public.sale_lot_main_property(p_lot_id);
    if v_main is null or not exists (
      select 1 from public.properties p
      where p.id = v_main and p.status = 'certified'
    ) then
      raise exception 'main_property_not_certified' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.sales s
      join public.properties p on p.id = s.property_id
      where p.lot_id = p_lot_id and s.stage <> 'withdrawn'
    ) then
      raise exception 'member_on_sale' using errcode = 'P0001';
    end if;
  end if;
end;
$$;

-- In-app notification about the sale p_sale (route: the sale, or one of
-- its screens).
create function public.sale_notify(
  p_sale public.sales,
  p_kind text,
  p_title text,
  p_body text,
  p_screen text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, property_id, kind, title, body, route)
  values (
    p_sale.owner_id,
    public.sale_main_property(p_sale),
    p_kind,
    p_title,
    p_body,
    '/vendeur/ventes/' || p_sale.id::text
      || coalesce('/' || p_screen, '')
  );
$$;

revoke execute on function public.sale_lot_main_property(uuid)
  from public, anon, authenticated;
revoke execute on function public.sale_main_property(public.sales)
  from public, anon, authenticated;
revoke execute on function public.sale_certified_value(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.sales_check_target(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.sale_notify(public.sales, text, text, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPCs of the app (security definer: they write the state columns)
-- ---------------------------------------------------------------------------

-- Version of the test mandate terms (supabase/functions/_shared/mandate).
create function public.sale_terms_version()
returns text
language sql
immutable
set search_path = ''
as $$ select 'test-2026-10'::text; $$;

grant execute on function public.sale_terms_version() to authenticated;

-- Creates the sale p_sale_id of the target (a property or a lot) with
-- p_formula, or changes the formula of its active sale while the mandate
-- is not signed. Retry-safe (same id). Returns the id of the sale.
create function public.choose_formula(
  p_sale_id uuid,
  p_property_id uuid,
  p_lot_id uuid,
  p_formula text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_sale public.sales;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_formula is null or p_formula not in ('essentiel', 'premium', 'expert') then
    raise exception 'formula_invalid' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('sales_owner_' || v_uid::text));

  select * into v_sale from public.sales s
  where s.owner_id = v_uid and (
    s.id = p_sale_id
    or (s.stage <> 'withdrawn' and (
      s.property_id = p_property_id or s.lot_id = p_lot_id
    ))
  )
  order by (s.id = p_sale_id) desc
  limit 1;

  if v_sale.id is not null then
    if v_sale.stage = 'withdrawn' then
      raise exception 'sale_withdrawn' using errcode = 'P0001';
    end if;
    if v_sale.formula <> p_formula then
      if v_sale.stage <> 'plan_chosen' then
        raise exception 'mandate_already_signed' using errcode = 'P0001';
      end if;
      update public.sales
      set formula = p_formula, formula_chosen_at = now()
      where id = v_sale.id;
    end if;
    return v_sale.id;
  end if;

  perform public.sales_check_target(v_uid, p_property_id, p_lot_id);
  insert into public.sales (id, owner_id, property_id, lot_id, formula, asking_price_eur)
  values (
    p_sale_id, v_uid, p_property_id, p_lot_id, p_formula,
    public.sale_certified_value(p_property_id, p_lot_id)
  );
  return p_sale_id;
end;
$$;

-- Signs the TEST mandate p_mandate_id of the sale p_sale_id with the drawn
-- signature stored at p_signature_path (bucket mandate-signatures).
-- Requires the identity document of the main property, and for L'Expert
-- the identity verified by the team. Retry-safe. Returns the mandate id
-- (the app then asks render-mandate for the PDF).
create function public.sign_test_mandate(
  p_sale_id uuid,
  p_mandate_id uuid,
  p_terms_version text,
  p_signature_path text,
  p_accepted boolean,
  p_user_agent text default null,
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_sale public.sales;
  v_main uuid;
  v_owner public.property_owners;
  v_name text;
begin
  select * into v_sale from public.sales
  where id = p_sale_id and owner_id = v_uid
  for update;
  if v_sale.id is null then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.mandates m
    where m.id = p_mandate_id and m.sale_id = p_sale_id
  ) then
    return p_mandate_id;
  end if;
  if v_sale.stage <> 'plan_chosen' then
    raise exception 'sale_stage_invalid' using errcode = 'P0001';
  end if;
  if p_accepted is not true then
    raise exception 'terms_not_accepted' using errcode = 'P0001';
  end if;
  if p_terms_version is distinct from public.sale_terms_version() then
    raise exception 'terms_version_invalid' using errcode = 'P0001';
  end if;
  if p_signature_path is null
    or p_signature_path not like v_uid::text || '/' || p_sale_id::text || '/%'
    or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'mandate-signatures' and o.name = p_signature_path
    ) then
    raise exception 'signature_missing' using errcode = 'P0001';
  end if;

  v_main := public.sale_main_property(v_sale);
  if not exists (
    select 1 from public.property_documents d
    where d.property_id = v_main and d.kind = 'piece_identite'
  ) then
    raise exception 'identity_document_missing' using errcode = 'P0001';
  end if;

  -- The signer: the owner linked to the account, else the first owner.
  select * into v_owner from public.property_owners po
  where po.property_id = v_main
  order by (po.profile_id = v_uid) desc nulls last, po.position
  limit 1;
  if v_sale.formula = 'expert' and v_owner.identity_verified_at is null then
    raise exception 'identity_not_verified' using errcode = 'P0001';
  end if;
  v_name := coalesce(
    nullif(trim(concat_ws(' ', v_owner.first_name, v_owner.last_name)), ''),
    (select nullif(trim(pr.first_name), '')
      from public.profiles pr where pr.id = v_uid),
    'Vendeur'
  );

  insert into public.mandates (
    id, sale_id, formula, kind, terms_version, presentation_price_eur,
    fee_rate, duration_months, status, is_test
  ) values (
    p_mandate_id, p_sale_id, v_sale.formula,
    case v_sale.formula when 'expert' then 'exclusif_3_mois'
      else 'exclusif_sans_engagement' end,
    p_terms_version, v_sale.asking_price_eur,
    case v_sale.formula when 'expert' then 3.00 else 1.00 end,
    case v_sale.formula when 'expert' then 3 end,
    'signed', true
  );
  insert into public.mandate_signatures (
    mandate_id, signer_user_id, property_owner_id, signer_name, method,
    signature_path, accepted_terms, user_agent, app_version
  ) values (
    p_mandate_id, v_uid, v_owner.id, v_name, 'drawn_test', p_signature_path,
    true, left(p_user_agent, 200), left(p_app_version, 40)
  );
  update public.sales
  set stage = 'mandate_signed', mandate_signed_at = now()
  where id = p_sale_id
  returning * into v_sale;

  perform public.sale_notify(
    v_sale, 'mandate_signed', 'Mandat de test signé',
    'Votre mandat (signature de test, sans valeur juridique) est enregistré.'
  );
  return p_mandate_id;
end;
$$;

-- Asks a service of the sale (no payment): Premium setup callback, photo
-- shoot, diagnostics. Retry-safe (same id); one open request per kind.
create function public.request_sale_service(
  p_request_id uuid,
  p_sale_id uuid,
  p_kind text,
  p_diagnostics text[] default '{}',
  p_preferred_slots timestamptz[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_sale public.sales;
begin
  select * into v_sale from public.sales
  where id = p_sale_id and owner_id = v_uid
    and stage in ('plan_chosen', 'mandate_signed', 'published')
  for update;
  if v_sale.id is null then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.sale_requests r
    where r.id = p_request_id and r.sale_id = p_sale_id
  ) then
    return p_request_id;
  end if;
  if p_kind = 'diagnostics' and coalesce(array_length(p_diagnostics, 1), 0) = 0 then
    raise exception 'diagnostics_missing' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.sale_requests r
    where r.sale_id = p_sale_id and r.kind = p_kind
      and r.status in ('requested', 'scheduled')
  ) then
    raise exception 'request_already_open' using errcode = 'P0001';
  end if;
  insert into public.sale_requests (
    id, sale_id, kind, diagnostics, preferred_slots, price_eur_ttc
  ) values (
    p_request_id, p_sale_id, p_kind,
    case when p_kind = 'diagnostics' then coalesce(p_diagnostics, '{}') else '{}' end,
    coalesce(p_preferred_slots, '{}'),
    case p_kind
      when 'shooting_photo' then 200
      when 'shooting_photo_video' then 350
      when 'diagnostics' then 250
      when 'premium_setup' then 299
    end
  );
  return p_request_id;
end;
$$;

-- Cancels the open request p_request_id of the caller.
create function public.cancel_sale_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.sale_requests r
  set status = 'cancelled'
  from public.sales s
  where r.id = p_request_id and s.id = r.sale_id
    and s.owner_id = (select auth.uid())
    and r.status in ('requested', 'cancelled');
  if not found then
    raise exception 'request_not_cancellable' using errcode = 'P0001';
  end if;
end;
$$;

-- Publishes the listing of the sale (L'Essentiel / Le Premium, mandate
-- signed). Raises publish_incomplete with the missing items in the detail
-- (missing_price, missing_title, missing_description, missing_photos).
create function public.publish_listing(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
  v_missing text[] := '{}';
begin
  select * into v_sale from public.sales
  where id = p_sale_id and owner_id = (select auth.uid())
  for update;
  if v_sale.id is null then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
  if v_sale.stage = 'published' then
    return;
  end if;
  if v_sale.formula = 'expert' then
    raise exception 'formula_not_self_published' using errcode = 'P0001';
  end if;
  if v_sale.stage <> 'mandate_signed' then
    raise exception 'mandate_not_signed' using errcode = 'P0001';
  end if;
  if v_sale.asking_price_eur is null then
    v_missing := array_append(v_missing, 'missing_price');
  end if;
  if coalesce(trim(v_sale.listing_title), '') = '' then
    v_missing := array_append(v_missing, 'missing_title');
  end if;
  if coalesce(trim(v_sale.listing_description), '') = '' then
    v_missing := array_append(v_missing, 'missing_description');
  end if;
  if (
    select count(*) from public.listing_photos lp where lp.sale_id = p_sale_id
  ) < 5 then
    v_missing := array_append(v_missing, 'missing_photos');
  end if;
  if cardinality(v_missing) > 0 then
    raise exception 'publish_incomplete'
      using errcode = 'P0001', detail = array_to_string(v_missing, ',');
  end if;
  update public.sales
  set stage = 'published', published_at = now()
  where id = p_sale_id
  returning * into v_sale;
  perform public.sale_notify(
    v_sale, 'listing_published', 'Votre annonce est en ligne',
    'Elle est visible dans Realesty.', 'annonce'
  );
end;
$$;

-- Takes the listing offline (it can be edited and published again).
create function public.unpublish_listing(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.sales
  set stage = 'mandate_signed'
  where id = p_sale_id and owner_id = (select auth.uid())
    and stage in ('published', 'mandate_signed')
    and formula <> 'expert';
  if not found then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
end;
$$;

-- Withdraws the sale: listing offline, test mandate terminated, open
-- requests cancelled. Retry-safe.
create function public.withdraw_sale(p_sale_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  select * into v_sale from public.sales
  where id = p_sale_id and owner_id = (select auth.uid())
  for update;
  if v_sale.id is null then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
  if v_sale.stage = 'withdrawn' then
    return;
  end if;
  update public.sales
  set stage = 'withdrawn', withdrawn_at = now(),
    withdraw_reason = left(nullif(trim(p_reason), ''), 300)
  where id = p_sale_id
  returning * into v_sale;
  update public.mandates
  set status = 'terminated', terminated_at = now()
  where sale_id = p_sale_id and status = 'signed';
  update public.sale_requests
  set status = 'cancelled'
  where sale_id = p_sale_id and status in ('requested', 'scheduled');
  perform public.sale_notify(
    v_sale, 'sale_withdrawn', 'Vente retirée',
    'Votre annonce est retirée et le mandat de test résilié.'
  );
end;
$$;

-- EPIC-11 (account deletion): whether p_owner has a sale with a signed
-- mandate or a published listing. Only answers about the caller (staff /
-- service role: about anyone).
create function public.has_active_sale(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.sales s
    where s.owner_id = p_owner
      and s.stage in ('mandate_signed', 'published')
      and ((select auth.uid()) is null or p_owner = (select auth.uid()))
  );
$$;

do $$
declare
  v_function text;
begin
  foreach v_function in array array[
    'public.choose_formula(uuid, uuid, uuid, text)',
    'public.sign_test_mandate(uuid, uuid, text, text, boolean, text, text)',
    'public.request_sale_service(uuid, uuid, text, text[], timestamptz[])',
    'public.cancel_sale_request(uuid)',
    'public.publish_listing(uuid)',
    'public.unpublish_listing(uuid)',
    'public.withdraw_sale(uuid, text)',
    'public.has_active_sale(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', v_function);
    execute format('grant execute on function %s to authenticated, service_role',
      v_function);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Team functions (SQL editor; wrapped by the back office of EPIC-12)
-- ---------------------------------------------------------------------------

-- The active sale of a property (on its own or through its lot), if any.
create function public.staff_active_sale_of(p_property_id uuid)
returns public.sales
language sql
stable
set search_path = ''
as $$
  select s.* from public.sales s
  left join public.properties p on p.id = p_property_id
  where s.stage <> 'withdrawn'
    and (s.property_id = p_property_id or (p.lot_id is not null and s.lot_id = p.lot_id))
  order by s.created_at desc
  limit 1;
$$;

-- Records that the team checked the identity of the owner p_property_owner_id.
create function public.staff_verify_identity(
  p_property_owner_id uuid,
  p_staff_user_id uuid default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_owner public.property_owners;
  v_user uuid;
  v_sale public.sales;
begin
  update public.property_owners
  set identity_verified_at = now(), identity_verified_by = p_staff_user_id
  where id = p_property_owner_id
  returning * into v_owner;
  if v_owner.id is null then
    raise exception 'Owner % not found', p_property_owner_id using errcode = 'P0002';
  end if;
  select owner_id into v_user from public.properties where id = v_owner.property_id;
  v_sale := public.staff_active_sale_of(v_owner.property_id);
  insert into public.notifications (user_id, property_id, kind, title, body, route)
  values (
    v_user, v_owner.property_id, 'identity_verified',
    'Identité vérifiée',
    v_owner.first_name || ' ' || v_owner.last_name
      || ' : pièce d’identité vérifiée par notre équipe.',
    case when v_sale.id is null
      then '/vendeur/biens/' || v_owner.property_id::text
      else '/vendeur/ventes/' || v_sale.id::text end
  );
end;
$$;

-- Plans, closes or cancels a request (p_status: scheduled, done, cancelled).
create function public.staff_update_sale_request(
  p_request_id uuid,
  p_status text,
  p_scheduled_at timestamptz default null,
  p_note text default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_request public.sale_requests;
  v_sale public.sales;
begin
  update public.sale_requests
  set status = p_status,
    scheduled_at = coalesce(p_scheduled_at, scheduled_at),
    staff_note = coalesce(p_note, staff_note)
  where id = p_request_id
  returning * into v_request;
  if v_request.id is null then
    raise exception 'Request % not found', p_request_id using errcode = 'P0002';
  end if;
  select * into v_sale from public.sales where id = v_request.sale_id;
  perform public.sale_notify(
    v_sale, 'sale_request_updated',
    case p_status
      when 'scheduled' then 'Rendez-vous confirmé'
      when 'done' then 'Demande traitée'
      else 'Demande annulée' end,
    case when p_status = 'scheduled' and v_request.scheduled_at is not null
      then 'Le ' || to_char(v_request.scheduled_at at time zone 'Europe/Paris',
        'DD/MM/YYYY à HH24"h"MI') || '.'
      else null end
  );
end;
$$;

-- Records the signature of a co-owner made outside the app.
create function public.staff_record_offline_signature(
  p_mandate_id uuid,
  p_property_owner_id uuid,
  p_signer_name text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.mandate_signatures (
    mandate_id, property_owner_id, signer_name, method, accepted_terms
  ) values (p_mandate_id, p_property_owner_id, p_signer_name, 'offline', true)
  returning id into v_id;
  return v_id;
end;
$$;

-- Publishes the listing of an Expert sale (prepared by the agent).
create function public.staff_publish_expert_sale(p_sale_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  update public.sales
  set stage = 'published', published_at = now()
  where id = p_sale_id and formula = 'expert' and stage = 'mandate_signed'
  returning * into v_sale;
  if v_sale.id is null then
    raise exception 'Expert sale % not found or not signed', p_sale_id
      using errcode = 'P0002';
  end if;
  perform public.sale_notify(
    v_sale, 'listing_published', 'Votre annonce est en ligne',
    'Votre agent a publié l’annonce dans Realesty.'
  );
end;
$$;

revoke execute on function public.staff_active_sale_of(uuid)
  from public, anon, authenticated;
revoke execute on function public.staff_verify_identity(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.staff_update_sale_request(uuid, text, timestamptz, text)
  from public, anon, authenticated;
revoke execute on function public.staff_record_offline_signature(uuid, uuid, text)
  from public, anon, authenticated;
revoke execute on function public.staff_publish_expert_sale(uuid)
  from public, anon, authenticated;
