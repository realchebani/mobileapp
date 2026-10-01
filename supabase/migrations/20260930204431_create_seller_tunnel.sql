-- Seller tunnel (V1 → V8): the property dossier of a seller and its child
-- collections, plus the private Storage bucket of its documents.
--
-- Purely additive. Every row belongs to the owner of its property: row level
-- security only lets that user read and write it. Enumerations are `text` +
-- `check`, like `profiles.role`. See docs/plans/2026-09-30-tunnel-vendeur-spec.md
-- section 4 for where each column is written.

-- Keeps updated_at current (shared by the triggers of this migration).
create function public.seller_tunnel_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- properties: one seller dossier.
-- ---------------------------------------------------------------------------

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  status text not null default 'draft'
    check (status in ('draft', 'submitted', 'in_review', 'certified')),
  current_step smallint not null default 1
    check (current_step between 1 and 8),

  -- V1 · Propriétaires
  ownership_type text check (ownership_type in ('single', 'multiple')),

  -- V2 · Adresse & cadastre
  address_label text check (char_length(address_label) <= 300),
  address_housenumber text check (char_length(address_housenumber) <= 20),
  address_street text check (char_length(address_street) <= 200),
  address_postcode text check (char_length(address_postcode) <= 10),
  address_city text check (char_length(address_city) <= 100),
  address_citycode text check (char_length(address_citycode) <= 10),
  address_ban_id text check (char_length(address_ban_id) <= 100),
  lat double precision check (lat between -90 and 90),
  lng double precision check (lng between -180 and 180),
  parcel_confirmed boolean not null default false,
  special_situations text[] not null default '{}'
    check (special_situations <@ array[
      'servitude_passage', 'servitude_reseaux', 'autre', 'aucune'
    ]::text[]),
  special_situation_other text
    check (char_length(special_situation_other) <= 300),

  -- V3 · Contexte
  property_type text
    check (property_type in ('maison', 'appartement', 'terrain', 'autre')),
  property_type_other text check (char_length(property_type_other) <= 100),
  purchase_year smallint check (purchase_year between 1800 and 2100),
  purchase_price_eur integer
    check (purchase_price_eur between 1 and 1000000000),
  self_built boolean,
  sale_reason text check (sale_reason in (
    'mutation', 'agrandissement', 'separation', 'investissement', 'autre'
  )),
  previously_estimated boolean,

  -- V4b · Audit technique
  construction_year smallint check (construction_year between 1000 and 2100),
  orientation text check (char_length(orientation) <= 30),
  living_area_m2 numeric(7, 2) check (living_area_m2 > 0),
  living_room_area_m2 numeric(6, 2) check (living_room_area_m2 > 0),
  rooms_count smallint check (rooms_count between 0 and 100),
  bedrooms_count smallint check (bedrooms_count between 0 and 100),
  levels text check (levels in ('plain_pied', 'r1', 'r2_plus')),
  wall_material text check (wall_material in (
    'parpaing', 'brique', 'pierre', 'beton', 'moellon', 'bois', 'pise'
  )),
  adjacency text check (adjacency in ('independant', '1', '2', '3')),
  roof_type text check (char_length(roof_type) <= 30),
  roof_year smallint check (roof_year between 1000 and 2100),
  heating_energy text
    check (heating_energy in ('electricite', 'gaz', 'fioul', 'pac', 'bois')),
  heat_pump_type text check (char_length(heat_pump_type) <= 30),
  heat_pump_year smallint check (heat_pump_year between 1900 and 2100),
  sanitation text check (sanitation in (
    'tout_a_l_egout', 'fosse_septique', 'puits_perdu'
  )),
  outdoor_equipment text[] not null default '{}'
    check (outdoor_equipment <@ array[
      'piscine', 'garage', 'terrasse', 'abri_jardin', 'portail_motorise'
    ]::text[]),
  pool_type text check (char_length(pool_type) <= 30),
  pool_length_m numeric(5, 2) check (pool_length_m > 0),
  pool_width_m numeric(5, 2) check (pool_width_m > 0),

  -- V5 · Pièces
  measurement_method text
    check (measurement_method in ('scan', 'plan', 'manual')),

  -- V6 · Cadre de vie
  noise_level smallint check (noise_level between 1 and 10),
  overlooking text check (overlooking in ('aucun', 'leger', 'important')),
  secret_note text check (char_length(secret_note) <= 500),

  -- Provenance of each answer: column name → 'declared' | 'document' |
  -- 'external' | 'expert' | 'ai' (optionally with a source document id).
  provenance jsonb not null default '{}'
    check (jsonb_typeof(provenance) = 'object'),

  -- V7 · Documents & envoi
  transparency_score smallint check (transparency_score between 0 and 100),
  submitted_at timestamptz,

  -- V8 · Attente expert
  notify_push boolean not null default true,

  -- Written by the backend only (no update grant).
  ai_estimate_low_eur integer,
  ai_estimate_median_eur integer,
  ai_estimate_high_eur integer,
  ai_estimate_computed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.properties is
  'Seller dossier built by the seller tunnel (V1–V8), one row per property.';
comment on column public.properties.current_step is
  'Resume point of the tunnel: 1–7 = steps V1–V7, 8 = submitted (V8).';
comment on column public.properties.provenance is
  'Map column name → declared | document | external | expert | ai.';

create index properties_owner_id_idx
  on public.properties (owner_id, status, updated_at desc);

create trigger properties_set_updated_at
  before update on public.properties
  for each row execute function public.seller_tunnel_set_updated_at();

alter table public.properties enable row level security;

create policy "Owners can view their properties"
  on public.properties for select
  to authenticated
  using ((select auth.uid()) = owner_id);

-- New dossiers start as drafts of the signed-in user.
create policy "Owners can create draft properties"
  on public.properties for insert
  to authenticated
  with check ((select auth.uid()) = owner_id and status = 'draft');

-- The owner may edit a dossier and submit it, but not move it further
-- (in_review / certified are set by the backend, which also locks edits).
create policy "Owners can update their properties"
  on public.properties for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check (
    (select auth.uid()) = owner_id and status in ('draft', 'submitted')
  );

create policy "Owners can delete their properties"
  on public.properties for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

revoke all on table public.properties from anon, authenticated;
grant select, delete on table public.properties to authenticated;
grant insert (owner_id, current_step) on table public.properties
  to authenticated;
grant update (
  status, current_step, ownership_type,
  address_label, address_housenumber, address_street, address_postcode,
  address_city, address_citycode, address_ban_id, lat, lng,
  parcel_confirmed, special_situations, special_situation_other,
  property_type, property_type_other, purchase_year, purchase_price_eur,
  self_built, sale_reason, previously_estimated,
  construction_year, orientation, living_area_m2, living_room_area_m2,
  rooms_count, bedrooms_count, levels, wall_material, adjacency, roof_type,
  roof_year, heating_energy, heat_pump_type, heat_pump_year, sanitation,
  outdoor_equipment, pool_type, pool_length_m, pool_width_m,
  measurement_method, noise_level, overlooking, secret_note, provenance,
  transparency_score, submitted_at, notify_push
) on table public.properties to authenticated;

-- ---------------------------------------------------------------------------
-- Child collections. RLS: the parent property belongs to the user.
-- ---------------------------------------------------------------------------

-- V1 · owners of the property (position 1 = the user).
create table public.property_owners (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  position smallint not null check (position between 1 and 20),
  profile_id uuid references public.profiles (id) on delete set null,
  first_name text not null
    check (char_length(first_name) between 1 and 100),
  last_name text not null check (char_length(last_name) between 1 and 100),
  phone text check (char_length(phone) <= 20),
  email text check (char_length(email) <= 320),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, position)
);

create index property_owners_profile_id_idx
  on public.property_owners (profile_id);

-- V2 · cadastral parcels (several when "Modifier / ajouter").
create table public.property_parcels (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  idu text not null check (char_length(idu) <= 20),
  code_insee text check (char_length(code_insee) <= 10),
  section text check (char_length(section) <= 5),
  numero text check (char_length(numero) <= 10),
  area_m2 integer check (area_m2 >= 0),
  geometry jsonb,
  source text not null default 'apicarto' check (char_length(source) <= 30),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, idu)
);

-- V3 · estimates by agencies.
create table public.previous_estimates (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  price_eur integer not null check (price_eur between 1 and 1000000000),
  estimated_month date
    check (estimated_month = date_trunc('month', estimated_month)::date),
  agency_name text check (char_length(agency_name) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index previous_estimates_property_id_idx
  on public.previous_estimates (property_id);

-- V5c · rooms and surfaces.
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  level text
    check (level in ('sous_sol', 'rdc', 'etage_1', 'etage_2', 'combles')),
  sort_order smallint not null default 0,
  area_m2 numeric(6, 2) not null check (area_m2 > 0),
  ceiling_height_m numeric(4, 2) check (ceiling_height_m > 0),
  floor_covering text check (char_length(floor_covering) <= 30),
  glazing text check (glazing in ('simple', 'double', 'triple')),
  is_main boolean not null default false,
  source text not null default 'manual'
    check (source in ('scan', 'plan', 'manual')),
  photos_count smallint not null default 0 check (photos_count >= 0),
  scan_data jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index rooms_property_id_idx on public.rooms (property_id);

-- V6 · assets and watch points of the neighbourhood.
create table public.lifestyle_items (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  kind text not null check (kind in ('asset', 'watch_point')),
  label text not null check (char_length(label) between 1 and 140),
  sort_order smallint not null default 0,
  source text not null default 'declared'
    check (source in ('declared', 'voice')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index lifestyle_items_property_id_idx
  on public.lifestyle_items (property_id);

-- V7 · documents; files live in the property-documents bucket under
-- <owner id>/<property id>/…
create table public.property_documents (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  kind text not null check (kind in (
    'titre_propriete', 'taxe_fonciere', 'facture_energie', 'facture_travaux',
    'piece_identite', 'diagnostics', 'rapport_spanc', 'plan', 'autre'
  )),
  storage_path text not null unique
    check (char_length(storage_path) <= 500),
  file_name text check (char_length(file_name) <= 255),
  mime_type text check (char_length(mime_type) <= 100),
  size_bytes integer check (size_bytes >= 0),
  status text not null default 'received'
    check (status in ('received', 'analyzing', 'analyzed', 'rejected')),
  extracted jsonb,
  uploaded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index property_documents_property_id_idx
  on public.property_documents (property_id);

-- Triggers, RLS and grants shared by the child tables.
do $$
declare
  child text;
begin
  foreach child in array array[
    'property_owners', 'property_parcels', 'previous_estimates', 'rooms',
    'lifestyle_items', 'property_documents'
  ] loop
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.seller_tunnel_set_updated_at()',
      child || '_set_updated_at', child
    );

    execute format('alter table public.%I enable row level security', child);

    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (exists (select 1 from public.properties p '
      'where p.id = property_id and p.owner_id = (select auth.uid())))',
      'Owners can view the ' || child || ' of their properties', child
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (exists (select 1 from public.properties p '
      'where p.id = property_id and p.owner_id = (select auth.uid())))',
      'Owners can add ' || child || ' to their properties', child
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (exists (select 1 from public.properties p '
      'where p.id = property_id and p.owner_id = (select auth.uid()))) '
      'with check (exists (select 1 from public.properties p '
      'where p.id = property_id and p.owner_id = (select auth.uid())))',
      'Owners can update the ' || child || ' of their properties', child
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (exists (select 1 from public.properties p '
      'where p.id = property_id and p.owner_id = (select auth.uid())))',
      'Owners can delete the ' || child || ' of their properties', child
    );

    execute format('revoke all on table public.%I from anon, authenticated',
      child);
  end loop;
end;
$$;

grant select, insert, update, delete on table
  public.property_owners, public.property_parcels, public.previous_estimates,
  public.rooms, public.lifestyle_items
  to authenticated;

-- Documents: the analysis columns (status, extracted) are backend-only.
grant select, delete on table public.property_documents to authenticated;
grant insert (
  id, property_id, kind, storage_path, file_name, mime_type, size_bytes
) on table public.property_documents to authenticated;
grant update (kind, file_name) on table public.property_documents
  to authenticated;

-- A document row must point into the user's own Storage folder.
create policy "Documents are stored in the owner folder"
  on public.property_documents as restrictive for insert
  to authenticated
  with check (
    storage_path like (select auth.uid())::text || '/%'
  );

-- ---------------------------------------------------------------------------
-- Storage: private bucket, one folder per user (<auth.uid()>/…).
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'property-documents',
  'property-documents',
  false,
  20971520, -- 20 MB
  array[
    'application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/heif'
  ]
);

create policy "Owners can read their property documents"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'property-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Owners can upload their property documents"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'property-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Owners can update their property documents"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'property-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'property-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Owners can delete their property documents"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'property-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
