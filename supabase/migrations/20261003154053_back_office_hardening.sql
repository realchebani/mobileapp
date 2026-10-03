-- EPIC-12 · back-office hardening (review of 2026-10-03).
--
-- S1  Signatory of a valuation: an ACTIVE team member. A non-admin may only
--     set `expert_user_id` to their own id (or keep the one already in the
--     draft); the admin may pick any active member. The name and initials
--     shown to the seller always come from `staff_members` (never free text).
-- S3  What a partner sees of a dossier is shaped in ONE place,
--     `_bo_partner_view`; the PDF path of the valuation (which holds the
--     seller's id) is no longer returned to partners.
-- S5  `bo_attach_report` checks the path and the file itself (file_not_found
--     → HTTP 404 instead of a 500 from staff_attach_valuation_report).
-- Error codes as in back_office_http_codes: PT404 / PT409 / 42501 / 22023.

-- ---------------------------------------------------------------------------
-- S1 · signatory
-- ---------------------------------------------------------------------------

-- Errors of the signatory of a draft that need the database (the pure rules
-- stay in _bo_valuation_errors, in parity with the Dart validator).
create function public._bo_signatory_errors(p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id text := p_payload ->> 'expert_user_id';
begin
  if v_id is null
    or v_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return '[]';
  end if;
  if exists (
    select 1 from public.staff_members m where m.user_id = v_id::uuid and m.active
  ) then
    return '[]';
  end if;
  return jsonb_build_array(
    jsonb_build_object('path', 'expert_user_id', 'code', 'unknown_signatory'));
end;
$$;

revoke all on function public._bo_signatory_errors(jsonb) from public, anon, authenticated;

create or replace function public.bo_save_draft(
  p_property_id uuid, p_payload jsonb, p_expected_version integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
  v_draft public.valuation_drafts;
  v_version integer;
  v_signer text;
begin
  perform public._bo_require_property(p_property_id);
  if not exists (
    select 1 from public.properties p
    where p.id = p_property_id and p.status in ('submitted', 'in_review')
  ) then
    raise exception 'dossier_closed' using errcode = 'PT409';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_payload' using errcode = '22023';
  end if;

  select * into v_draft from public.valuation_drafts d
  where d.property_id = p_property_id for update;

  -- A non-admin signs for themselves only (or keeps the signatory already
  -- chosen in the draft, e.g. by the admin or the partner who wrote it).
  v_signer := lower(nullif(btrim(p_payload ->> 'expert_user_id'), ''));
  if v_role <> 'admin' and v_signer is not null
    and v_signer <> auth.uid()::text
    and v_signer is distinct from lower(v_draft.payload ->> 'expert_user_id') then
    raise exception 'signatory_not_allowed' using errcode = '42501';
  end if;

  if v_draft.property_id is null then
    if coalesce(p_expected_version, 0) <> 0 then
      raise exception 'draft_conflict' using errcode = 'PT409';
    end if;
    insert into public.valuation_drafts (property_id, payload, updated_by)
    values (p_property_id, p_payload, auth.uid())
    on conflict (property_id) do nothing
    returning version into v_version;
    if v_version is null then
      raise exception 'draft_conflict' using errcode = 'PT409';
    end if;
  else
    if p_expected_version is distinct from v_draft.version then
      raise exception 'draft_conflict' using errcode = 'PT409',
        detail = coalesce((select m.display_name from public.staff_members m
          where m.user_id = v_draft.updated_by), '');
    end if;
    if v_role = 'partner_expert' and v_draft.status = 'submitted_for_approval' then
      raise exception 'draft_submitted' using errcode = 'PT409';
    end if;
    update public.valuation_drafts
    set payload = p_payload, version = version + 1,
        updated_by = auth.uid(), updated_at = now()
    where property_id = p_property_id
    returning version into v_version;
  end if;

  perform public._bo_log('draft_saved', p_property_id, 'valuation_draft',
    p_property_id::text, jsonb_build_object('version', v_version));
  return v_version;
end;
$$;

create or replace function public.bo_validate_draft(p_property_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_payload jsonb;
begin
  perform public._bo_actor(array['admin', 'expert', 'partner_expert']);
  perform public._bo_require_property(p_property_id);
  select d.payload into v_payload from public.valuation_drafts d
  where d.property_id = p_property_id;
  if v_payload is null then
    raise exception 'draft_not_found' using errcode = 'PT404';
  end if;
  return public._bo_valuation_errors(v_payload)
    || public._bo_signatory_errors(v_payload);
end;
$$;

create or replace function public._bo_lock_valid_draft(
  p_property_id uuid, p_expected_version integer
)
returns public.valuation_drafts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_draft public.valuation_drafts;
  v_errors jsonb;
begin
  select * into v_draft from public.valuation_drafts d
  where d.property_id = p_property_id for update;
  if v_draft.property_id is null then
    raise exception 'draft_not_found' using errcode = 'PT404';
  end if;
  if p_expected_version is distinct from v_draft.version then
    raise exception 'draft_conflict' using errcode = 'PT409';
  end if;
  v_errors := public._bo_valuation_errors(v_draft.payload)
    || public._bo_signatory_errors(v_draft.payload);
  if jsonb_array_length(v_errors) > 0 then
    raise exception 'draft_invalid' using errcode = '22023', detail = v_errors::text;
  end if;
  return v_draft;
end;
$$;

-- Signatory: expert_user_id of the draft, else the partner who submitted it,
-- else the caller; it must be an active member; name and initials are theirs.
create or replace function public.bo_certify(p_property_id uuid, p_expected_version integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_draft public.valuation_drafts;
  v_payload jsonb;
  v_signer uuid;
  v_member public.staff_members;
  v_id uuid;
begin
  perform public._bo_actor(array['admin', 'expert']);
  perform public._bo_require_property(p_property_id);
  v_draft := public._bo_lock_valid_draft(p_property_id, p_expected_version);

  select coalesce(jsonb_object_agg(k, v), '{}') into v_payload
  from jsonb_each(v_draft.payload) as e(k, v)
  where not (jsonb_typeof(v) = 'null'
    or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = ''));

  v_signer := coalesce(
    (v_payload ->> 'expert_user_id')::uuid,
    case when v_draft.status = 'submitted_for_approval' then v_draft.submitted_by end,
    auth.uid());
  select * into v_member from public.staff_members m
  where m.user_id = v_signer and m.active;
  if v_member.user_id is null then
    raise exception 'invalid_signatory' using errcode = '22023';
  end if;
  v_payload := v_payload || jsonb_build_object(
    'expert_user_id', v_signer,
    'expert_display_name', v_member.display_name,
    'expert_initials', v_member.initials);

  perform set_config('realesty.bo_call', 'on', true);
  v_id := public.staff_certify_property(p_property_id, v_payload);
  perform set_config('realesty.bo_call', '', true);

  delete from public.valuation_drafts where property_id = p_property_id;
  perform public._bo_log('certified', p_property_id, 'valuation', v_id::text,
    jsonb_build_object(
      'value_eur', (v_payload ->> 'value_eur')::integer,
      'signatory', v_signer,
      'draft_version', v_draft.version,
      'submitted_by', v_draft.submitted_by));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- S5 · attach the PDF: path and file checked here
-- ---------------------------------------------------------------------------

create or replace function public.bo_attach_report(
  p_property_id uuid, p_storage_path text, p_pages smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_valuation uuid;
  v_prefix text;
begin
  perform public._bo_actor(array['admin', 'expert']);
  perform public._bo_require_property(p_property_id);
  select v.id into v_valuation from public.valuations v
  where v.property_id = p_property_id order by v.certified_at desc limit 1;
  if v_valuation is null then
    raise exception 'not_certified' using errcode = 'PT409';
  end if;
  select p.owner_id::text || '/' || p.id::text || '/' into v_prefix
  from public.properties p where p.id = p_property_id;
  if p_storage_path is null
    or left(p_storage_path, char_length(v_prefix)) <> v_prefix
    or char_length(p_storage_path) <= char_length(v_prefix) then
    raise exception 'invalid_path' using errcode = '22023';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'valuation-reports' and o.name = p_storage_path
  ) then
    raise exception 'file_not_found' using errcode = 'PT404';
  end if;
  if p_pages is null or p_pages not between 1 and 500 then
    raise exception 'invalid_pages' using errcode = '22023';
  end if;
  perform set_config('realesty.bo_call', 'on', true);
  perform public.staff_attach_valuation_report(v_valuation, p_storage_path, p_pages);
  perform set_config('realesty.bo_call', '', true);
  perform public._bo_log('report_attached', p_property_id, 'valuation', v_valuation::text,
    jsonb_build_object('pages', p_pages));
end;
$$;

-- ---------------------------------------------------------------------------
-- S3 · what a partner sees: one place
-- ---------------------------------------------------------------------------

-- Every restriction of a partner on a dossier (bo_get_dossier) is here:
-- no seller id or contact, owners as initials + commune, no identity
-- document, no storage path (the PDF path holds the seller's id). Still
-- visible, to be confirmed by the owner (plan §12 ter): full address, secret
-- note, step notes, purchase price, voice transcripts.
create function public._bo_partner_view(p_dossier jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select p_dossier || jsonb_build_object(
    'property', (p_dossier -> 'property') - 'owner_id',
    'seller', case when jsonb_typeof(p_dossier -> 'seller') = 'object' then
      jsonb_build_object(
        'initials', public._bo_initials(
          p_dossier #>> '{seller,first_name}', p_dossier #>> '{seller,last_name}'),
        'city', p_dossier #>> '{property,address_city}',
        'deactivated', coalesce(p_dossier #> '{seller,deactivated}', 'false'::jsonb))
      end,
    'owners', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', o -> 'id',
          'position', o -> 'position',
          'initials', public._bo_initials(o ->> 'first_name', o ->> 'last_name'),
          'city', p_dossier #>> '{property,address_city}',
          'identity_verified_at', o -> 'identity_verified_at') order by t.ord)
      from jsonb_array_elements(p_dossier -> 'owners') with ordinality as t(o, ord)), '[]'),
    'documents', coalesce((
      select jsonb_agg(t.d order by t.ord)
      from jsonb_array_elements(p_dossier -> 'documents') with ordinality as t(d, ord)
      where t.d ->> 'kind' <> 'piece_identite'), '[]'),
    'valuation', case when jsonb_typeof(p_dossier -> 'valuation') = 'object'
      then (p_dossier -> 'valuation') || '{"report_storage_path": null}'::jsonb
      else p_dossier -> 'valuation' end
  );
$$;

revoke all on function public._bo_partner_view(jsonb) from public, anon, authenticated;

-- One dossier; a partner gets it through _bo_partner_view. Journals
-- 'dossier_opened'.
create or replace function public.bo_get_dossier(p_property_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
  v_partner boolean := v_role = 'partner_expert';
  v_p public.properties;
  v_result jsonb;
begin
  perform public._bo_require_property(p_property_id);
  select * into v_p from public.properties where id = p_property_id;

  v_result := jsonb_build_object(
    'role', v_role,
    'property', to_jsonb(v_p),
    'seller', (
      select jsonb_build_object(
          'user_id', pr.id, 'first_name', pr.first_name, 'last_name', pr.last_name,
          'phone', pr.phone, 'email', u.email,
          'deactivated', pr.deactivated_at is not null,
          'deletion_due_at', pr.deletion_due_at)
      from public.profiles pr
      left join auth.users u on u.id = pr.id
      where pr.id = v_p.owner_id),
    'owners', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', o.id, 'position', o.position, 'first_name', o.first_name,
          'last_name', o.last_name, 'phone', o.phone, 'email', o.email,
          'identity_verified_at', o.identity_verified_at) order by o.position)
      from public.property_owners o where o.property_id = p_property_id), '[]'),
    'parcels', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', pp.id, 'idu', pp.idu, 'code_insee', pp.code_insee,
          'section', pp.section, 'numero', pp.numero, 'area_m2', pp.area_m2,
          'source', pp.source) order by pp.idu)
      from public.property_parcels pp where pp.property_id = p_property_id), '[]'),
    'previous_estimates', coalesce((
      select jsonb_agg(to_jsonb(e) - 'property_id' order by e.created_at)
      from public.previous_estimates e where e.property_id = p_property_id), '[]'),
    'rooms', coalesce((
      select jsonb_agg(to_jsonb(r) - 'property_id' - 'scan_data' order by r.sort_order, r.created_at)
      from public.rooms r where r.property_id = p_property_id), '[]'),
    'lifestyle_items', coalesce((
      select jsonb_agg(to_jsonb(li) - 'property_id' order by li.sort_order, li.created_at)
      from public.lifestyle_items li where li.property_id = p_property_id), '[]'),
    'documents', coalesce((
      select jsonb_agg(to_jsonb(d) - 'property_id' - 'storage_path' order by d.uploaded_at desc)
      from public.property_documents d
      where d.property_id = p_property_id), '[]'),
    'photos', coalesce((
      select jsonb_agg(to_jsonb(ph) - 'property_id' - 'storage_path'
        order by r.sort_order, ph.room_id, ph.sort_order)
      from public.room_photos ph
      join public.rooms r on r.id = ph.room_id
      where ph.property_id = p_property_id), '[]'),
    'voice_sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', s.id, 'step', s.step, 'status', s.status,
          'created_at', s.created_at, 'updated_at', s.updated_at) order by s.created_at)
      from public.agent_sessions s where s.property_id = p_property_id), '[]'),
    'voice_thread', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.at)
      from public.staff_voice_thread(p_property_id) t), '[]'),
    'fill_sheet', coalesce((
      select jsonb_agg(to_jsonb(f) order by f.sort_order)
      from public.staff_fill_sheet(p_property_id) f), '[]'),
    'market', (
      select to_jsonb(m) - 'property_id'
      from public.market_snapshots m where m.property_id = p_property_id
      order by m.created_at desc limit 1),
    'lot', (
      select jsonb_build_object(
        'id', l.id, 'name', l.name, 'sale_mode', l.sale_mode,
        'main_property_id', l.main_property_id,
        'members', (
          select jsonb_agg(jsonb_build_object(
              'id', m.id, 'property_type', m.property_type, 'status', m.status,
              'city', m.address_city, 'living_area_m2', m.living_area_m2,
              'accessible', public.bo_can_access_property(m.id)) order by m.created_at)
          from public.properties m where m.lot_id = l.id))
      from public.property_lots l where l.id = v_p.lot_id),
    'valuation', (
      select to_jsonb(v) from public.valuations v
      where v.property_id = p_property_id
      order by v.certified_at desc limit 1),
    'draft', (
      select jsonb_build_object(
        'payload', d.payload, 'version', d.version, 'status', d.status,
        'updated_at', d.updated_at, 'updated_by', d.updated_by,
        'updated_by_name', (select m.display_name from public.staff_members m where m.user_id = d.updated_by),
        'submitted_by', d.submitted_by,
        'submitted_by_name', (select m.display_name from public.staff_members m where m.user_id = d.submitted_by),
        'submitted_at', d.submitted_at, 'approval_note', d.approval_note)
      from public.valuation_drafts d where d.property_id = p_property_id),
    'assignment', (
      select jsonb_build_object(
        'user_id', a.expert_user_id, 'display_name', m.display_name,
        'initials', m.initials, 'role', m.role, 'assigned_at', a.assigned_at,
        'note', a.note)
      from public.dossier_assignments a
      join public.staff_members m on m.user_id = a.expert_user_id
      where a.property_id = p_property_id and a.revoked_at is null)
  );

  if v_partner then
    v_result := public._bo_partner_view(v_result);
  end if;
  perform public._bo_log('dossier_opened', p_property_id);
  return v_result;
end;
$$;

