-- EPIC-16 · Voix prioritaire (docs/plans/2026-10-03-voix-prioritaire.md §6).
-- Additive only: step notes and the origin of every saved value
-- (field_sources), the answers said for another step (pending_answers,
-- written by agent-turn with the service role, resolved by the app), the
-- catalog of the dossier fields, and two staff functions (conversation
-- thread, fill sheet) run from the SQL editor until the expert back office
-- (EPIC-12). The `owners` step stays readable in the journal (old turns);
-- the functions simply stop creating it.

-- ---------------------------------------------------------------------------
-- Step notes and field sources (§4, §5.3).
-- ---------------------------------------------------------------------------

-- An object whose keys are steps with a « Notes complémentaires » field and
-- whose values are texts of at most 1 000 characters.
create function public.step_notes_valid(p_notes jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p_notes) = 'object' and not exists (
    select 1
    from jsonb_each(p_notes) as e
    where e.key not in ('location', 'context', 'technical', 'rooms', 'lifestyle')
      or jsonb_typeof(e.value) <> 'string'
      or char_length(e.value #>> '{}') > 1000
  );
$$;

-- field_sources: {column: {s: source, t?: turn id, k?: evidence key,
-- p?: accepted pending answer id, c?: confirmation, at: saved at}}, written
-- by the app in the same request as the value (Property.mergeFieldSources).
alter table public.properties
  add column step_notes jsonb not null default '{}'
    check (public.step_notes_valid(step_notes)),
  add column field_sources jsonb not null default '{}'
    check (
      jsonb_typeof(field_sources) = 'object'
      and octet_length(field_sources::text) <= 32000
    );

comment on column public.properties.step_notes is
  'EPIC-16 · « Notes complémentaires » per step (location, context, '
  'technical, rooms, lifestyle), ≤ 1 000 characters each, typed or dictated.';
comment on column public.properties.field_sources is
  'EPIC-16 · origin of each saved value: {column: {s, t, k, p, c, at}} '
  '(source dicte | dicte_autre_etape | saisi | extrait | externe).';

-- properties grants updates column by column.
grant update (step_notes, field_sources) on table public.properties
  to authenticated;

-- Room notes: « Notes complémentaires » (the column keeps its name,
-- EPIC-15 already uses it), up to 600 characters.
alter table public.rooms
  drop constraint rooms_description_check,
  add constraint rooms_description_check
    check (char_length(description) <= 600),
  add column field_sources jsonb not null default '{}'
    check (
      jsonb_typeof(field_sources) = 'object'
      and octet_length(field_sources::text) <= 8000
    );

comment on column public.rooms.description is
  'V5c · « Notes complémentaires » of the room (≤ 600 characters), typed, '
  'dictated or added from a photo.';

alter table public.previous_estimates
  add column source text not null default 'manual'
    check (source in ('manual', 'voice')),
  add column field_sources jsonb not null default '{}'
    check (
      jsonb_typeof(field_sources) = 'object'
      and octet_length(field_sources::text) <= 8000
    );

alter table public.lifestyle_items
  add column field_sources jsonb not null default '{}'
    check (
      jsonb_typeof(field_sources) = 'object'
      and octet_length(field_sources::text) <= 8000
    );
-- The child tables keep their table-level grants and their lock (RLS, draft
-- / submitted only): the new columns are covered.

-- ---------------------------------------------------------------------------
-- Answers said for another step (§3, §6.2).
-- ---------------------------------------------------------------------------

create table public.pending_answers (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id)
    on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  target_step text not null check (target_step in (
    'location', 'context', 'technical', 'rooms', 'lifestyle'
  )),
  kind text not null check (kind in (
    'field', 'room', 'previous_estimate', 'lifestyle_item', 'note'
  )),
  -- The properties column (kind = field).
  field text check (char_length(field) <= 60),
  -- The typed value (field), or the values of the entity / the note text.
  value jsonb not null check (octet_length(value::text) <= 2000),
  label_fr text not null check (char_length(label_fr) between 1 and 160),
  -- « Prix d’achat : 300 000 € → 320 000 € » when it replaces a value.
  changed_fr text check (char_length(changed_fr) <= 160),
  quote text not null check (char_length(quote) between 1 and 300),
  confidence numeric(3, 2) check (confidence between 0 and 1),
  -- The step where the sentence was said.
  source_step text not null check (source_step in (
    'location', 'context', 'technical', 'rooms', 'lifestyle'
  )),
  turn_id uuid references public.agent_turns (id) on delete set null,
  status text not null default 'pending' check (status in (
    'pending', 'accepted', 'rejected', 'superseded', 'expired'
  )),
  resolution text check (resolution in (
    'continuer', 'oui', 'non', 'modifie', 'efface', 'annule', 'remplace',
    'envoi'
  )),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check ((kind = 'field') = (field is not null)),
  check ((status = 'pending') = (resolution is null))
);

comment on table public.pending_answers is
  'EPIC-16 · values said for another step, pre-filled there « À confirmer »; '
  'written by agent-turn (service role), resolved by the app; never applied '
  'to the dossier by the server.';

-- One open answer per field: a new value said for it replaces it.
create unique index pending_answers_one_open_field
  on public.pending_answers (property_id, field)
  where status = 'pending' and kind = 'field';
create index pending_answers_property
  on public.pending_answers (property_id, target_step, status);
create index pending_answers_turn on public.pending_answers (turn_id);

alter table public.pending_answers enable row level security;

create policy "Owners can view their pending answers"
  on public.pending_answers for select
  to authenticated
  using (owner_id = (select auth.uid()));

create policy "Owners can resolve the pending answers of their drafts"
  on public.pending_answers for update
  to authenticated
  using (
    owner_id = (select auth.uid())
    and exists (
      select 1 from public.properties p
      where p.id = property_id and p.owner_id = (select auth.uid())
        and p.status = 'draft'
    )
  )
  with check (
    owner_id = (select auth.uid())
    and exists (
      select 1 from public.properties p
      where p.id = property_id and p.owner_id = (select auth.uid())
        and p.status = 'draft'
    )
  );

-- No insert / delete for clients: the server writes them.
revoke all on table public.pending_answers from anon, authenticated;
grant select on table public.pending_answers to authenticated;
grant update (status, resolution) on table public.pending_answers
  to authenticated;

-- Only an open answer can be resolved, with a resolution matching its new
-- status; expiry (at submission) is reserved to the backend.
create function public.pending_answers_resolve()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_client constant boolean := current_user in ('authenticated', 'anon');
begin
  if old.status <> 'pending' then
    raise exception 'Pending answer % is already %', old.id, old.status
      using errcode = '23514';
  end if;
  if not (
    (new.status = 'accepted' and new.resolution in ('continuer', 'oui'))
    or (new.status = 'rejected'
      and new.resolution in ('non', 'modifie', 'efface', 'annule'))
    or (new.status = 'superseded' and new.resolution = 'remplace')
    or (new.status = 'expired' and new.resolution = 'envoi' and not v_client)
  ) then
    raise exception 'Invalid resolution % / %', new.status, new.resolution
      using errcode = '23514';
  end if;
  new.resolved_at := now();
  return new;
end;
$$;

create trigger pending_answers_resolve
  before update on public.pending_answers
  for each row execute function public.pending_answers_resolve();

-- At submission (draft → submitted), the answers still open expire: they
-- are never applied, the expert sees them as « dit, non confirmé ».
create function public.pending_answers_expire()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.pending_answers
  set status = 'expired', resolution = 'envoi'
  where property_id = new.id and status = 'pending';
  return null;
end;
$$;

revoke execute on function public.pending_answers_expire()
  from public, anon, authenticated;

create trigger properties_expire_pending_answers
  after update of status on public.properties
  for each row
  when (old.status = 'draft' and new.status = 'submitted')
  execute function public.pending_answers_expire();

-- Records the answers of one turn in ONE transaction (serialised per
-- property): the open answer of the same field is superseded, then the new
-- rows are inserted while fewer than p_max are open. Returns
-- {ids: [uuid | null per row], superseded: [uuid]}. Called by agent-turn
-- with the service role only, after checking ownership with the caller's JWT.
create function public.agent_record_pending(
  p_owner_id uuid,
  p_property_id uuid,
  p_turn_id uuid,
  p_source_step text,
  p_rows jsonb,
  p_max integer
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row jsonb;
  v_id uuid;
  v_old uuid;
  v_open integer;
  v_ids jsonb := '[]'::jsonb;
  v_superseded jsonb := '[]'::jsonb;
begin
  if not exists (
    select 1 from public.properties
    where id = p_property_id and owner_id = p_owner_id and status = 'draft'
  ) then
    raise exception 'Property % not found or not a draft', p_property_id
      using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('pending_answers:' || p_property_id::text, 0)
  );
  select count(*) into v_open
  from public.pending_answers
  where property_id = p_property_id and status = 'pending';

  for v_row in
    select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    if v_row ->> 'kind' = 'field' then
      v_old := null;
      update public.pending_answers
      set status = 'superseded', resolution = 'remplace'
      where property_id = p_property_id and kind = 'field'
        and field = v_row ->> 'field' and status = 'pending'
      returning id into v_old;
      if v_old is not null then
        v_superseded := v_superseded || to_jsonb(v_old);
        v_open := v_open - 1;
      end if;
    end if;
    if v_open >= p_max then
      v_ids := v_ids || 'null'::jsonb;
      continue;
    end if;
    insert into public.pending_answers (
      property_id, owner_id, target_step, kind, field, value, label_fr,
      changed_fr, quote, confidence, source_step, turn_id
    ) values (
      p_property_id, p_owner_id, v_row ->> 'target_step', v_row ->> 'kind',
      v_row ->> 'field', v_row -> 'value', v_row ->> 'label_fr',
      v_row ->> 'changed_fr', v_row ->> 'quote',
      (v_row ->> 'confidence')::numeric, p_source_step, p_turn_id
    )
    returning id into v_id;
    v_open := v_open + 1;
    v_ids := v_ids || to_jsonb(v_id);
  end loop;
  return jsonb_build_object('ids', v_ids, 'superseded', v_superseded);
end;
$$;

revoke all on function public.agent_record_pending(
  uuid, uuid, uuid, text, jsonb, integer
) from public, anon, authenticated;
grant execute on function public.agent_record_pending(
  uuid, uuid, uuid, text, jsonb, integer
) to service_role;

-- ---------------------------------------------------------------------------
-- Catalog of the dossier fields (§5.3): labels and codes of every value the
-- fill sheet shows, for the staff functions and the EPIC-12 back office.
-- Kept in parity with the agent registry (supabase/functions/tests).
-- ---------------------------------------------------------------------------

create table public.dossier_field_catalog (
  step text not null,
  entity text not null check (entity in (
    'property', 'room', 'previous_estimate', 'lifestyle_item', 'note'
  )),
  field text not null,
  label_fr text not null,
  sort_order smallint not null,
  -- code → French label (enumerations and lists).
  codes jsonb,
  primary key (entity, field)
);

alter table public.dossier_field_catalog enable row level security;
revoke all on table public.dossier_field_catalog
  from public, anon, authenticated;
grant select on table public.dossier_field_catalog to service_role;

insert into public.dossier_field_catalog
  (step, entity, field, label_fr, sort_order, codes)
values
  ('location', 'property', 'address_label', 'Adresse', 10, null),
  ('location', 'property', 'special_situations', 'Situations particulières', 20, '{"servitude_passage":"Servitude de passage","servitude_reseaux":"Servitude de réseaux","autre":"Autre situation","aucune":"Aucune"}'::jsonb),
  ('location', 'property', 'special_situation_other', 'Autre situation', 30, null),
  ('context', 'property', 'property_type', 'Type', 40, '{"maison":"Maison","appartement":"Appartement","terrain":"Terrain","stationnement":"Garage / parking","dependance":"Cave / dépendance","local_commercial":"Local commercial","immeuble":"Immeuble","autre":"Autre"}'::jsonb),
  ('context', 'property', 'property_type_other', 'Précision', 50, null),
  ('context', 'property', 'land_kind', 'Terrain', 60, '{"constructible":"Constructible","non_constructible":"Non constructible","inconnu":"Je ne sais pas"}'::jsonb),
  ('context', 'property', 'parking_kind', 'Stationnement', 70, '{"box":"Box","garage":"Garage","place_couverte":"Place couverte","place_exterieure":"Place extérieure"}'::jsonb),
  ('context', 'property', 'commercial_use', 'Usage', 80, null),
  ('context', 'property', 'units_count', 'Logements', 90, null),
  ('context', 'property', 'purchase_year', 'Achat', 100, null),
  ('context', 'property', 'purchase_price_eur', 'Prix d’achat', 110, null),
  ('context', 'property', 'self_built', 'Construit par vous', 120, null),
  ('context', 'property', 'sale_reason', 'Raison', 130, '{"mutation":"Mutation","agrandissement":"Agrandissement","separation":"Séparation","investissement":"Investissement","autre":"Autre"}'::jsonb),
  ('context', 'property', 'previously_estimated', 'Déjà estimé', 140, null),
  ('context', 'previous_estimate', 'price_eur', 'Estimation', 150, null),
  ('context', 'previous_estimate', 'estimated_month', 'Mois', 160, null),
  ('context', 'previous_estimate', 'agency_name', 'Agence', 170, null),
  ('technical', 'property', 'construction_year', 'Construction', 180, null),
  ('technical', 'property', 'living_area_m2', 'Surface habitable', 190, null),
  ('technical', 'property', 'living_room_area_m2', 'Surface séjour', 200, null),
  ('technical', 'property', 'rooms_count', 'Pièces', 210, null),
  ('technical', 'property', 'bedrooms_count', 'Chambres', 220, null),
  ('technical', 'property', 'levels', 'Niveaux', 230, '{"plain_pied":"Plain-pied","r1":"R+1","r2_plus":"R+2 et plus"}'::jsonb),
  ('technical', 'property', 'orientation', 'Exposition', 240, '{"nord":"Nord","nord_est":"Nord-Est","est":"Est","sud_est":"Sud-Est","sud":"Sud","sud_ouest":"Sud-Ouest","ouest":"Ouest","nord_ouest":"Nord-Ouest","traversant":"Traversant"}'::jsonb),
  ('technical', 'property', 'wall_material', 'Murs', 250, '{"parpaing":"Parpaing","brique":"Brique","pierre":"Pierre","beton":"Béton","moellon":"Moellon","bois":"Bois","pise":"Pisé"}'::jsonb),
  ('technical', 'property', 'adjacency', 'Mitoyenneté', 260, '{"1":"Mitoyen 1 côté","2":"Mitoyen 2 côtés","3":"Mitoyen 3 côtés","independant":"Indépendant"}'::jsonb),
  ('technical', 'property', 'roof_type', 'Toiture', 270, '{"tuiles":"Tuiles","ardoises":"Ardoises","toit_terrasse":"Toit-terrasse","bac_acier":"Bac acier","zinc":"Zinc","autre":"Autre"}'::jsonb),
  ('technical', 'property', 'roof_year', 'Année toiture', 280, null),
  ('technical', 'property', 'heating_systems', 'Chauffage', 290, '{"electricite":"Électrique","pac":"Pompe à chaleur","gaz":"Gaz","fioul":"Fioul","bois":"Poêle à bois","granules":"Poêle à granulés","cheminee":"Cheminée / insert","reseau_chaleur":"Réseau de chaleur","solaire":"Solaire","autre":"Autre"}'::jsonb),
  ('technical', 'property', 'heat_pump_type', 'Type de PAC', 300, '{"air_eau":"Air / eau","air_air":"Air / air","geothermique":"Géothermique"}'::jsonb),
  ('technical', 'property', 'heat_pump_year', 'Année PAC', 310, null),
  ('technical', 'property', 'sanitation', 'Assainissement', 320, '{"tout_a_l_egout":"Tout-à-l’égout","fosse_septique":"Fosse septique","puits_perdu":"Puits perdu"}'::jsonb),
  ('technical', 'property', 'outdoor_equipment', 'Extérieur', 330, '{"piscine":"Piscine","garage":"Garage","terrasse":"Terrasse","abri_jardin":"Abri de jardin","portail_motorise":"Portail motorisé"}'::jsonb),
  ('technical', 'property', 'pool_type', 'Type de piscine', 340, '{"enterree_liner":"Enterrée · liner","enterree_coque":"Enterrée · coque","enterree_beton":"Enterrée · béton","semi_enterree":"Semi-enterrée","hors_sol":"Hors-sol"}'::jsonb),
  ('technical', 'property', 'pool_length_m', 'Longueur piscine', 350, null),
  ('technical', 'property', 'pool_width_m', 'Largeur piscine', 360, null),
  ('technical', 'property', 'usable_area_m2', 'Surface utile', 370, null),
  ('technical', 'property', 'parking_level', 'Niveau', 380, '{"sous_sol":"Sous-sol","rdc":"Rez-de-chaussée","etage":"Étage","exterieur":"Extérieur"}'::jsonb),
  ('technical', 'property', 'parking_features', 'Équipements', 390, '{"porte_motorisee":"Porte motorisée","electricite":"Électricité","borne_recharge":"Borne de recharge","eau":"Point d’eau","acces_securise":"Accès sécurisé"}'::jsonb),
  ('lifestyle', 'property', 'noise_level', 'Bruit', 400, null),
  ('lifestyle', 'property', 'overlooking', 'Vis-à-vis', 410, '{"aucun":"Aucun","leger":"Léger","important":"Important"}'::jsonb),
  ('lifestyle', 'property', 'secret_note', 'Note secrète', 420, null),
  ('rooms', 'property', 'measurement_method', 'Méthode de mesure', 430, '{"scan":"Scan","plan":"Plan","manual":"Saisie manuelle"}'::jsonb),
  ('rooms', 'property', 'annex_area_m2', 'Surface des annexes', 440, null),
  ('rooms', 'room', 'name', 'Pièce', 450, null),
  ('rooms', 'room', 'area_m2', 'Surface', 460, null),
  ('rooms', 'room', 'level', 'Niveau', 470, '{"sous_sol":"Sous-sol","rdc":"Rez-de-chaussée","etage_1":"Étage","etage_2":"Étage 2","combles":"Combles"}'::jsonb),
  ('rooms', 'room', 'floor_covering', 'Sol', 480, '{"parquet_chene":"Parquet chêne","parquet":"Parquet","carrelage":"Carrelage","moquette":"Moquette","beton_cire":"Béton ciré","stratifie":"Stratifié","vinyle":"Vinyle","autre":"Autre"}'::jsonb),
  ('rooms', 'room', 'glazing', 'Vitrage', 490, '{"simple":"Simple vitrage","double":"Double vitrage","triple":"Triple vitrage"}'::jsonb),
  ('rooms', 'room', 'ceiling_height_m', 'Hauteur sous plafond', 500, null),
  ('rooms', 'room', 'description', 'Notes complémentaires', 510, null),
  ('lifestyle', 'lifestyle_item', 'label', 'Atout / point de vigilance', 520, '{"asset":"Atout","watch_point":"Point de vigilance"}'::jsonb),
  ('location', 'note', 'location', 'Notes complémentaires', 530, null),
  ('context', 'note', 'context', 'Notes complémentaires', 540, null),
  ('technical', 'note', 'technical', 'Notes complémentaires', 550, null),
  ('rooms', 'note', 'rooms', 'Notes complémentaires', 560, null),
  ('lifestyle', 'note', 'lifestyle', 'Notes complémentaires', 570, null);

-- ---------------------------------------------------------------------------
-- Staff functions (§5.4): run with the service role (SQL editor, later an
-- EPIC-12 Edge Function). Runbook docs/runbooks/fiche-de-remplissage.md.
-- ---------------------------------------------------------------------------

-- Whether the value said [p_said] backs the saved value [p_saved]: same
-- set of codes, same number, or a text contained in the saved one (notes
-- are appended turn after turn).
create function public.voice_value_matches(p_said jsonb, p_saved jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_said is null or p_saved is null then false
    when jsonb_typeof(p_said) = 'array' and jsonb_typeof(p_saved) = 'array'
      then p_said @> p_saved and p_saved @> p_said
    when jsonb_typeof(p_said) = 'number' and jsonb_typeof(p_saved) = 'number'
      then abs((p_said #>> '{}')::numeric - (p_saved #>> '{}')::numeric) < 0.005
    when jsonb_typeof(p_said) = 'string' and jsonb_typeof(p_saved) = 'string'
      then strpos(p_saved #>> '{}', p_said #>> '{}') > 0
    else p_said = p_saved
  end;
$$;

-- (a) The conversation thread of a property, turn by turn.
create function public.staff_voice_thread(p_property_id uuid)
returns table (
  step text,
  turn_id uuid,
  at timestamptz,
  transcript text,
  reply_fr text,
  retained jsonb,
  cross_step jsonb,
  notes jsonb,
  rejected jsonb,
  confirmations jsonb,
  undone boolean,
  error text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    s.step,
    t.id,
    t.created_at,
    t.transcript,
    t.reply_fr,
    jsonb_strip_nulls(jsonb_build_object(
      'patch', t.extracted -> 'patch',
      'entity_ops', t.extracted -> 'entity_ops',
      'lifestyle_items', t.extracted -> 'lifestyle_items',
      'evidence', t.extracted -> 'evidence'
    )),
    coalesce(t.extracted -> 'cross_step', '[]'::jsonb),
    coalesce(t.extracted -> 'notes', '[]'::jsonb),
    coalesce(t.extracted -> 'rejected', '[]'::jsonb),
    coalesce(t.extracted -> 'confirmations', '[]'::jsonb),
    t.undone,
    t.error
  from public.agent_turns t
  join public.agent_sessions s on s.id = t.session_id
  where s.property_id = p_property_id
    and coalesce(t.error, '') not in ('in_progress', 'empty')
  order by t.created_at;
$$;

-- (b) The fill sheet: one row per saved value (property, rooms, previous
-- estimates, lifestyle items, step notes) with its source, the sentence it
-- comes from and whether the journal backs it; plus one row per answer said
-- for another step and not accepted.
create function public.staff_fill_sheet(p_property_id uuid)
returns table (
  step text,
  entity text,
  entity_id uuid,
  entity_label text,
  field text,
  label_fr text,
  value text,
  source text,
  quote text,
  turn_id uuid,
  said_at timestamptz,
  saved_at timestamptz,
  confirmed boolean,
  confirmation text,
  verified boolean,
  sort_order integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with prop as (
    select to_jsonb(p) as j, p.field_sources as fs, p.step_notes as notes
    from public.properties p
    where p.id = p_property_id
  ),
  turns as (
    select t.id, t.created_at, t.extracted
    from public.agent_turns t
    join public.agent_sessions s on s.id = t.session_id
    where s.property_id = p_property_id
  ),
  catalog as (
    select * from public.dossier_field_catalog
  ),
  vals as (
    -- The property's columns.
    select c.step, c.entity, null::uuid as entity_id, null::text as entity_label,
      c.field, c.label_fr, c.sort_order * 100 as sort_order, c.codes,
      prop.j -> c.field as v, prop.fs -> c.field as src,
      null::text as legacy
    from catalog c cross join prop
    where c.entity = 'property'
      and coalesce(prop.j -> c.field, 'null'::jsonb)
        not in ('null'::jsonb, '[]'::jsonb, '""'::jsonb)
    union all
    -- Rooms.
    select c.step, c.entity, r.id, r.name, c.field, c.label_fr,
      c.sort_order * 100 + r.sort_order, c.codes,
      to_jsonb(r) -> c.field, r.field_sources -> c.field,
      case r.source
        when 'voice' then 'dicte'
        when 'plan' then 'extrait'
        when 'scan' then 'extrait'
        else null
      end
    from public.rooms r
    cross join catalog c
    where r.property_id = p_property_id and c.entity = 'room'
      and coalesce(to_jsonb(r) -> c.field, 'null'::jsonb)
        not in ('null'::jsonb, '""'::jsonb)
    union all
    -- Previous estimates.
    select c.step, c.entity, e.id, 'Estimation ' || e.n, c.field, c.label_fr,
      c.sort_order * 100 + e.n::integer, c.codes,
      to_jsonb(e) -> c.field, e.field_sources -> c.field,
      case e.source when 'voice' then 'dicte' else null end
    from (
      select x.*, row_number() over (order by x.created_at) as n
      from public.previous_estimates x
      where x.property_id = p_property_id
    ) e
    cross join catalog c
    where c.entity = 'previous_estimate'
      and coalesce(to_jsonb(e) -> c.field, 'null'::jsonb)
        not in ('null'::jsonb, '""'::jsonb)
    union all
    -- Lifestyle items (the label; the kind as the entity label).
    select c.step, c.entity, i.id, c.codes ->> i.kind, c.field, c.label_fr,
      c.sort_order * 100 + i.sort_order, null,
      to_jsonb(i.label), i.field_sources -> 'label',
      case i.source when 'voice' then 'dicte' else null end
    from public.lifestyle_items i
    cross join catalog c
    where i.property_id = p_property_id and c.entity = 'lifestyle_item'
    union all
    -- Step notes.
    select c.step, c.entity, null, null, c.field, c.label_fr,
      c.sort_order * 100, null,
      prop.notes -> c.field, prop.fs -> ('step_notes.' || c.field), null
    from catalog c cross join prop
    where c.entity = 'note' and coalesce(prop.notes ->> c.field, '') <> ''
  )
  select
    v.step,
    v.entity,
    v.entity_id,
    v.entity_label,
    v.field,
    v.label_fr,
    case
      when v.codes is not null and jsonb_typeof(v.v) = 'array' then (
        select string_agg(coalesce(v.codes ->> x, x), ', ')
        from jsonb_array_elements_text(v.v) as x
      )
      when v.codes is not null then coalesce(v.codes ->> (v.v #>> '{}'), v.v #>> '{}')
      when jsonb_typeof(v.v) = 'array' then (
        select string_agg(x, ', ') from jsonb_array_elements_text(v.v) as x
      )
      else v.v #>> '{}'
    end,
    coalesce(v.src ->> 's', v.legacy, 'non_trace'),
    coalesce(ev.q, pa.quote),
    coalesce(t.id, pa.turn_id),
    coalesce(t.created_at, pt.created_at),
    case
      when v.src ->> 'at' ~ '^\d{4}-\d{2}-\d{2}T' then (v.src ->> 'at')::timestamptz
    end,
    true,
    case when pa.id is not null then coalesce(v.src ->> 'c', 'continuer') end,
    case
      when v.src ? 'p' then pa.status = 'accepted'
        and public.voice_value_matches(
          case when pa.kind = 'field' then pa.value else pa.value -> v.field end,
          v.v
        )
      when v.src ? 't' then t.id is not null
        and public.voice_value_matches(ev.v, v.v)
    end,
    v.sort_order
  from vals v
  left join turns t on t.id::text = v.src ->> 't'
  left join lateral (
    select e ->> 'q' as q, e -> 'v' as v
    from jsonb_array_elements(
      case when jsonb_typeof(t.extracted -> 'evidence') = 'array'
        then t.extracted -> 'evidence' else '[]'::jsonb end
    ) as e
    where e ->> 'k' = v.src ->> 'k'
    limit 1
  ) ev on true
  left join public.pending_answers pa
    on pa.id::text = v.src ->> 'p' and pa.property_id = p_property_id
  left join turns pt on pt.id = pa.turn_id
  union all
  -- Answers said for another step and not accepted.
  select
    pa.target_step,
    case when pa.kind = 'field' then 'property' else pa.kind end,
    pa.id,
    null,
    coalesce(pa.field, pa.kind),
    coalesce(c.label_fr, pa.label_fr),
    pa.label_fr,
    'dicte_autre_etape',
    pa.quote,
    pa.turn_id,
    pt.created_at,
    null,
    false,
    pa.status,
    pt.id is not null,
    coalesce(c.sort_order, 999) * 100 + 99
  from public.pending_answers pa
  left join catalog c on c.entity = 'property' and c.field = pa.field
  left join turns pt on pt.id = pa.turn_id
  where pa.property_id = p_property_id and pa.status <> 'accepted'
  order by 16, 4, 5;
$$;

revoke execute on function public.staff_voice_thread(uuid)
  from public, anon, authenticated;
revoke execute on function public.staff_fill_sheet(uuid)
  from public, anon, authenticated;
grant execute on function public.staff_voice_thread(uuid) to service_role;
grant execute on function public.staff_fill_sheet(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Cost and quality (§10): answers said for another step, their acceptance
-- rate (accepted / resolved) and the notes, per step × model × week.
-- Same columns as 20261002111222_voix_etendue.sql, three appended.
-- ---------------------------------------------------------------------------

create or replace view public.agent_step_stats
with (security_invoker = true) as
with turns as (
  select
    t.id,
    s.step,
    coalesce(t.agent_model, '-') as model,
    date_trunc('week', t.created_at)::date as week,
    t.reply_fr,
    t.cost_usd,
    t.audio_seconds,
    t.stt_ms,
    t.agent_ms,
    t.error,
    t.undone,
    t.extracted
  from public.agent_turns t
  join public.agent_sessions s on s.id = t.session_id
),
rejections as (
  select step, model, week, r ->> 'reason' as reason, count(*) as n
  from turns
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(extracted -> 'rejected') = 'array'
      then extracted -> 'rejected' else '[]'::jsonb end
  ) as r
  group by 1, 2, 3, 4
),
reasons as (
  select step, model, week, jsonb_object_agg(reason, n) as rejected_by_reason
  from rejections
  group by 1, 2, 3
),
pending as (
  select
    t.step,
    t.model,
    t.week,
    count(*) filter (where p.status = 'accepted') as accepted,
    count(*) filter (where p.status <> 'pending') as resolved
  from public.pending_answers p
  join turns t on t.id = p.turn_id
  group by 1, 2, 3
)
select
  t.step,
  t.model as agent_model,
  t.week,
  count(*) as turns,
  count(*) filter (where t.reply_fr is not null) as answered_turns,
  round(avg(t.cost_usd), 5) as avg_cost_usd,
  round(sum(t.cost_usd), 4) as total_cost_usd,
  round(avg(t.audio_seconds), 1) as avg_audio_seconds,
  round(avg(t.stt_ms)) as avg_stt_ms,
  round(avg(t.agent_ms)) as avg_agent_ms,
  round(
    count(*) filter (where t.error = 'invalid_output')::numeric
      / nullif(count(*) filter (where t.model <> '-'), 0), 3
  ) as invalid_output_rate,
  round(
    count(*) filter (where t.undone)::numeric
      / nullif(count(*) filter (where t.reply_fr is not null), 0), 3
  ) as undone_rate,
  round(
    count(*) filter (
      where jsonb_typeof(t.extracted -> 'corrections') = 'array'
        and jsonb_array_length(t.extracted -> 'corrections') > 0
    )::numeric / nullif(count(*) filter (where t.reply_fr is not null), 0), 3
  ) as correction_rate,
  coalesce(sum(
    case when jsonb_typeof(t.extracted -> 'confirmations') = 'array'
      then jsonb_array_length(t.extracted -> 'confirmations') else 0 end
  ), 0) as confirmations_asked,
  coalesce(r.rejected_by_reason, '{}'::jsonb) as rejected_by_reason,
  coalesce(sum(
    case when jsonb_typeof(t.extracted -> 'cross_step') = 'array'
      then jsonb_array_length(t.extracted -> 'cross_step') else 0 end
  ), 0) as cross_step_count,
  round(max(p.accepted)::numeric / nullif(max(p.resolved), 0), 3)
    as pending_accept_rate,
  coalesce(sum(
    case when jsonb_typeof(t.extracted -> 'notes') = 'array'
      then jsonb_array_length(t.extracted -> 'notes') else 0 end
  ), 0) as notes_count
from turns t
left join reasons r
  on r.step = t.step and r.model = t.model and r.week = t.week
left join pending p
  on p.step = t.step and p.model = t.model and p.week = t.week
group by t.step, t.model, t.week, r.rejected_by_reason;

comment on view public.agent_step_stats is
  'EPIC-14 / EPIC-16 · voice agent cost and quality per step, agent model '
  'and week (service role only).';

-- create or replace keeps the grants; restated (select only).
revoke all on table public.agent_step_stats from public, anon, authenticated;
revoke all on table public.agent_step_stats from service_role;
grant select on table public.agent_step_stats to service_role;
