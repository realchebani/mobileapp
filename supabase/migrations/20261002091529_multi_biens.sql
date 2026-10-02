-- EPIC-13 · Several properties per seller and sale lots
-- (docs/plans/2026-10-02-multi-biens.md, owner decisions of 2026-10-02).
--
-- - Several drafts per user: the unique index "one draft per owner" is
--   dropped. The app generates the id of a new property (retry-safe insert);
--   at most 5 properties per user during the test phase (trigger).
-- - New property types (stationnement, dependance, local_commercial,
--   immeuble) and the columns of their adapted audit.
-- - Sale lots: property_lots + properties.lot_id (a property is in at most
--   one lot). A lot only groups properties of its owner and is frozen once
--   one of its properties is in_review or certified.
-- - Notifications open the property they are about
--   (/vendeur/biens/<id>/…): existing rows are rewritten and the staff
--   functions recreated.
--
-- Existing rows are unchanged (lot_id null, same types); only the unique
-- index and the type check are replaced. Rollback of the index is only
-- possible with at most one draft per user:
--   select owner_id from public.properties where status = 'draft'
--   group by owner_id having count(*) > 1;

-- ---------------------------------------------------------------------------
-- Several drafts, at most 5 properties per user.
-- ---------------------------------------------------------------------------

drop index public.properties_one_draft_per_owner;

-- Test phase limit (owner decision Q11): 5 properties in total per user,
-- whatever their status. The advisory lock serializes concurrent inserts of
-- the same user so that the count cannot be bypassed.
create function public.properties_check_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext('properties_owner_' || new.owner_id::text));
  if (
    select count(*) from public.properties p where p.owner_id = new.owner_id
  ) >= 5 then
    raise exception 'property_limit_reached'
      using errcode = 'P0001',
        hint = 'At most 5 properties per user during the test phase.';
  end if;
  return new;
end;
$$;

revoke execute on function public.properties_check_limit()
  from public, anon, authenticated;

create trigger properties_check_limit
  before insert on public.properties
  for each row execute function public.properties_check_limit();

-- ---------------------------------------------------------------------------
-- Property types and the columns of their adapted audit.
-- ---------------------------------------------------------------------------

alter table public.properties
  drop constraint properties_property_type_check,
  add constraint properties_property_type_check check (property_type in (
    'maison', 'appartement', 'terrain', 'stationnement', 'dependance',
    'local_commercial', 'immeuble', 'autre'
  )),
  -- V3 · terrain
  add column land_kind text check (land_kind in (
    'constructible', 'non_constructible', 'inconnu'
  )),
  -- V3 · stationnement
  add column parking_kind text check (parking_kind in (
    'box', 'garage', 'place_couverte', 'place_exterieure'
  )),
  -- V3 · local commercial (boutique, bureau, entrepôt…)
  add column commercial_use text check (char_length(commercial_use) <= 100),
  -- V3 · immeuble
  add column units_count smallint check (units_count between 2 and 500),
  -- V4b · surface utile of non-dwelling properties (stationnement,
  -- dependance, local_commercial); living_area_m2 keeps its legal meaning.
  add column usable_area_m2 numeric(7, 2) check (usable_area_m2 > 0),
  -- V4b · stationnement: level of the space.
  add column parking_level text check (parking_level in (
    'sous_sol', 'rdc', 'etage', 'exterieur'
  )),
  -- V4b · equipment of a stationnement (all) or a dependance (electricite,
  -- eau).
  add column parking_features text[] not null default '{}'
    check (parking_features <@ array[
      'porte_motorisee', 'electricite', 'borne_recharge', 'eau',
      'acces_securise'
    ]::text[]);

comment on column public.properties.usable_area_m2 is
  'V4b · surface utile (m²) of a stationnement, dependance or local '
  'commercial; not the surface habitable (living_area_m2).';
comment on column public.properties.parking_features is
  'V4b · equipment: porte_motorisee, electricite, borne_recharge, eau, '
  'acces_securise (a dependance uses electricite / eau).';

grant update (
  land_kind, parking_kind, commercial_use, units_count, usable_area_m2,
  parking_level, parking_features
) on table public.properties to authenticated;

-- ---------------------------------------------------------------------------
-- Sale lots.
-- ---------------------------------------------------------------------------

create table public.property_lots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text check (char_length(name) between 1 and 80),
  -- 'ensemble': sold only together; 'ensemble_ou_separe': together, or
  -- each property on its own (owner decision Q3).
  sale_mode text not null default 'ensemble'
    check (sale_mode in ('ensemble', 'ensemble_ou_separe')),
  main_property_id uuid references public.properties (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.property_lots is
  'Sale lot: properties of one seller sold together (EPIC-13).';

create index property_lots_owner_id_idx on public.property_lots (owner_id);
create index property_lots_main_property_id_idx
  on public.property_lots (main_property_id);

create trigger property_lots_set_updated_at
  before update on public.property_lots
  for each row execute function public.seller_tunnel_set_updated_at();

alter table public.properties
  add column lot_id uuid references public.property_lots (id)
    on delete set null;

create index properties_lot_id_idx on public.properties (lot_id);

grant insert (id, owner_id, current_step, property_type, property_type_other, lot_id)
  on table public.properties to authenticated;
grant update (lot_id) on table public.properties to authenticated;

-- Whether a property of lot [p_lot_id] (other than [p_except]) is taken
-- over by the expert or certified: the lot is then frozen.
create function public.property_lot_is_frozen(p_lot_id uuid, p_except uuid)
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
  );
$$;

revoke execute on function public.property_lot_is_frozen(uuid, uuid)
  from public, anon;
grant execute on function public.property_lot_is_frozen(uuid, uuid)
  to authenticated;

-- properties.lot_id: only a lot of the same owner, never a frozen lot (to
-- join or to leave). Leaving a lot clears its main property if it was this
-- one.
create function public.properties_check_lot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old uuid;
begin
  if tg_op = 'UPDATE' then
    v_old := old.lot_id;
  end if;
  if new.lot_id is not distinct from v_old then
    return new;
  end if;
  if new.lot_id is not null then
    if not exists (
      select 1 from public.property_lots l
      where l.id = new.lot_id and l.owner_id = new.owner_id
    ) then
      raise exception 'lot_not_found'
        using errcode = 'P0001', hint = 'The lot must belong to the owner.';
    end if;
    if public.property_lot_is_frozen(new.lot_id, new.id) then
      raise exception 'lot_frozen' using errcode = 'P0001';
    end if;
  end if;
  if v_old is not null then
    if public.property_lot_is_frozen(v_old, new.id) then
      raise exception 'lot_frozen' using errcode = 'P0001';
    end if;
    update public.property_lots
    set main_property_id = null
    where id = v_old and main_property_id = new.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.properties_check_lot()
  from public, anon, authenticated;

create trigger properties_check_lot
  before insert or update of lot_id on public.properties
  for each row execute function public.properties_check_lot();

-- property_lots.main_property_id: a property of the lot's owner that is a
-- member of the lot.
create function public.property_lots_check_main()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.main_property_id is not null and not exists (
    select 1 from public.properties p
    where p.id = new.main_property_id
      and p.owner_id = new.owner_id
      and p.lot_id = new.id
  ) then
    raise exception 'main_property_not_in_lot' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.property_lots_check_main()
  from public, anon, authenticated;

create trigger property_lots_check_main
  before insert or update of main_property_id on public.property_lots
  for each row execute function public.property_lots_check_main();

alter table public.property_lots enable row level security;

create policy "Owners can view their lots"
  on public.property_lots for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can create lots"
  on public.property_lots for insert
  to authenticated
  with check ((select auth.uid()) = owner_id);

create policy "Owners can update their open lots"
  on public.property_lots for update
  to authenticated
  using (
    (select auth.uid()) = owner_id
    and not public.property_lot_is_frozen(id, null)
  )
  with check ((select auth.uid()) = owner_id);

create policy "Owners can delete their open lots"
  on public.property_lots for delete
  to authenticated
  using (
    (select auth.uid()) = owner_id
    and not public.property_lot_is_frozen(id, null)
  );

revoke all on table public.property_lots from anon, authenticated;
grant select, delete on table public.property_lots to authenticated;
grant insert (id, owner_id, name, sale_mode) on table public.property_lots
  to authenticated;
grant update (name, sale_mode, main_property_id) on table public.property_lots
  to authenticated;

-- ---------------------------------------------------------------------------
-- Notifications open their property.
-- ---------------------------------------------------------------------------

update public.notifications
set route = '/vendeur/biens/' || property_id::text || '/rapport'
where route = '/vendeur/rapport' and property_id is not null;

update public.notifications
set route = '/vendeur/biens/' || property_id::text
where route = '/vendeur' and property_id is not null;

-- Same as 20261001162633_valuations_and_notifications.sql, with the route
-- of the property.
create or replace function public.staff_start_review(p_property_id uuid)
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
    '/vendeur/biens/' || p_property_id::text
  );
end;
$$;

create or replace function public.staff_certify_property(
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
    '/vendeur/biens/' || p_property_id::text || '/rapport'
  );

  return v_id;
end;
$$;

-- create or replace keeps the existing grants; restated for clarity.
revoke execute on function public.staff_start_review(uuid)
  from public, anon, authenticated;
revoke execute on function public.staff_certify_property(uuid, jsonb)
  from public, anon, authenticated;
