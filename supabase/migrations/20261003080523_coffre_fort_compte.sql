-- EPIC-11 · Coffre-fort & compte (plan docs/plans/2026-10-03-coffre-fort-et-compte.md).
--
-- 1. property_documents: new kinds, seller title, owner of an identity
--    document, sharing preference (visibility), "added after sending",
--    expert verification / rejection, replacement of a rejected document.
--    After sending (owner decision 2026-10-03): documents can be ADDED
--    freely to a dossier in review / certified (flagged "Ajouté après
--    l'envoi"); only those additions, while not verified, can be deleted;
--    the documents present when the dossier was sent stay locked.
-- 2. Storage property-documents: insert into a locked dossier folder (never
--    into photos/, never overwriting), delete of unreferenced files only.
-- 3. notifications.kind: format check (idempotent, same statement in the
--    sibling epics EPIC-08 / EPIC-12) + document_rejected / _verified.
-- 4. staff_verify_document / staff_reject_document (SQL editor until
--    EPIC-12).
-- 5. profiles: last name, phone, postal address, language; account
--    deactivation (owner decision 2026-10-03: immediate deactivation, then
--    definitive deletion after 30 days, reactivation possible meanwhile).
-- 6. account_deletions journal + purge helpers (service role) + daily
--    pg_cron job calling the Edge Function purge-accounts through pg_net
--    (runbook docs/runbooks/suppression-de-compte.md).

-- ---------------------------------------------------------------------------
-- 1. property_documents
-- ---------------------------------------------------------------------------

alter table public.property_documents
  drop constraint if exists property_documents_kind_check;
alter table public.property_documents
  add constraint property_documents_kind_check check (kind in (
    'titre_propriete', 'taxe_fonciere', 'facture_energie', 'facture_travaux',
    'piece_identite', 'diagnostics', 'rapport_spanc', 'plan', 'autre',
    'dpe', 'contrat_entretien', 'assurance', 'copropriete'
  ));

alter table public.property_documents
  add column title text check (char_length(title) between 1 and 120),
  add column owner_ref uuid
    references public.property_owners (id) on delete set null,
  add column visibility text[] not null default '{}',
  add column added_after_submission boolean not null default false,
  add column verified_at timestamptz,
  add column verified_by uuid references auth.users (id) on delete set null,
  add column rejected_reason text check (char_length(rejected_reason) <= 300),
  add column replaced_by uuid
    references public.property_documents (id) on delete set null;

-- Who may see the document once buyers and notaries use Realesty. An
-- identity document is never shared.
alter table public.property_documents
  add constraint property_documents_visibility_check check (
    visibility <@ array['buyers', 'notary']::text[]
    and (kind <> 'piece_identite' or visibility = '{}')
  );

create index property_documents_owner_ref_idx
  on public.property_documents (owner_ref) where owner_ref is not null;
create index property_documents_replaced_by_idx
  on public.property_documents (replaced_by) where replaced_by is not null;

comment on column public.property_documents.title is
  'Label chosen by the seller (else the label of the kind).';
comment on column public.property_documents.owner_ref is
  'Owner an identity document belongs to.';
comment on column public.property_documents.visibility is
  'Sharing preference (buyers, notary); set through set_document_visibility.';
comment on column public.property_documents.added_after_submission is
  'Added once the dossier was sent ("Ajouté après l''envoi"); set by trigger.';
comment on column public.property_documents.replaced_by is
  'The document that replaces this one (rejected or unverified addition).';

-- The seller may now also write the title and the owner of an identity
-- document; visibility, verification and replacement are server-side.
grant insert (title, owner_ref) on table public.property_documents
  to authenticated;
grant update (title, owner_ref) on table public.property_documents
  to authenticated;

-- Flags additions to a sent dossier, never shares an identity document,
-- keeps the documents of the dossier as sent unchanged (only their title,
-- a label of the seller, may change) and checks the owner of an identity
-- document belongs to the same property.
create function public.property_documents_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.properties
  where id = new.property_id;

  if tg_op = 'INSERT' then
    new.added_after_submission := coalesce(v_status, 'draft') <> 'draft';
    if new.kind = 'piece_identite' then
      new.visibility := '{}';
    end if;
  elsif auth.uid() is not null
    and v_status in ('in_review', 'certified')
    and not old.added_after_submission
    and (
      new.kind is distinct from old.kind
      or new.file_name is distinct from old.file_name
      or new.owner_ref is distinct from old.owner_ref
    ) then
    raise exception 'document_locked' using errcode = '42501';
  end if;

  if new.owner_ref is not null
    and (tg_op = 'INSERT' or new.owner_ref is distinct from old.owner_ref)
    and not exists (
      select 1 from public.property_owners o
      where o.id = new.owner_ref and o.property_id = new.property_id
    ) then
    raise exception 'owner_ref must be an owner of the same property'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke execute on function public.property_documents_before_write()
  from public, anon, authenticated;

create trigger property_documents_before_write
  before insert or update on public.property_documents
  for each row execute function public.property_documents_before_write();

-- Documents added to a dossier in review / certified.
create policy "Owners can add documents to their sent properties"
  on public.property_documents for insert
  to authenticated
  with check (
    exists (
      select 1 from public.properties p
      where p.id = property_id
        and p.owner_id = (select auth.uid())
        and p.status in ('in_review', 'certified')
    )
  );

-- Their title (and, for the additions, kind / owner: see the trigger).
create policy "Owners can rename documents of their sent properties"
  on public.property_documents for update
  to authenticated
  using (
    exists (
      select 1 from public.properties p
      where p.id = property_id
        and p.owner_id = (select auth.uid())
        and p.status in ('in_review', 'certified')
    )
  )
  with check (
    exists (
      select 1 from public.properties p
      where p.id = property_id
        and p.owner_id = (select auth.uid())
        and p.status in ('in_review', 'certified')
    )
  );

-- Only the additions the expert has not verified can be deleted.
create policy "Owners can delete their unverified additions"
  on public.property_documents for delete
  to authenticated
  using (
    added_after_submission
    and verified_at is null
    and exists (
      select 1 from public.properties p
      where p.id = property_id
        and p.owner_id = (select auth.uid())
        and p.status in ('in_review', 'certified')
    )
  );

-- Every document row points into the folder of its own property.
create policy "Documents are stored in their property folder"
  on public.property_documents as restrictive for insert
  to authenticated
  with check (
    storage_path like
      (select auth.uid())::text || '/' || property_id::text || '/%'
  );

-- set_document_visibility ---------------------------------------------------

create function public.set_document_visibility(
  p_document_id uuid,
  p_visibility text[]
)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_visibility text[] := coalesce(
    (select array_agg(distinct v order by v) from unnest(p_visibility) v),
    '{}'
  );
begin
  select d.kind into v_kind
  from public.property_documents d
  join public.properties p on p.id = d.property_id
  where d.id = p_document_id and p.owner_id = auth.uid();

  if v_kind is null then
    raise exception 'document_not_found' using errcode = 'P0002';
  end if;
  if not v_visibility <@ array['buyers', 'notary']::text[] then
    raise exception 'invalid_visibility' using errcode = '22023';
  end if;
  if v_kind = 'piece_identite' and v_visibility <> '{}' then
    raise exception 'identity_private' using errcode = '22023';
  end if;

  update public.property_documents
  set visibility = v_visibility
  where id = p_document_id;
  return v_visibility;
end;
$$;

revoke all on function public.set_document_visibility(uuid, text[])
  from public, anon;
grant execute on function public.set_document_visibility(uuid, text[])
  to authenticated;

-- replace_document ----------------------------------------------------------

-- Records that p_new_id (already added) replaces p_old_id: a rejected
-- document, or an addition not verified yet. The old row stays (the expert
-- sees it crossed out); the app deletes an unverified addition afterwards.
create function public.replace_document(p_old_id uuid, p_new_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.property_documents;
  v_new_property uuid;
begin
  select d.* into v_old
  from public.property_documents d
  join public.properties p on p.id = d.property_id
  where d.id = p_old_id and p.owner_id = auth.uid()
  for update of d;

  select d.property_id into v_new_property
  from public.property_documents d
  join public.properties p on p.id = d.property_id
  where d.id = p_new_id and p.owner_id = auth.uid();

  if v_old.id is null or v_new_property is null or p_old_id = p_new_id then
    raise exception 'document_not_found' using errcode = 'P0002';
  end if;
  if v_new_property <> v_old.property_id then
    raise exception 'other_property' using errcode = '22023';
  end if;
  if not (
    v_old.status = 'rejected'
    or (v_old.added_after_submission and v_old.verified_at is null)
  ) then
    raise exception 'not_replaceable' using errcode = '42501';
  end if;

  update public.property_documents
  set replaced_by = p_new_id
  where id = p_old_id;
end;
$$;

revoke all on function public.replace_document(uuid, uuid) from public, anon;
grant execute on function public.replace_document(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Storage: additions to a sent dossier
-- ---------------------------------------------------------------------------

-- A new file directly in the folder of a property in review / certified
-- (<uid>/<property id>/<file>: never in photos/…). Without an update
-- policy, an existing (locked) file cannot be overwritten.
create policy "Owners can add documents to their sent properties"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'property-documents'
    and array_length(storage.foldername(objects.name), 1) = 2
    and (storage.foldername(objects.name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.properties p
      where p.id::text = (storage.foldername(objects.name))[2]
        and p.owner_id = (select auth.uid())
        and p.status in ('in_review', 'certified')
    )
  );

-- A file of a sent dossier can only be deleted once no document row
-- refers to it (the app deletes the row of an unverified addition first;
-- also cleans the file of a failed insert). Photos stay locked.
create policy "Owners can delete unreferenced files of their sent properties"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'property-documents'
    and array_length(storage.foldername(objects.name), 1) = 2
    and (storage.foldername(objects.name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.properties p
      where p.id::text = (storage.foldername(objects.name))[2]
        and p.owner_id = (select auth.uid())
        and p.status in ('in_review', 'certified')
    )
    and not exists (
      select 1 from public.property_documents d
      where d.storage_path = objects.name
    )
  );

-- ---------------------------------------------------------------------------
-- 3. notifications.kind (idempotent: the same in EPIC-08 / EPIC-12)
-- ---------------------------------------------------------------------------

alter table public.notifications
  drop constraint if exists notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check
  check (kind ~ '^[a-z][a-z_]{2,39}$');

-- ---------------------------------------------------------------------------
-- 4. Staff: verify / reject a document
-- ---------------------------------------------------------------------------

-- Rubric of the vault (C1 / V18) of a document kind, used in the routes of
-- the notifications (/vendeur/coffre/biens/<id>?rubrique=<code>); the app
-- has the same mapping (VaultRubric).
create function public.vault_rubric_of(p_kind text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_kind in ('titre_propriete', 'plan', 'copropriete') then 'propriete'
    when p_kind = 'taxe_fonciere' then 'fiscalite'
    when p_kind in ('diagnostics', 'dpe', 'facture_energie', 'contrat_entretien')
      then 'energie'
    when p_kind in ('facture_travaux', 'rapport_spanc', 'assurance')
      then 'travaux'
    when p_kind = 'piece_identite' then 'identite'
    else 'autres'
  end;
$$;

-- French label of a document kind (notifications are written in French).
create function public.document_kind_label(p_kind text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'titre_propriete' then 'Titre de propriété'
    when 'taxe_fonciere' then 'Taxe foncière'
    when 'facture_energie' then 'Factures d’énergie'
    when 'facture_travaux' then 'Facture de travaux'
    when 'piece_identite' then 'Pièce d’identité'
    when 'diagnostics' then 'Diagnostics'
    when 'rapport_spanc' then 'Rapport SPANC'
    when 'plan' then 'Plan'
    when 'dpe' then 'DPE'
    when 'contrat_entretien' then 'Contrat d’entretien'
    when 'assurance' then 'Assurance'
    when 'copropriete' then 'Copropriété'
    else 'Document'
  end;
$$;

-- Marks a document verified by the expert (status analyzed). With
-- p_notify, the owner gets a "document vérifié" notification.
create function public.staff_verify_document(
  p_document_id uuid,
  p_verified_by uuid default null,
  p_notify boolean default false
)
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
end;
$$;

-- Rejects a document (status rejected + reason) and asks the owner to
-- replace it ("Un document est à remplacer").
create function public.staff_reject_document(
  p_document_id uuid,
  p_reason text
)
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
end;
$$;

revoke execute on function public.staff_verify_document(uuid, uuid, boolean)
  from public, anon, authenticated;
revoke execute on function public.staff_reject_document(uuid, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. profiles: personal information, language, deactivation
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column last_name text check (char_length(last_name) <= 100),
  add column phone text check (phone ~ '^\+?[0-9 .]{6,20}$'),
  add column postal_address text check (char_length(postal_address) <= 300),
  add column locale text check (locale in ('fr', 'en', 'es')),
  add column deactivated_at timestamptz,
  add column deletion_due_at timestamptz,
  add constraint profiles_deactivation_check
    check ((deactivated_at is null) = (deletion_due_at is null));

comment on column public.profiles.locale is
  'Language chosen in the app (null = language of the device).';
comment on column public.profiles.deactivated_at is
  'Account deactivated by its user (deletion requested); null when active.';
comment on column public.profiles.deletion_due_at is
  'When the purge deletes the account for good (deactivation + 30 days).';

grant update (last_name, phone, postal_address, locale)
  on table public.profiles to authenticated;

create index profiles_deletion_due_at_idx
  on public.profiles (deletion_due_at) where deletion_due_at is not null;

-- Whether p_user_id sells a property (EPIC-08 `sales`, which may not exist
-- yet in this database: checked at run time). A stage with a mandate
-- signed or later blocks the deactivation.
create function public.account_has_active_sale(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active boolean := false;
begin
  if to_regclass('public.sales') is null then
    return false;
  end if;
  execute 'select exists (select 1 from public.sales s '
    || 'where s.owner_id = $1 and s.stage in '
    || '(''mandate_signed'', ''published'', ''under_offer'', '
    || '''under_compromis''))'
    into v_active
    using p_user_id;
  return v_active;
end;
$$;

-- Whether p_user_id is a member of the Realesty team (EPIC-12
-- `staff_members`, checked at run time).
create function public.account_is_staff(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_staff boolean := false;
begin
  if to_regclass('public.staff_members') is null then
    return false;
  end if;
  execute 'select exists (select 1 from public.staff_members m '
    || 'where m.user_id = $1)'
    into v_staff
    using p_user_id;
  return v_staff;
end;
$$;

revoke all on function public.account_has_active_sale(uuid)
  from public, anon, authenticated;
revoke all on function public.account_is_staff(uuid)
  from public, anon, authenticated;

-- What prevents the signed-in user from deleting their account:
-- 'active_sale', 'staff_account' (empty when nothing does).
create function public.account_deletion_blockers()
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_blockers text[] := '{}';
begin
  if v_uid is null then
    raise exception 'not_signed_in' using errcode = '42501';
  end if;
  if public.account_is_staff(v_uid) then
    v_blockers := v_blockers || 'staff_account'::text;
  end if;
  if public.account_has_active_sale(v_uid) then
    v_blockers := v_blockers || 'active_sale'::text;
  end if;
  return v_blockers;
end;
$$;

-- Deactivates the account of the signed-in user at once; it is deleted
-- for good 30 days later (purge-accounts) unless reactivated. Idempotent:
-- returns the deletion date.
create function public.deactivate_account()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_due timestamptz;
begin
  if v_uid is null then
    raise exception 'not_signed_in' using errcode = '42501';
  end if;
  if public.account_is_staff(v_uid) then
    raise exception 'staff_account' using errcode = '42501';
  end if;
  if public.account_has_active_sale(v_uid) then
    raise exception 'active_sale' using errcode = '55000';
  end if;

  update public.profiles
  set deactivated_at = coalesce(deactivated_at, now()),
      deletion_due_at = coalesce(deletion_due_at, now() + interval '30 days')
  where id = v_uid
  returning deletion_due_at into v_due;

  if v_due is null then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;
  return v_due;
end;
$$;

-- Cancels the deletion of the signed-in user's account (before the purge).
create function public.reactivate_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_signed_in' using errcode = '42501';
  end if;
  update public.profiles
  set deactivated_at = null, deletion_due_at = null
  where id = auth.uid();
end;
$$;

revoke all on function public.account_deletion_blockers() from public, anon;
revoke all on function public.deactivate_account() from public, anon;
revoke all on function public.reactivate_account() from public, anon;
grant execute on function public.account_deletion_blockers() to authenticated;
grant execute on function public.deactivate_account() to authenticated;
grant execute on function public.reactivate_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Purge of the deactivated accounts
-- ---------------------------------------------------------------------------

-- One row per purged account: proves the deletion and lets a purge that
-- stopped half-way resume. No personal data in clear (the e-mail is
-- hashed), no foreign key (the user is gone).
create table public.account_deletions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique,
  email_sha256 text,
  deactivated_at timestamptz,
  started_at timestamptz not null default now(),
  deleted_at timestamptz,
  properties_count integer not null default 0,
  files_count integer not null default 0,
  attempts integer not null default 1,
  requested_from text not null default 'app'
    check (requested_from in ('app', 'staff'))
);

comment on table public.account_deletions is
  'Journal of the purged accounts (service role only, no personal data).';

alter table public.account_deletions enable row level security;
revoke all on table public.account_deletions from anon, authenticated;

-- The accounts whose deletion date has passed, oldest first.
create function public.account_purge_due(p_limit integer default 20)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from public.profiles p
  where p.deletion_due_at <= now()
  order by p.deletion_due_at
  limit greatest(p_limit, 1);
$$;

-- Starts (or resumes) the purge of p_user_id: false when the account was
-- reactivated or is not due. Records the journal row.
create function public.account_purge_begin(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  select * into v_profile
  from public.profiles
  where id = p_user_id
  for update;

  if v_profile.id is null
    or v_profile.deletion_due_at is null
    or v_profile.deletion_due_at > now() then
    return false;
  end if;

  insert into public.account_deletions (
    user_id, email_sha256, deactivated_at, properties_count
  )
  select
    p_user_id,
    encode(extensions.digest(lower(u.email), 'sha256'), 'hex'),
    v_profile.deactivated_at,
    (select count(*) from public.properties pr where pr.owner_id = p_user_id)
  from auth.users u
  where u.id = p_user_id
  on conflict (user_id) do update
    set attempts = public.account_deletions.attempts + 1;
  return true;
end;
$$;

-- The files of p_user_id in every bucket (all private buckets keep a
-- user's files under <user id>/…).
create function public.account_purge_files(p_user_id uuid)
returns table (bucket_id text, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select o.bucket_id, o.name
  from storage.objects o
  where o.name like p_user_id::text || '/%'
  order by o.bucket_id, o.name;
$$;

-- Ends the purge of p_user_id (its auth user was deleted).
create function public.account_purge_finish(
  p_user_id uuid,
  p_files_count integer
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.account_deletions
  set deleted_at = now(),
      files_count = files_count + greatest(p_files_count, 0)
  where user_id = p_user_id;
$$;

revoke all on function public.account_purge_due(integer)
  from public, anon, authenticated;
revoke all on function public.account_purge_begin(uuid)
  from public, anon, authenticated;
revoke all on function public.account_purge_files(uuid)
  from public, anon, authenticated;
revoke all on function public.account_purge_finish(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.account_purge_due(integer) to service_role;
grant execute on function public.account_purge_begin(uuid) to service_role;
grant execute on function public.account_purge_files(uuid) to service_role;
grant execute on function public.account_purge_finish(uuid, integer)
  to service_role;

-- Daily job: calls the Edge Function purge-accounts when an account is
-- due. Its URL and shared secret live in Vault (project_url,
-- purge_accounts_secret; see the runbook); without them it does nothing.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create function public.run_account_purge()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (
    select 1 from public.profiles where deletion_due_at <= now()
  ) then
    return null;
  end if;
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'purge_accounts_secret';
  if v_url is null or v_secret is null then
    raise warning 'run_account_purge: missing Vault secrets';
    return null;
  end if;
  return net.http_post(
    url := v_url || '/functions/v1/purge-accounts',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.run_account_purge()
  from public, anon, authenticated;

select cron.schedule(
  'purge-deactivated-accounts',
  '17 3 * * *',
  'select public.run_account_purge()'
);
