-- EPIC-05 · Non-certified price estimate ("Tendance IA", V8 / V8b).
--
-- Purely additive. The Edge Function `estimate-property` computes the
-- estimate once, when the dossier is sent, from the DVF sales of the sector
-- (docs/plans/2026-10-01-estimation-non-certifiee.md):
-- - dvf_sources / dvf_sales: server-side cache of the geo-dvf files (DGFiP
--   DVF, Etalab processing, Licence Ouverte 2.0), cleaned. Service role
--   only: RLS enabled, no policy, no grant to anon / authenticated.
-- - market_snapshots: the result per property, readable by its owner only,
--   written by the service role only. One final result (ok / insufficient)
--   per property, never recomputed; failed attempts are kept for diagnosis.
-- - properties.ai_estimate_confidence: confidence index of the estimate,
--   written by the service role only (no update grant).

-- ---------------------------------------------------------------------------
-- DVF cache.
-- ---------------------------------------------------------------------------

create table public.dvf_sources (
  insee text not null check (char_length(insee) = 5),
  year smallint not null check (year between 2000 and 2100),
  etag text check (char_length(etag) <= 200),
  last_modified text check (char_length(last_modified) <= 100),
  fetched_at timestamptz not null default now(),
  -- false when the file does not exist (no sale, Alsace-Moselle, Mayotte).
  available boolean not null default true,
  rows_kept integer not null default 0,
  -- Dropped mutations per reason (multi_lots, dependencies, extreme…).
  rows_dropped jsonb not null default '{}'
    check (jsonb_typeof(rows_dropped) = 'object'),
  primary key (insee, year)
);

comment on table public.dvf_sources is
  'geo-dvf commune files loaded into dvf_sales (one row per commune × year).';

create table public.dvf_sales (
  id_mutation text not null check (char_length(id_mutation) <= 40),
  insee text not null check (char_length(insee) = 5),
  year smallint not null,
  sold_on date not null,
  property_type text not null
    check (property_type in ('maison', 'appartement')),
  price_eur integer not null check (price_eur > 0),
  built_area_m2 numeric(7, 2) not null check (built_area_m2 > 0),
  rooms smallint,
  land_m2 integer,
  -- adresse_nom_voie: the street name only, never the house number.
  street text check (char_length(street) <= 200),
  lat double precision,
  lng double precision,
  primary key (id_mutation, insee)
);

comment on table public.dvf_sales is
  'Cleaned DVF sales (one dwelling per mutation), cache of dvf_sources.';

create index dvf_sales_lookup_idx
  on public.dvf_sales (insee, property_type, sold_on);
create index dvf_sales_source_idx on public.dvf_sales (insee, year);

alter table public.dvf_sources enable row level security;
alter table public.dvf_sales enable row level security;
revoke all on table public.dvf_sources from anon, authenticated;
revoke all on table public.dvf_sales from anon, authenticated;

-- ---------------------------------------------------------------------------
-- market_snapshots: the estimate of a property.
-- ---------------------------------------------------------------------------

create table public.market_snapshots (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  status text not null
    check (status in ('running', 'ok', 'insufficient', 'error')),
  -- Why there is no estimate (status insufficient): too_few_sales,
  -- unsupported_type, missing_area, missing_location, no_dvf_coverage.
  reason text check (char_length(reason) <= 40),
  computed_at timestamptz not null default now(),
  method_version text not null check (char_length(method_version) <= 40),
  source_version text check (char_length(source_version) <= 200),
  data_until date,
  property_type text check (property_type in ('maison', 'appartement')),
  living_area_m2 numeric(7, 2),
  city text check (char_length(city) <= 100),
  estimate_low_eur integer,
  estimate_median_eur integer,
  estimate_high_eur integer,
  price_m2_low integer,
  price_m2_median integer,
  price_m2_high integer,
  confidence smallint check (confidence between 0 and 100),
  comparables_count smallint,
  scope text check (scope in ('radius', 'commune')),
  radius_m integer,
  months smallint,
  sales_12m integer,
  yoy_change_pct numeric(5, 2),
  semester_medians jsonb,
  comparables jsonb,
  factors jsonb,
  explanation_fr text check (char_length(explanation_fr) <= 1000),
  explanation_source text check (explanation_source in ('ai', 'template')),
  error text check (char_length(error) <= 500),
  created_at timestamptz not null default now()
);

comment on table public.market_snapshots is
  'Non-certified estimate of a property (EPIC-05), computed once at sending.';

-- One final result per property (never recomputed) and one attempt at a
-- time; failed attempts (error) are kept.
create unique index market_snapshots_one_result
  on public.market_snapshots (property_id)
  where status in ('ok', 'insufficient');
create unique index market_snapshots_one_running
  on public.market_snapshots (property_id)
  where status = 'running';
create index market_snapshots_property_idx
  on public.market_snapshots (property_id, created_at desc);

alter table public.market_snapshots enable row level security;

create policy "Owners can view the market snapshots of their properties"
  on public.market_snapshots for select
  to authenticated
  using (
    exists (
      select 1 from public.properties p
      where p.id = property_id and p.owner_id = (select auth.uid())
    )
  );

revoke all on table public.market_snapshots from anon, authenticated;
grant select on table public.market_snapshots to authenticated;

-- ---------------------------------------------------------------------------
-- properties: confidence of the estimate (service role only, like the other
-- ai_estimate_* columns: no update grant to authenticated).
-- ---------------------------------------------------------------------------

alter table public.properties
  add column ai_estimate_confidence smallint
    check (ai_estimate_confidence between 0 and 100);
