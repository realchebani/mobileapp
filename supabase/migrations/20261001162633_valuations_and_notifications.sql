-- EPIC-07 · Seller space: certified valuations (V9, V9b), in-app
-- notifications and the staff functions used to review and certify a
-- dossier until the expert back-office (EPIC-12) exists.
--
-- - valuations: the expert's structured report, one row per certification
--   (the app reads the latest). Read-only for the owner; written by staff
--   only (no insert / update grant).
-- - notifications: in-app notifications of a user (no push, no e-mail in
--   v1). The user reads them and marks them read (read_at only).
-- - valuation-reports: private Storage bucket of the optional PDF report,
--   under <owner id>/<property id>/…; read-only for the owner.
-- - staff_start_review / staff_certify_property /
--   staff_attach_valuation_report: run by staff from the SQL editor (role
--   postgres) or with the service role; not executable by app users. See
--   docs/runbooks/certifier-un-dossier.md.

-- ---------------------------------------------------------------------------
-- valuations
-- ---------------------------------------------------------------------------

create table public.valuations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null
    references public.properties (id) on delete cascade,

  -- Hero (V9, V9b).
  value_eur integer not null check (value_eur between 1000 and 100000000),
  low_eur integer not null check (low_eur between 1000 and 100000000),
  high_eur integer not null check (high_eur between 1000 and 100000000),
  price_m2_eur integer check (price_m2_eur > 0),
  -- "Tendance IA initiale": the AI estimate the expert started from.
  ai_trend_eur integer check (ai_trend_eur > 0),

  -- Synthèse tab.
  estimated_delay_weeks smallint check (estimated_delay_weeks between 1 and 104),
  -- [{label, detail, amount_eur, is_delta}] "Comment nous arrivons à ce chiffre"
  method_steps jsonb not null default '[]'
    check (jsonb_typeof(method_steps) = 'array'),
  -- [{positive, text}] "Pourquoi cette valeur"
  reasons jsonb not null default '[]'
    check (jsonb_typeof(reasons) = 'array'),
  -- [{price_eur, label}] "Le prix décide du délai"
  delay_curve jsonb not null default '[]'
    check (jsonb_typeof(delay_curve) = 'array'),
  expert_quote text check (char_length(expert_quote) <= 2000),

  -- Le bien tab.
  description text check (char_length(description) <= 4000),
  -- [{label, value, provenance: declared|document|external|verified}]
  technical_sheet jsonb not null default '[]'
    check (jsonb_typeof(technical_sheet) = 'array'),

  -- Secteur tab (the DVF curve comes from the EPIC-05 market snapshot).
  -- [{street, sold_on, area_m2, land_m2, price_eur, excluded}] — street
  -- without house number (decision 2026-10-01).
  comparables jsonb not null default '[]'
    check (jsonb_typeof(comparables) = 'array'),
  comparables_note text check (char_length(comparables_note) <= 1000),
  competitors_summary text check (char_length(competitors_summary) <= 500),
  -- [{label, price_eur, note, days_online, retained}] typed by the expert.
  competitors jsonb not null default '[]'
    check (jsonb_typeof(competitors) = 'array'),
  risks_note text check (char_length(risks_note) <= 1000),

  -- Prix tab.
  -- [{label, amount_eur, kind: base|line|total}] "Ce qui déplace le prix"
  adjustments jsonb not null default '[]'
    check (jsonb_typeof(adjustments) = 'array'),
  -- [{label, amount_eur, kind: line|total|control}] "La méthode"
  method_summary jsonb not null default '[]'
    check (jsonb_typeof(method_summary) = 'array'),
  -- Works the buyer will budget ("Le calcul que fera votre acquéreur").
  works_label text check (char_length(works_label) <= 200),
  works_estimate_eur integer check (works_estimate_eur >= 0),
  sources text check (char_length(sources) <= 1000),

  -- Expert and validity.
  expert_user_id uuid references auth.users (id) on delete set null,
  expert_display_name text not null
    check (char_length(expert_display_name) between 1 and 100),
  expert_initials text check (char_length(expert_initials) between 1 and 3),
  certified_at timestamptz not null default now(),
  valid_until date not null,

  -- Optional PDF in the valuation-reports bucket.
  report_storage_path text check (char_length(report_storage_path) <= 500),
  report_pages smallint check (report_pages between 1 and 500),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (low_eur <= value_eur and value_eur <= high_eur)
);

create index valuations_property_id_certified_at_idx
  on public.valuations (property_id, certified_at desc);

create trigger valuations_set_updated_at
  before update on public.valuations
  for each row execute function public.seller_tunnel_set_updated_at();

alter table public.valuations enable row level security;

create policy "Owners can view the valuations of their properties"
  on public.valuations for select
  to authenticated
  using (
    exists (
      select 1 from public.properties p
      where p.id = property_id and p.owner_id = (select auth.uid())
    )
  );

revoke all on table public.valuations from anon, authenticated;
grant select on table public.valuations to authenticated;

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  property_id uuid references public.properties (id) on delete cascade,
  kind text not null check (kind in ('review_started', 'valuation_certified')),
  title text not null check (char_length(title) between 1 and 200),
  body text check (char_length(body) <= 1000),
  -- App location opened from the notification (e.g. /vendeur/rapport).
  route text check (char_length(route) <= 200),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_id_created_at_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

create policy "Users can view their notifications"
  on public.notifications for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can mark their notifications read"
  on public.notifications for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on table public.notifications from anon, authenticated;
grant select on table public.notifications to authenticated;
grant update (read_at) on table public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: private bucket of the PDF reports (<owner id>/<property id>/…).
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'valuation-reports',
  'valuation-reports',
  false,
  31457280, -- 30 MB
  array['application/pdf']
);

create policy "Owners can read their valuation reports"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'valuation-reports'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ---------------------------------------------------------------------------
-- Staff functions (SQL editor / service role only).
-- ---------------------------------------------------------------------------

-- Takes a submitted dossier over: status in_review (locks it, see
-- lock_submitted_dossiers) and notifies the owner.
create function public.staff_start_review(p_property_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  update public.properties
  set status = 'in_review'
  where id = p_property_id and status = 'submitted'
  returning owner_id into v_owner;

  if v_owner is null then
    raise exception 'Property % not found or not submitted', p_property_id
      using errcode = 'P0002';
  end if;

  insert into public.notifications (user_id, property_id, kind, title, body, route)
  values (
    v_owner, p_property_id, 'review_started',
    'Un expert analyse votre dossier',
    'Votre avis de valeur certifié arrive bientôt.',
    '/vendeur'
  );
end;
$$;

-- Certifies a submitted or in-review dossier: inserts the valuation from
-- p_valuation (keys = valuations columns, see the runbook), sets the status
-- to certified and notifies the owner. Returns the valuation id.
create function public.staff_certify_property(
  p_property_id uuid,
  p_valuation jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_property public.properties;
  v_id uuid;
  v_certified_at timestamptz :=
    coalesce((p_valuation ->> 'certified_at')::timestamptz, now());
begin
  select * into v_property
  from public.properties
  where id = p_property_id
  for update;

  if v_property.id is null
    or v_property.status not in ('submitted', 'in_review') then
    raise exception 'Property % not found or not submitted / in review',
      p_property_id using errcode = 'P0002';
  end if;

  insert into public.valuations (
    property_id, value_eur, low_eur, high_eur, price_m2_eur, ai_trend_eur,
    estimated_delay_weeks, method_steps, reasons, delay_curve, expert_quote,
    description, technical_sheet, comparables, comparables_note,
    competitors_summary, competitors, risks_note, adjustments,
    method_summary, works_label, works_estimate_eur, sources,
    expert_user_id, expert_display_name, expert_initials, certified_at,
    valid_until, report_storage_path, report_pages
  ) values (
    p_property_id,
    (p_valuation ->> 'value_eur')::integer,
    (p_valuation ->> 'low_eur')::integer,
    (p_valuation ->> 'high_eur')::integer,
    coalesce(
      (p_valuation ->> 'price_m2_eur')::integer,
      case when v_property.living_area_m2 > 0
        then round((p_valuation ->> 'value_eur')::numeric
          / v_property.living_area_m2)::integer
      end
    ),
    coalesce(
      (p_valuation ->> 'ai_trend_eur')::integer,
      v_property.ai_estimate_median_eur
    ),
    (p_valuation ->> 'estimated_delay_weeks')::smallint,
    coalesce(p_valuation -> 'method_steps', '[]'),
    coalesce(p_valuation -> 'reasons', '[]'),
    coalesce(p_valuation -> 'delay_curve', '[]'),
    p_valuation ->> 'expert_quote',
    p_valuation ->> 'description',
    coalesce(p_valuation -> 'technical_sheet', '[]'),
    coalesce(p_valuation -> 'comparables', '[]'),
    p_valuation ->> 'comparables_note',
    p_valuation ->> 'competitors_summary',
    coalesce(p_valuation -> 'competitors', '[]'),
    p_valuation ->> 'risks_note',
    coalesce(p_valuation -> 'adjustments', '[]'),
    coalesce(p_valuation -> 'method_summary', '[]'),
    p_valuation ->> 'works_label',
    (p_valuation ->> 'works_estimate_eur')::integer,
    p_valuation ->> 'sources',
    (p_valuation ->> 'expert_user_id')::uuid,
    p_valuation ->> 'expert_display_name',
    p_valuation ->> 'expert_initials',
    v_certified_at,
    coalesce(
      (p_valuation ->> 'valid_until')::date,
      (v_certified_at + interval '3 months')::date
    ),
    p_valuation ->> 'report_storage_path',
    (p_valuation ->> 'report_pages')::smallint
  )
  returning id into v_id;

  update public.properties
  set status = 'certified'
  where id = p_property_id;

  insert into public.notifications (user_id, property_id, kind, title, body, route)
  values (
    v_property.owner_id, p_property_id, 'valuation_certified',
    'Votre avis de valeur certifié est disponible',
    'Découvrez la valeur de votre bien et le rapport de l’expert.',
    '/vendeur/rapport'
  );

  return v_id;
end;
$$;

-- Links the PDF uploaded to valuation-reports (path
-- <owner id>/<property id>/<file>.pdf) to a valuation.
create function public.staff_attach_valuation_report(
  p_valuation_id uuid,
  p_storage_path text,
  p_pages smallint
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.valuations
  set report_storage_path = p_storage_path, report_pages = p_pages
  where id = p_valuation_id;

  if not found then
    raise exception 'Valuation % not found', p_valuation_id
      using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.staff_start_review(uuid)
  from public, anon, authenticated;
revoke execute on function public.staff_certify_property(uuid, jsonb)
  from public, anon, authenticated;
revoke execute on function public.staff_attach_valuation_report(uuid, text, smallint)
  from public, anon, authenticated;
