-- EPIC-12 · Back-office expert (plan docs/plans/2026-10-03-back-office-expert.md).
--
-- The team (admin, hired expert, partner expert) reads and writes seller
-- dossiers ONLY through the `bo_*` functions below (security definer,
-- search_path ''), which check the caller's role in `staff_members`, require
-- an MFA session (JWT `aal` = 'aal2'), shape the answer by role and write the
-- append-only `staff_audit_log`. Seller tables keep exactly their policies.
-- The existing `staff_*` functions (SQL editor runbooks) keep working and now
-- also write the journal (`actor_role = 'sql_editor'`).

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

create table public.staff_members (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('admin', 'expert', 'partner_expert')),
  display_name text not null
    check (char_length(display_name) between 1 and 100),
  initials text not null check (char_length(initials) between 1 and 3),
  organisation text check (char_length(organisation) <= 120),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  deactivated_at timestamptz
);

comment on table public.staff_members is
  'EPIC-12: Realesty team access (one row = one access). Read by the bo_* '
  'functions at every call: deactivation is immediate.';

alter table public.staff_members enable row level security;
revoke all on public.staff_members from anon, authenticated;
grant select on public.staff_members to authenticated;
create policy "staff members read their own row"
  on public.staff_members for select to authenticated
  using (user_id = (select auth.uid()));

create table public.dossier_assignments (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  expert_user_id uuid not null
    references public.staff_members (user_id) on delete cascade,
  assigned_by uuid references auth.users (id) on delete set null,
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz,
  note text check (char_length(note) <= 300)
);

create unique index dossier_assignments_one_active
  on public.dossier_assignments (property_id) where revoked_at is null;
create index dossier_assignments_expert
  on public.dossier_assignments (expert_user_id) where revoked_at is null;

alter table public.dossier_assignments enable row level security;
revoke all on public.dossier_assignments from anon, authenticated;

create table public.valuation_drafts (
  property_id uuid primary key
    references public.properties (id) on delete cascade,
  payload jsonb not null default '{}'
    check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 200000),
  version integer not null default 1 check (version >= 1),
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  status text not null default 'editing'
    check (status in ('editing', 'submitted_for_approval')),
  submitted_by uuid references auth.users (id) on delete set null,
  submitted_at timestamptz,
  approval_note text check (char_length(approval_note) <= 1000)
);

alter table public.valuation_drafts enable row level security;
revoke all on public.valuation_drafts from anon, authenticated;

create table public.staff_audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_user_id uuid,
  actor_role text not null,
  action text not null check (action ~ '^[a-z][a-z_]{2,39}$'),
  -- No foreign key: the journal outlives purged accounts and dossiers.
  property_id uuid,
  target_type text check (char_length(target_type) <= 40),
  target_id text check (char_length(target_id) <= 100),
  details jsonb not null default '{}'
    check (jsonb_typeof(details) = 'object' and octet_length(details::text) <= 20000)
);

create index staff_audit_log_property on public.staff_audit_log (property_id, at desc);
create index staff_audit_log_actor on public.staff_audit_log (actor_user_id, at desc);
create index staff_audit_log_at on public.staff_audit_log (at desc);

comment on table public.staff_audit_log is
  'EPIC-12: append-only journal of the team''s actions (bo_* functions and '
  'staff_* runbook functions). Purge only with '
  'set_config(''realesty.audit_purge'', ''on'', true) in the SQL editor.';

alter table public.staff_audit_log enable row level security;
revoke all on public.staff_audit_log from anon, authenticated;

create function public.staff_audit_log_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('realesty.audit_purge', true), '') <> 'on' then
    raise exception 'staff_audit_log is append-only' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger staff_audit_log_append_only
  before update or delete on public.staff_audit_log
  for each row execute function public.staff_audit_log_append_only();

create trigger staff_audit_log_no_truncate
  before truncate on public.staff_audit_log
  for each statement execute function public.staff_audit_log_append_only();

revoke all on function public.staff_audit_log_append_only()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Role helpers
-- ---------------------------------------------------------------------------

-- Whether the caller's session passed MFA (TOTP).
create function public.bo_aal2()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

-- Active role of the caller with an MFA session, else null.
create function public.bo_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.staff_members m
  where m.user_id = auth.uid() and m.active and public.bo_aal2();
$$;

-- admin / expert: every sent dossier; partner_expert: dossiers assigned to
-- them (assignment not revoked); anyone else: none.
create function public.bo_can_access_property(p_property_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.bo_role();
begin
  if v_role is null then
    return false;
  end if;
  if v_role in ('admin', 'expert') then
    return exists (
      select 1 from public.properties p
      where p.id = p_property_id and p.status <> 'draft'
    );
  end if;
  return exists (
    select 1
    from public.dossier_assignments a
    join public.properties p on p.id = a.property_id
    where a.property_id = p_property_id
      and a.expert_user_id = auth.uid()
      and a.revoked_at is null
      and p.status <> 'draft'
  );
end;
$$;

revoke all on function public.bo_aal2() from public, anon;
revoke all on function public.bo_role() from public, anon;
revoke all on function public.bo_can_access_property(uuid) from public, anon;
grant execute on function public.bo_aal2() to authenticated;
grant execute on function public.bo_role() to authenticated;
grant execute on function public.bo_can_access_property(uuid) to authenticated;

-- Caller's role, or an error the back-office understands:
-- not_authenticated, not_staff, mfa_required, forbidden (all 42501).
create function public._bo_actor(p_roles text[])
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member public.staff_members;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_member from public.staff_members m
  where m.user_id = auth.uid() and m.active;
  if v_member.user_id is null then
    raise exception 'not_staff' using errcode = '42501';
  end if;
  if not public.bo_aal2() then
    raise exception 'mfa_required' using errcode = '42501';
  end if;
  if not (v_member.role = any (p_roles)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return v_member.role;
end;
$$;

-- Raises dossier_not_found (P0002) unless the caller may open the dossier.
create function public._bo_require_property(p_property_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_property_id is null or not public.bo_can_access_property(p_property_id) then
    raise exception 'dossier_not_found' using errcode = 'P0002';
  end if;
end;
$$;

-- Appends to the journal. Without a JWT (SQL editor, service role) the actor
-- is 'sql_editor'.
create function public._bo_log(
  p_action text,
  p_property_id uuid,
  p_target_type text default null,
  p_target_id text default null,
  p_details jsonb default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then
    v_role := 'sql_editor';
  else
    select m.role into v_role from public.staff_members m where m.user_id = v_uid;
    v_role := coalesce(v_role, 'unknown');
  end if;
  insert into public.staff_audit_log (
    actor_user_id, actor_role, action, property_id, target_type, target_id, details
  ) values (
    v_uid, v_role, p_action, p_property_id, p_target_type, p_target_id,
    coalesce(p_details, '{}')
  );
end;
$$;

-- staff_* functions log as 'sql_editor', except when a bo_* function calls
-- them (it logs its own line).
create function public._staff_log(
  p_action text,
  p_property_id uuid,
  p_target_type text default null,
  p_target_id text default null,
  p_details jsonb default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('realesty.bo_call', true), '') = 'on' then
    return;
  end if;
  perform public._bo_log(p_action, p_property_id, p_target_type, p_target_id, p_details);
end;
$$;

revoke all on function public._bo_actor(text[]) from public, anon, authenticated;
revoke all on function public._bo_require_property(uuid) from public, anon, authenticated;
revoke all on function public._bo_log(text, uuid, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public._staff_log(text, uuid, text, text, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. staff_* runbook functions: unchanged bodies, plus a journal line
--    (actor 'sql_editor'; silent when called by a bo_* function).
-- ---------------------------------------------------------------------------
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

  perform public._staff_log('review_started', p_property_id);
end;
$$;

create or replace function public.staff_certify_property(p_property_id uuid, p_valuation jsonb)
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

  perform public._staff_log(
    'certified', p_property_id, 'valuation', v_id::text,
    jsonb_build_object('value_eur', (p_valuation ->> 'value_eur')::integer)
  );

  return v_id;
end;
$$;

create or replace function public.staff_attach_valuation_report(p_valuation_id uuid, p_storage_path text, p_pages smallint)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_prefix text;
begin
  select p.owner_id::text || '/' || p.id::text || '/'
  into v_prefix
  from public.valuations v
  join public.properties p on p.id = v.property_id
  where v.id = p_valuation_id;

  if v_prefix is null then
    raise exception 'Valuation % not found', p_valuation_id
      using errcode = 'P0002';
  end if;

  if p_storage_path is null
    or left(p_storage_path, char_length(v_prefix)) <> v_prefix
    or char_length(p_storage_path) <= char_length(v_prefix) then
    raise exception 'The report path must start with %', v_prefix
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'valuation-reports' and o.name = p_storage_path
  ) then
    raise exception 'No file % in the valuation-reports bucket', p_storage_path
      using errcode = 'P0002';
  end if;

  update public.valuations
  set report_storage_path = p_storage_path, report_pages = p_pages
  where id = p_valuation_id;

  perform public._staff_log(
    'report_attached',
    (select v.property_id from public.valuations v where v.id = p_valuation_id),
    'valuation', p_valuation_id::text,
    jsonb_build_object('pages', p_pages)
  );
end;
$$;

create or replace function public.staff_verify_document(p_document_id uuid, p_verified_by uuid DEFAULT NULL::uuid, p_notify boolean DEFAULT false)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_document public.property_documents;
  v_owner uuid;
begin
  update public.property_documents
  set verified_at = now(),
      verified_by = p_verified_by,
      status = 'analyzed',
      rejected_reason = null
  where id = p_document_id
  returning * into v_document;

  if v_document.id is null then
    raise exception 'Document % not found', p_document_id
      using errcode = 'P0002';
  end if;

  if p_notify then
    select owner_id into v_owner
    from public.properties where id = v_document.property_id;
    insert into public.notifications (
      user_id, property_id, kind, title, body, route
    ) values (
      v_owner, v_document.property_id, 'document_verified',
      'Un document a été vérifié',
      coalesce(v_document.title, public.document_kind_label(v_document.kind))
        || ' a été vérifié par l’expert.',
      '/vendeur/coffre/biens/' || v_document.property_id
        || '?rubrique=' || public.vault_rubric_of(v_document.kind)
    );
  end if;

  perform public._staff_log(
    'document_verified', v_document.property_id, 'document', p_document_id::text,
    jsonb_build_object('kind', v_document.kind, 'notify', p_notify)
  );
end;
$$;

create or replace function public.staff_reject_document(p_document_id uuid, p_reason text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_document public.property_documents;
  v_owner uuid;
begin
  if p_reason is null or char_length(trim(p_reason)) not between 1 and 300 then
    raise exception 'A reason of 1 to 300 characters is required'
      using errcode = '22023';
  end if;

  update public.property_documents
  set status = 'rejected',
      rejected_reason = trim(p_reason),
      verified_at = null,
      verified_by = null
  where id = p_document_id
  returning * into v_document;

  if v_document.id is null then
    raise exception 'Document % not found', p_document_id
      using errcode = 'P0002';
  end if;

  select owner_id into v_owner
  from public.properties where id = v_document.property_id;
  insert into public.notifications (
    user_id, property_id, kind, title, body, route
  ) values (
    v_owner, v_document.property_id, 'document_rejected',
    'Un document est à remplacer',
    coalesce(v_document.title, public.document_kind_label(v_document.kind))
      || ' : ' || trim(p_reason),
    '/vendeur/coffre/biens/' || v_document.property_id
      || '?rubrique=' || public.vault_rubric_of(v_document.kind)
  );

  perform public._staff_log(
    'document_rejected', v_document.property_id, 'document', p_document_id::text,
    jsonb_build_object('kind', v_document.kind, 'reason', trim(p_reason))
  );
end;
$$;

create or replace function public.staff_verify_identity(p_property_owner_id uuid, p_staff_user_id uuid DEFAULT NULL::uuid)
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

  perform public._staff_log(
    'identity_verified', v_owner.property_id, 'property_owner',
    p_property_owner_id::text
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Valuation draft validation (pure). Mirrored by the Dart
--    `ValuationDraftValidator` (packages/backoffice_repository); parity
--    fixture: supabase/functions/tests/fixtures/valuation_drafts.json.
--    Returns a list of {"path", "code"}; an empty list means certifiable.
-- ---------------------------------------------------------------------------

-- One error, or none, for an integer value.
create function public._bo_v_int(
  p_path text, p_value jsonb, p_required boolean, p_min numeric, p_max numeric
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) = 'null' then
      case when p_required
        then jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'required'))
        else '[]'::jsonb end
    when jsonb_typeof(p_value) <> 'number'
      or (p_value::text)::numeric <> trunc((p_value::text)::numeric) then
      jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'not_integer'))
    when (p_value::text)::numeric < p_min or (p_value::text)::numeric > p_max then
      jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'out_of_range'))
    else '[]'::jsonb
  end;
$$;

-- One error, or none, for a number (decimals allowed).
create function public._bo_v_num(
  p_path text, p_value jsonb, p_required boolean, p_min numeric, p_max numeric
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) = 'null' then
      case when p_required
        then jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'required'))
        else '[]'::jsonb end
    when jsonb_typeof(p_value) <> 'number' then
      jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'not_number'))
    when (p_value::text)::numeric < p_min or (p_value::text)::numeric > p_max then
      jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'out_of_range'))
    else '[]'::jsonb
  end;
$$;

-- One error, or none, for a text. Blank texts count as absent.
create function public._bo_v_text(
  p_path text, p_value jsonb, p_required boolean, p_max integer
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) = 'null'
      or (jsonb_typeof(p_value) = 'string' and btrim(p_value #>> '{}') = '') then
      case when p_required
        then jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'required'))
        else '[]'::jsonb end
    when jsonb_typeof(p_value) <> 'string' then
      jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'not_text'))
    when char_length(p_value #>> '{}') > p_max then
      jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'too_long'))
    else '[]'::jsonb
  end;
$$;

create function public._bo_v_bool(p_path text, p_value jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) in ('null', 'boolean') then '[]'::jsonb
    else jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'not_bool'))
  end;
$$;

create function public._bo_v_choice(p_path text, p_value jsonb, p_choices text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null or jsonb_typeof(p_value) = 'null' then '[]'::jsonb
    when jsonb_typeof(p_value) = 'string' and (p_value #>> '{}') = any (p_choices)
      then '[]'::jsonb
    else jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'invalid_choice'))
  end;
$$;

-- A calendar date written YYYY-MM-DD.
create function public._bo_v_date(p_path text, p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text;
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return '[]';
  end if;
  v_text := p_value #>> '{}';
  if jsonb_typeof(p_value) = 'string' and v_text ~ '^\d{4}-\d{2}-\d{2}$' then
    begin
      if to_char(v_text::date, 'YYYY-MM-DD') = v_text then
        return '[]';
      end if;
    exception when others then
      null;
    end;
  end if;
  return jsonb_build_array(jsonb_build_object('path', p_path, 'code', 'invalid_date'));
end;
$$;

-- Keys of p_object that are not in p_allowed.
create function public._bo_v_keys(p_prefix text, p_object jsonb, p_allowed text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(jsonb_build_object('path', p_prefix || k, 'code', 'unknown_field') order by k),
    '[]'::jsonb
  )
  from jsonb_object_keys(p_object) k
  where not (k = any (p_allowed));
$$;

create function public._bo_valuation_errors(p_payload jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  p jsonb := coalesce(p_payload, '{}');
  e jsonb := '[]';
  v_list text;
  v_item jsonb;
  v_i integer;
  v_at text;
  v_lists constant text[] := array[
    'method_steps', 'reasons', 'delay_curve', 'technical_sheet', 'comparables',
    'competitors', 'adjustments', 'method_summary'
  ];
begin
  if jsonb_typeof(p) <> 'object' then
    return jsonb_build_array(jsonb_build_object('path', '', 'code', 'not_object'));
  end if;

  e := e || public._bo_v_keys('', p, array[
    'value_eur', 'low_eur', 'high_eur', 'price_m2_eur', 'estimated_delay_weeks',
    'valid_until', 'expert_user_id', 'expert_display_name', 'expert_initials',
    'method_steps', 'reasons', 'delay_curve', 'expert_quote', 'description',
    'technical_sheet', 'comparables', 'comparables_note', 'competitors_summary',
    'competitors', 'risks_note', 'adjustments', 'method_summary', 'works_label',
    'works_estimate_eur', 'sources'
  ]);

  e := e
    || public._bo_v_int('value_eur', p -> 'value_eur', true, 1000, 100000000)
    || public._bo_v_int('low_eur', p -> 'low_eur', true, 1000, 100000000)
    || public._bo_v_int('high_eur', p -> 'high_eur', true, 1000, 100000000)
    || public._bo_v_int('price_m2_eur', p -> 'price_m2_eur', false, 1, 1000000)
    || public._bo_v_int('estimated_delay_weeks', p -> 'estimated_delay_weeks', false, 1, 104)
    || public._bo_v_int('works_estimate_eur', p -> 'works_estimate_eur', false, 0, 100000000)
    || public._bo_v_date('valid_until', p -> 'valid_until')
    || public._bo_v_text('expert_display_name', p -> 'expert_display_name', false, 100)
    || public._bo_v_text('expert_initials', p -> 'expert_initials', false, 3)
    || public._bo_v_text('expert_quote', p -> 'expert_quote', false, 2000)
    || public._bo_v_text('description', p -> 'description', false, 4000)
    || public._bo_v_text('comparables_note', p -> 'comparables_note', false, 1000)
    || public._bo_v_text('competitors_summary', p -> 'competitors_summary', false, 500)
    || public._bo_v_text('risks_note', p -> 'risks_note', false, 1000)
    || public._bo_v_text('works_label', p -> 'works_label', false, 200)
    || public._bo_v_text('sources', p -> 'sources', false, 1000);

  if p ? 'expert_user_id' and jsonb_typeof(p -> 'expert_user_id') <> 'null' and not (
    jsonb_typeof(p -> 'expert_user_id') = 'string'
    and (p ->> 'expert_user_id')
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  ) then
    e := e || jsonb_build_array(jsonb_build_object('path', 'expert_user_id', 'code', 'invalid_uuid'));
  end if;

  if jsonb_typeof(p -> 'value_eur') = 'number'
    and jsonb_typeof(p -> 'low_eur') = 'number'
    and jsonb_typeof(p -> 'high_eur') = 'number'
    and not (
      (p ->> 'low_eur')::numeric <= (p ->> 'value_eur')::numeric
      and (p ->> 'value_eur')::numeric <= (p ->> 'high_eur')::numeric
    ) then
    e := e || jsonb_build_array(jsonb_build_object('path', 'value_eur', 'code', 'range_order'));
  end if;

  foreach v_list in array v_lists loop
    continue when not (p ? v_list) or jsonb_typeof(p -> v_list) = 'null';
    if jsonb_typeof(p -> v_list) <> 'array' then
      e := e || jsonb_build_array(jsonb_build_object('path', v_list, 'code', 'not_list'));
      continue;
    end if;
    if jsonb_array_length(p -> v_list) > 50 then
      e := e || jsonb_build_array(jsonb_build_object('path', v_list, 'code', 'too_many'));
      continue;
    end if;
    for v_i in 0 .. jsonb_array_length(p -> v_list) - 1 loop
      v_item := p -> v_list -> v_i;
      v_at := v_list || '[' || v_i || '].';
      if jsonb_typeof(v_item) <> 'object' then
        e := e || jsonb_build_array(jsonb_build_object(
          'path', v_list || '[' || v_i || ']', 'code', 'not_object'));
        continue;
      end if;
      case v_list
        when 'method_steps' then
          e := e || public._bo_v_keys(v_at, v_item, array['label', 'detail', 'amount_eur', 'is_delta'])
            || public._bo_v_text(v_at || 'label', v_item -> 'label', true, 120)
            || public._bo_v_text(v_at || 'detail', v_item -> 'detail', false, 200)
            || public._bo_v_int(v_at || 'amount_eur', v_item -> 'amount_eur', true, -100000000, 100000000)
            || public._bo_v_bool(v_at || 'is_delta', v_item -> 'is_delta');
        when 'reasons' then
          e := e || public._bo_v_keys(v_at, v_item, array['text', 'positive'])
            || public._bo_v_text(v_at || 'text', v_item -> 'text', true, 300)
            || public._bo_v_bool(v_at || 'positive', v_item -> 'positive');
        when 'delay_curve' then
          e := e || public._bo_v_keys(v_at, v_item, array['price_eur', 'label'])
            || public._bo_v_int(v_at || 'price_eur', v_item -> 'price_eur', true, 1000, 100000000)
            || public._bo_v_text(v_at || 'label', v_item -> 'label', true, 60);
        when 'technical_sheet' then
          e := e || public._bo_v_keys(v_at, v_item, array['label', 'value', 'provenance'])
            || public._bo_v_text(v_at || 'label', v_item -> 'label', true, 60)
            || public._bo_v_text(v_at || 'value', v_item -> 'value', true, 200)
            || public._bo_v_choice(v_at || 'provenance', v_item -> 'provenance',
              array['declared', 'document', 'external', 'verified']);
        when 'comparables' then
          e := e || public._bo_v_keys(v_at, v_item,
              array['street', 'sold_on', 'area_m2', 'land_m2', 'price_eur', 'excluded'])
            || public._bo_v_text(v_at || 'street', v_item -> 'street', true, 120)
            || public._bo_v_date(v_at || 'sold_on', v_item -> 'sold_on')
            || public._bo_v_num(v_at || 'area_m2', v_item -> 'area_m2', false, 1, 100000)
            || public._bo_v_int(v_at || 'land_m2', v_item -> 'land_m2', false, 0, 100000000)
            || public._bo_v_int(v_at || 'price_eur', v_item -> 'price_eur', true, 1000, 100000000)
            || public._bo_v_bool(v_at || 'excluded', v_item -> 'excluded');
          if jsonb_typeof(v_item -> 'street') = 'string'
            and btrim(v_item ->> 'street') ~ '^[0-9]' then
            e := e || jsonb_build_array(jsonb_build_object(
              'path', v_at || 'street', 'code', 'street_number'));
          end if;
        when 'competitors' then
          e := e || public._bo_v_keys(v_at, v_item,
              array['label', 'price_eur', 'note', 'days_online', 'retained'])
            || public._bo_v_text(v_at || 'label', v_item -> 'label', true, 120)
            || public._bo_v_int(v_at || 'price_eur', v_item -> 'price_eur', false, 1000, 100000000)
            || public._bo_v_text(v_at || 'note', v_item -> 'note', false, 300)
            || public._bo_v_int(v_at || 'days_online', v_item -> 'days_online', false, 0, 3650)
            || public._bo_v_bool(v_at || 'retained', v_item -> 'retained');
        else -- adjustments, method_summary
          e := e || public._bo_v_keys(v_at, v_item, array['label', 'amount_eur', 'kind'])
            || public._bo_v_text(v_at || 'label', v_item -> 'label', true, 200)
            || public._bo_v_int(v_at || 'amount_eur', v_item -> 'amount_eur', true, -100000000, 100000000)
            || public._bo_v_choice(v_at || 'kind', v_item -> 'kind',
              array['base', 'line', 'total', 'control']);
      end case;
    end loop;
  end loop;

  return e;
end;
$$;

revoke all on function public._bo_v_int(text, jsonb, boolean, numeric, numeric) from public, anon, authenticated;
revoke all on function public._bo_v_num(text, jsonb, boolean, numeric, numeric) from public, anon, authenticated;
revoke all on function public._bo_v_text(text, jsonb, boolean, integer) from public, anon, authenticated;
revoke all on function public._bo_v_bool(text, jsonb) from public, anon, authenticated;
revoke all on function public._bo_v_choice(text, jsonb, text[]) from public, anon, authenticated;
revoke all on function public._bo_v_date(text, jsonb) from public, anon, authenticated;
revoke all on function public._bo_v_keys(text, jsonb, text[]) from public, anon, authenticated;
revoke all on function public._bo_valuation_errors(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Back-office RPCs: reads
-- ---------------------------------------------------------------------------

create function public._bo_initials(p_first text, p_last text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(
    upper(left(btrim(coalesce(p_first, '')), 1) || left(btrim(coalesce(p_last, '')), 1)),
    ''
  );
$$;

create function public._bo_like(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select replace(replace(replace(btrim(p_text), '\', '\\'), '%', '\%'), '_', '\_');
$$;

revoke all on function public._bo_initials(text, text) from public, anon, authenticated;
revoke all on function public._bo_like(text) from public, anon, authenticated;

-- The caller: role (null when not an active member), MFA state and the
-- actions the back-office may show. Works without MFA (the app needs it to
-- ask for the code).
create function public.bo_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_member public.staff_members;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_member from public.staff_members m
  where m.user_id = auth.uid() and m.active;
  return jsonb_build_object(
    'user_id', auth.uid(),
    'email', (select u.email from auth.users u where u.id = auth.uid()),
    'role', v_member.role,
    'display_name', v_member.display_name,
    'initials', v_member.initials,
    'organisation', v_member.organisation,
    'aal2', public.bo_aal2(),
    'capabilities', to_jsonb(case v_member.role
      when 'admin' then array[
        'queue_all', 'assign', 'take', 'start_review', 'edit_draft', 'certify',
        'attach_report', 'verify_documents', 'identity_documents',
        'verify_identity', 'team', 'audit_all']
      when 'expert' then array[
        'queue_all', 'take', 'start_review', 'edit_draft', 'certify',
        'attach_report', 'verify_documents', 'identity_documents',
        'verify_identity']
      when 'partner_expert' then array[
        'start_review', 'edit_draft', 'submit_for_approval', 'verify_documents']
      else array[]::text[]
    end)
  );
end;
$$;

-- The queue. p_scope: 'all', 'mine' (assigned to me) or 'unassigned'.
-- Partners only ever see the dossiers assigned to them. Oldest first.
create function public.bo_list_dossiers(
  p_statuses text[] default null,
  p_scope text default 'all',
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
  v_partner boolean := v_role = 'partner_expert';
  v_search text := nullif(public._bo_like(coalesce(p_search, '')), '');
begin
  if coalesce(p_scope, 'all') not in ('all', 'mine', 'unassigned') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(s.row order by s.submitted_at nulls last, s.id)
    from (
      select p.id, p.submitted_at, jsonb_build_object(
        'id', p.id,
        'status', p.status,
        'property_type', p.property_type,
        'property_type_other', p.property_type_other,
        'city', p.address_city,
        'postcode', p.address_postcode,
        'living_area_m2', p.living_area_m2,
        'usable_area_m2', p.usable_area_m2,
        'submitted_at', p.submitted_at,
        'owner_initials', coalesce(
          (select public._bo_initials(o.first_name, o.last_name)
           from public.property_owners o where o.property_id = p.id
           order by o.position limit 1),
          public._bo_initials(pr.first_name, pr.last_name)),
        'owner_deactivated', pr.deactivated_at is not null,
        'lot', case when l.id is null then null else jsonb_build_object(
          'id', l.id, 'name', l.name, 'sale_mode', l.sale_mode,
          'main_property_id', l.main_property_id) end,
        'assigned_to', case when a.id is null then null else jsonb_build_object(
          'user_id', a.expert_user_id, 'display_name', sm.display_name,
          'initials', sm.initials) end,
        'documents_to_verify', (
          select count(*) from public.property_documents d
          where d.property_id = p.id and d.verified_at is null
            and d.status <> 'rejected' and d.replaced_by is null
            and not (v_partner and d.kind = 'piece_identite')),
        'documents_added_after', (
          select count(*) from public.property_documents d
          where d.property_id = p.id and d.added_after_submission
            and d.verified_at is null and d.status <> 'rejected'
            and d.replaced_by is null
            and not (v_partner and d.kind = 'piece_identite')),
        'photos_count', (
          select count(*) from public.room_photos ph where ph.property_id = p.id),
        'has_voice', exists (
          select 1 from public.agent_sessions s2 where s2.property_id = p.id),
        'draft', case when dr.property_id is null then null else jsonb_build_object(
          'status', dr.status, 'version', dr.version, 'updated_at', dr.updated_at) end
      ) as row
      from public.properties p
      left join public.dossier_assignments a
        on a.property_id = p.id and a.revoked_at is null
      left join public.staff_members sm on sm.user_id = a.expert_user_id
      left join public.property_lots l on l.id = p.lot_id
      left join public.valuation_drafts dr on dr.property_id = p.id
      left join public.profiles pr on pr.id = p.owner_id
      where p.status <> 'draft'
        and (p_statuses is null or p.status = any (p_statuses))
        and (not v_partner or a.expert_user_id = auth.uid())
        and (
          coalesce(p_scope, 'all') = 'all'
          or (p_scope = 'mine' and a.expert_user_id = auth.uid())
          or (p_scope = 'unassigned' and a.id is null)
        )
        and (
          v_search is null
          or p.address_city ilike '%' || v_search || '%'
          or p.address_postcode like v_search || '%'
          or p.id::text like lower(v_search) || '%'
          or l.name ilike '%' || v_search || '%'
        )
      order by p.submitted_at nulls last, p.id
      limit least(greatest(coalesce(p_limit, 100), 1), 200)
      offset greatest(coalesce(p_offset, 0), 0)
    ) s
  ), '[]'::jsonb);
end;
$$;

-- One dossier, shaped by role (partners: owners reduced to initials and
-- commune, no identity document, no seller contact). Journals
-- 'dossier_opened'. No storage path is returned: files go through bo-files.
create function public.bo_get_dossier(p_property_id uuid)
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
    'property', case when v_partner then to_jsonb(v_p) - 'owner_id' else to_jsonb(v_p) end,
    'seller', (
      select case when v_partner then jsonb_build_object(
          'initials', public._bo_initials(pr.first_name, pr.last_name),
          'city', v_p.address_city,
          'deactivated', pr.deactivated_at is not null)
        else jsonb_build_object(
          'user_id', pr.id, 'first_name', pr.first_name, 'last_name', pr.last_name,
          'phone', pr.phone, 'email', u.email,
          'deactivated', pr.deactivated_at is not null,
          'deletion_due_at', pr.deletion_due_at)
        end
      from public.profiles pr
      left join auth.users u on u.id = pr.id
      where pr.id = v_p.owner_id),
    'owners', coalesce((
      select jsonb_agg(case when v_partner then jsonb_build_object(
          'id', o.id, 'position', o.position,
          'initials', public._bo_initials(o.first_name, o.last_name),
          'city', v_p.address_city,
          'identity_verified_at', o.identity_verified_at)
        else jsonb_build_object(
          'id', o.id, 'position', o.position, 'first_name', o.first_name,
          'last_name', o.last_name, 'phone', o.phone, 'email', o.email,
          'identity_verified_at', o.identity_verified_at)
        end order by o.position)
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
      where d.property_id = p_property_id
        and not (v_partner and d.kind = 'piece_identite')), '[]'),
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

  perform public._bo_log('dossier_opened', p_property_id);
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Back-office RPCs: assignment and review
-- ---------------------------------------------------------------------------

-- Admin: give a sent dossier to a team member (replaces the current one).
create function public.bo_assign(
  p_property_id uuid, p_expert_user_id uuid, p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous uuid;
begin
  perform public._bo_actor(array['admin']);
  perform public._bo_require_property(p_property_id);
  if not exists (
    select 1 from public.properties p
    where p.id = p_property_id and p.status in ('submitted', 'in_review')
  ) then
    raise exception 'dossier_closed' using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.staff_members m
    where m.user_id = p_expert_user_id and m.active
  ) then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  update public.dossier_assignments
  set revoked_at = now()
  where property_id = p_property_id and revoked_at is null
  returning expert_user_id into v_previous;
  insert into public.dossier_assignments (property_id, expert_user_id, assigned_by, note)
  values (p_property_id, p_expert_user_id, auth.uid(), nullif(btrim(p_note), ''));
  perform public._bo_log('assigned', p_property_id, 'staff_member', p_expert_user_id::text,
    jsonb_build_object('previous', v_previous));
end;
$$;

create function public.bo_unassign(p_property_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous uuid;
begin
  perform public._bo_actor(array['admin']);
  perform public._bo_require_property(p_property_id);
  update public.dossier_assignments
  set revoked_at = now()
  where property_id = p_property_id and revoked_at is null
  returning expert_user_id into v_previous;
  if v_previous is null then
    raise exception 'not_assigned' using errcode = 'P0002';
  end if;
  perform public._bo_log('unassigned', p_property_id, 'staff_member', v_previous::text);
end;
$$;

-- « Prendre en charge »: submitted → in_review, seller notified. An admin or
-- expert taking an unassigned dossier becomes its assignee (Q11 a).
create function public.bo_start_review(p_property_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
begin
  perform public._bo_require_property(p_property_id);
  if not exists (
    select 1 from public.properties p
    where p.id = p_property_id and p.status = 'submitted'
  ) then
    raise exception 'not_submitted' using errcode = '55000';
  end if;
  if v_role in ('admin', 'expert') and not exists (
    select 1 from public.dossier_assignments a
    where a.property_id = p_property_id and a.revoked_at is null
  ) then
    insert into public.dossier_assignments (property_id, expert_user_id, assigned_by)
    values (p_property_id, auth.uid(), auth.uid());
    perform public._bo_log('assigned', p_property_id, 'staff_member', auth.uid()::text,
      jsonb_build_object('self', true));
  end if;
  perform set_config('realesty.bo_call', 'on', true);
  perform public.staff_start_review(p_property_id);
  perform set_config('realesty.bo_call', '', true);
  perform public._bo_log('review_started', p_property_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Back-office RPCs: valuation draft and certification
-- ---------------------------------------------------------------------------

-- Saves the draft (optimistic lock). p_expected_version: 0 or null for the
-- first save, else the version read. Returns the new version.
-- Errors: draft_conflict (40001), draft_submitted / dossier_closed (55000).
create function public.bo_save_draft(
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
begin
  perform public._bo_require_property(p_property_id);
  if not exists (
    select 1 from public.properties p
    where p.id = p_property_id and p.status in ('submitted', 'in_review')
  ) then
    raise exception 'dossier_closed' using errcode = '55000';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_payload' using errcode = '22023';
  end if;

  select * into v_draft from public.valuation_drafts d
  where d.property_id = p_property_id for update;

  if v_draft.property_id is null then
    if coalesce(p_expected_version, 0) <> 0 then
      raise exception 'draft_conflict' using errcode = '40001';
    end if;
    insert into public.valuation_drafts (property_id, payload, updated_by)
    values (p_property_id, p_payload, auth.uid())
    on conflict (property_id) do nothing
    returning version into v_version;
    if v_version is null then
      raise exception 'draft_conflict' using errcode = '40001';
    end if;
  else
    if p_expected_version is distinct from v_draft.version then
      raise exception 'draft_conflict' using errcode = '40001',
        detail = coalesce((select m.display_name from public.staff_members m
          where m.user_id = v_draft.updated_by), '');
    end if;
    if v_role = 'partner_expert' and v_draft.status = 'submitted_for_approval' then
      raise exception 'draft_submitted' using errcode = '55000';
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

-- Errors of the saved draft (same rules as the Dart validator), without
-- writing anything.
create function public.bo_validate_draft(p_property_id uuid)
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
    raise exception 'draft_not_found' using errcode = 'P0002';
  end if;
  return public._bo_valuation_errors(v_payload);
end;
$$;

-- Same rules on any payload (used by the parity test and the form).
create function public.bo_validate_payload(p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._bo_actor(array['admin', 'expert', 'partner_expert']);
  return public._bo_valuation_errors(p_payload);
end;
$$;

-- Locks the draft at the expected version and checks it is certifiable.
create function public._bo_lock_valid_draft(
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
    raise exception 'draft_not_found' using errcode = 'P0002';
  end if;
  if p_expected_version is distinct from v_draft.version then
    raise exception 'draft_conflict' using errcode = '40001';
  end if;
  v_errors := public._bo_valuation_errors(v_draft.payload);
  if jsonb_array_length(v_errors) > 0 then
    raise exception 'draft_invalid' using errcode = '22023', detail = v_errors::text;
  end if;
  return v_draft;
end;
$$;

revoke all on function public._bo_lock_valid_draft(uuid, integer)
  from public, anon, authenticated;

-- Partner: hands the draft to an expert or the admin for certification.
create function public.bo_submit_for_approval(
  p_property_id uuid, p_expected_version integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._bo_actor(array['partner_expert']);
  perform public._bo_require_property(p_property_id);
  perform public._bo_lock_valid_draft(p_property_id, p_expected_version);
  update public.valuation_drafts
  set status = 'submitted_for_approval', submitted_by = auth.uid(),
      submitted_at = now(), approval_note = null
  where property_id = p_property_id;
  perform public._bo_log('submitted_for_approval', p_property_id, 'valuation_draft',
    p_property_id::text, jsonb_build_object('version', p_expected_version));
end;
$$;

-- Expert / admin: sends a submitted draft back to its author with a note.
create function public.bo_return_draft(p_property_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._bo_actor(array['admin', 'expert']);
  perform public._bo_require_property(p_property_id);
  if p_note is null or char_length(btrim(p_note)) not between 1 and 1000 then
    raise exception 'note_required' using errcode = '22023';
  end if;
  update public.valuation_drafts
  set status = 'editing', approval_note = btrim(p_note)
  where property_id = p_property_id and status = 'submitted_for_approval';
  if not found then
    raise exception 'draft_not_submitted' using errcode = '55000';
  end if;
  perform public._bo_log('draft_returned', p_property_id, 'valuation_draft',
    p_property_id::text, jsonb_build_object('note', btrim(p_note)));
end;
$$;

-- Expert / admin: certifies the draft (status certified, seller notified,
-- draft deleted). Signatory: expert_user_id of the draft, else the partner
-- who submitted it, else the caller; name and initials default to theirs.
create function public.bo_certify(p_property_id uuid, p_expected_version integer)
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
  select * into v_member from public.staff_members m where m.user_id = v_signer;
  if v_member.user_id is null then
    raise exception 'invalid_signatory' using errcode = '22023';
  end if;
  v_payload := v_payload || jsonb_build_object(
    'expert_user_id', v_signer,
    'expert_display_name', coalesce(v_payload ->> 'expert_display_name', v_member.display_name),
    'expert_initials', coalesce(v_payload ->> 'expert_initials', v_member.initials));

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

-- Expert / admin: the path for the PDF of the latest valuation (bo-files
-- signs an upload URL to it).
create function public.bo_prepare_report_upload(p_property_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_valuation uuid;
begin
  perform public._bo_actor(array['admin', 'expert']);
  perform public._bo_require_property(p_property_id);
  select p.owner_id into v_owner from public.properties p where p.id = p_property_id;
  select v.id into v_valuation from public.valuations v
  where v.property_id = p_property_id order by v.certified_at desc limit 1;
  if v_valuation is null then
    raise exception 'not_certified' using errcode = '55000';
  end if;
  perform public._bo_log('report_upload_signed', p_property_id, 'valuation',
    v_valuation::text);
  return jsonb_build_object(
    'bucket', 'valuation-reports',
    'path', v_owner::text || '/' || p_property_id::text || '/avis-de-valeur-'
      || to_char(now() at time zone 'Europe/Paris', 'YYYYMMDD-HH24MISS') || '.pdf',
    'valuation_id', v_valuation);
end;
$$;

-- Expert / admin: links the uploaded PDF to the latest valuation.
create function public.bo_attach_report(
  p_property_id uuid, p_storage_path text, p_pages smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_valuation uuid;
begin
  perform public._bo_actor(array['admin', 'expert']);
  perform public._bo_require_property(p_property_id);
  select v.id into v_valuation from public.valuations v
  where v.property_id = p_property_id order by v.certified_at desc limit 1;
  if v_valuation is null then
    raise exception 'not_certified' using errcode = '55000';
  end if;
  perform set_config('realesty.bo_call', 'on', true);
  perform public.staff_attach_valuation_report(v_valuation, p_storage_path, p_pages);
  perform set_config('realesty.bo_call', '', true);
  perform public._bo_log('report_attached', p_property_id, 'valuation', v_valuation::text,
    jsonb_build_object('pages', p_pages));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Back-office RPCs: documents and identity
-- ---------------------------------------------------------------------------

-- The dossier of a document the caller may act on (partners: never an
-- identity document).
create function public._bo_document_property(p_document_id uuid, p_role text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_document public.property_documents;
begin
  select * into v_document from public.property_documents d where d.id = p_document_id;
  if v_document.id is null or not public.bo_can_access_property(v_document.property_id) then
    raise exception 'document_not_found' using errcode = 'P0002';
  end if;
  if p_role = 'partner_expert' and v_document.kind = 'piece_identite' then
    raise exception 'identity_document_forbidden' using errcode = '42501';
  end if;
  return v_document.property_id;
end;
$$;

revoke all on function public._bo_document_property(uuid, text)
  from public, anon, authenticated;

create function public.bo_verify_document(p_document_id uuid, p_notify boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
  v_property uuid := public._bo_document_property(p_document_id, v_role);
begin
  perform set_config('realesty.bo_call', 'on', true);
  perform public.staff_verify_document(p_document_id, auth.uid(), coalesce(p_notify, false));
  perform set_config('realesty.bo_call', '', true);
  perform public._bo_log('document_verified', v_property, 'document', p_document_id::text,
    jsonb_build_object('notify', coalesce(p_notify, false)));
end;
$$;

create function public.bo_reject_document(p_document_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
  v_property uuid := public._bo_document_property(p_document_id, v_role);
begin
  perform set_config('realesty.bo_call', 'on', true);
  perform public.staff_reject_document(p_document_id, p_reason);
  perform set_config('realesty.bo_call', '', true);
  perform public._bo_log('document_rejected', v_property, 'document', p_document_id::text,
    jsonb_build_object('reason', btrim(p_reason)));
end;
$$;

-- Expert / admin: identity of a co-owner checked (EPIC-08, unlocks the
-- « L'Expert » mandate).
create function public.bo_verify_identity(p_property_owner_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_property uuid;
begin
  perform public._bo_actor(array['admin', 'expert']);
  select o.property_id into v_property from public.property_owners o
  where o.id = p_property_owner_id;
  if v_property is null or not public.bo_can_access_property(v_property) then
    raise exception 'owner_not_found' using errcode = 'P0002';
  end if;
  perform set_config('realesty.bo_call', 'on', true);
  perform public.staff_verify_identity(p_property_owner_id, auth.uid());
  perform set_config('realesty.bo_call', '', true);
  perform public._bo_log('identity_verified', v_property, 'property_owner',
    p_property_owner_id::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Back-office RPCs: team (admin)
-- ---------------------------------------------------------------------------

create function public.bo_list_team()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public._bo_actor(array['admin']);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id, 'email', u.email, 'role', m.role,
        'display_name', m.display_name, 'initials', m.initials,
        'organisation', m.organisation, 'active', m.active,
        'created_at', m.created_at, 'deactivated_at', m.deactivated_at,
        'mfa_enrolled', exists (
          select 1 from auth.mfa_factors f
          where f.user_id = m.user_id and f.status = 'verified'),
        'active_assignments', (
          select count(*) from public.dossier_assignments a
          join public.properties p on p.id = a.property_id
          where a.expert_user_id = m.user_id and a.revoked_at is null
            and p.status in ('submitted', 'in_review')))
      order by m.active desc, m.display_name)
    from public.staff_members m
    left join auth.users u on u.id = m.user_id), '[]'::jsonb);
end;
$$;

-- Adds (or updates and reactivates) a member from the e-mail of an existing
-- user (they sign in once with a magic link first).
create function public.bo_upsert_member(
  p_email text,
  p_role text,
  p_display_name text,
  p_initials text,
  p_organisation text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_existed boolean;
begin
  perform public._bo_actor(array['admin']);
  select u.id into v_user from auth.users u
  where lower(u.email) = lower(btrim(p_email)) and u.deleted_at is null;
  if v_user is null then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  if v_user = auth.uid() and p_role <> 'admin' then
    raise exception 'cannot_demote_self' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('admin', 'expert', 'partner_expert') then
    raise exception 'invalid_role' using errcode = '22023';
  end if;
  v_existed := exists (select 1 from public.staff_members m where m.user_id = v_user);
  insert into public.staff_members (
    user_id, role, display_name, initials, organisation, created_by
  ) values (
    v_user, p_role, btrim(p_display_name), upper(btrim(p_initials)),
    nullif(btrim(p_organisation), ''), auth.uid()
  )
  on conflict (user_id) do update
  set role = excluded.role,
      display_name = excluded.display_name,
      initials = excluded.initials,
      organisation = excluded.organisation,
      active = true,
      deactivated_at = null;
  perform public._bo_log(
    case when v_existed then 'member_updated' else 'member_added' end,
    null, 'staff_member', v_user::text,
    jsonb_build_object('role', p_role, 'organisation', nullif(btrim(p_organisation), '')));
  return v_user;
end;
$$;

-- Removes an access at once (their assignments go back to the queue).
create function public.bo_deactivate_member(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._bo_actor(array['admin']);
  if p_user_id = auth.uid() then
    raise exception 'cannot_deactivate_self' using errcode = '42501';
  end if;
  update public.staff_members
  set active = false, deactivated_at = now()
  where user_id = p_user_id and active;
  if not found then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  update public.dossier_assignments
  set revoked_at = now()
  where expert_user_id = p_user_id and revoked_at is null;
  perform public._bo_log('member_deactivated', null, 'staff_member', p_user_id::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Back-office RPCs: journal and files
-- ---------------------------------------------------------------------------

-- Admin: the whole journal (filters optional); others: their own actions.
create function public.bo_audit(
  p_property_id uuid default null,
  p_actor uuid default null,
  p_action text default null,
  p_since timestamptz default null,
  p_until timestamptz default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
  v_actor uuid := case when v_role = 'admin' then p_actor else auth.uid() end;
begin
  return coalesce((
    select jsonb_agg(s.row order by s.at desc, s.id desc)
    from (
      select l.id, l.at, jsonb_build_object(
        'id', l.id, 'at', l.at, 'actor_user_id', l.actor_user_id,
        'actor_role', l.actor_role,
        'actor_name', coalesce(m.display_name,
          case when l.actor_role = 'sql_editor' then 'SQL' end),
        'action', l.action, 'property_id', l.property_id,
        'target_type', l.target_type, 'target_id', l.target_id,
        'details', l.details) as row
      from public.staff_audit_log l
      left join public.staff_members m on m.user_id = l.actor_user_id
      where (p_property_id is null or l.property_id = p_property_id)
        and (v_actor is null or l.actor_user_id = v_actor)
        and (p_action is null or l.action = p_action)
        and (p_since is null or l.at >= p_since)
        and (p_until is null or l.at < p_until)
      order by l.at desc, l.id desc
      limit least(greatest(coalesce(p_limit, 200), 1), 5000)
      offset greatest(coalesce(p_offset, 0), 0)
    ) s
  ), '[]'::jsonb);
end;
$$;

-- Called by the bo-files Edge Function with the caller's JWT: checks each
-- requested file belongs to the dossier and may be opened by the caller,
-- journals 'file_signed' and returns the storage locations to sign.
-- p_items: [{"type": "document" | "photo" | "report", "id": uuid}], 1 to 60.
create function public.bo_check_files(p_property_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public._bo_actor(array['admin', 'expert', 'partner_expert']);
  v_item jsonb;
  v_type text;
  v_id uuid;
  v_row jsonb;
  v_result jsonb := '[]';
begin
  perform public._bo_require_property(p_property_id);
  if p_items is null or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) not between 1 and 60 then
    raise exception 'invalid_items' using errcode = '22023';
  end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_type := v_item ->> 'type';
    begin
      v_id := (v_item ->> 'id')::uuid;
    exception when others then
      raise exception 'invalid_items' using errcode = '22023';
    end;
    v_row := null;
    if v_type = 'document' then
      select jsonb_build_object(
          'type', v_type, 'id', d.id, 'bucket', 'property-documents',
          'path', d.storage_path, 'file_name', d.file_name, 'mime_type', d.mime_type,
          'kind', d.kind)
        into v_row
      from public.property_documents d
      where d.id = v_id and d.property_id = p_property_id;
      if v_row is not null and v_role = 'partner_expert'
        and v_row ->> 'kind' = 'piece_identite' then
        raise exception 'identity_document_forbidden' using errcode = '42501';
      end if;
    elsif v_type = 'photo' then
      select jsonb_build_object(
          'type', v_type, 'id', ph.id, 'bucket', 'property-documents',
          'path', ph.storage_path, 'file_name', ph.id::text || '.jpg',
          'mime_type', 'image/jpeg')
        into v_row
      from public.room_photos ph
      where ph.id = v_id and ph.property_id = p_property_id;
    elsif v_type = 'report' then
      select jsonb_build_object(
          'type', v_type, 'id', v.id, 'bucket', 'valuation-reports',
          'path', v.report_storage_path, 'file_name', 'avis-de-valeur.pdf',
          'mime_type', 'application/pdf')
        into v_row
      from public.valuations v
      where v.id = v_id and v.property_id = p_property_id
        and v.report_storage_path is not null;
    else
      raise exception 'invalid_items' using errcode = '22023';
    end if;
    if v_row is null then
      raise exception 'file_not_found' using errcode = 'P0002';
    end if;
    v_result := v_result || jsonb_build_array(v_row);
  end loop;

  perform public._bo_log('file_signed', p_property_id, 'files', null,
    jsonb_build_object('items', (
      select jsonb_agg(jsonb_build_object('type', r ->> 'type', 'id', r ->> 'id'))
      from jsonb_array_elements(v_result) r)));
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Grants: the bo_* RPCs are callable by signed-in users (each checks the
--     role and MFA itself); nothing for anon.
-- ---------------------------------------------------------------------------

do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'bo\_%'
      and p.proname not in ('bo_aal2', 'bo_role', 'bo_can_access_property')
  loop
    execute format('revoke all on function %s from public, anon', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end;
$$;
