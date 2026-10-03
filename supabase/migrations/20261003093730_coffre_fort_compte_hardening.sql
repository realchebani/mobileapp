-- EPIC-11 · Hardening of the vault and of the account deletion (review of
-- 2026-10-03). Additive; the applied migrations coffre_fort_compte and
-- account_purge_fallback are not edited.
--
-- M1  The purge never deletes an account that sells a property (EPIC-08
--     sales) or belongs to the team (EPIC-12): account_purge_begin re-checks
--     the blockers, records why on the profile (purge_blocked_reason /
--     purge_blocked_at) and skips it; staff see them in
--     staff_purge_blocked_accounts (runbook suppression-de-compte.md §5).
-- S1  account_purge_check (called by purge-accounts just before deleting the
--     files and the user) and account_purge_finish re-check that the account
--     is still deactivated, due and not blocked: a reactivation between two
--     steps keeps both the files and the account.
-- S2  A deactivated account cannot write its own data any more: trigger
--     refuse_deactivated_writes on the dossier tables (and the EPIC-08 sale
--     tables when they exist, also reached through security definer RPCs),
--     restrictive Storage policies on insert / update. Reactivation
--     (reactivate_account, profiles) stays possible.
-- Nits A document's kind is frozen once verified; a document row can never
--     point into a photos/ folder.

-- ---------------------------------------------------------------------------
-- M1 · blocked purges
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column purge_blocked_reason text
    check (purge_blocked_reason in ('active_sale', 'staff_account')),
  add column purge_blocked_at timestamptz;

comment on column public.profiles.purge_blocked_reason is
  'Why the purge skipped this due account (active_sale, staff_account); '
  'cleared on reactivation / deactivation.';

-- Due accounts, those never blocked first (a blocked account cannot hold
-- the others back).
create or replace function public.account_purge_due(p_limit integer default 20)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from public.profiles p
  where p.deactivated_at is not null
    and p.deletion_due_at <= now()
  order by p.purge_blocked_at nulls first, p.deletion_due_at
  limit greatest(p_limit, 1);
$$;

-- Whether p_user_id may be purged right now: deactivated, due, and neither
-- selling a property nor in the team (the reason is recorded when blocked).
create function public.account_purge_check(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_reason text;
begin
  select * into v_profile
  from public.profiles
  where id = p_user_id
  for update;

  if v_profile.id is null
    or v_profile.deactivated_at is null
    or v_profile.deletion_due_at is null
    or v_profile.deletion_due_at > now() then
    return false;
  end if;

  v_reason := case
    when public.account_has_active_sale(p_user_id) then 'active_sale'
    when public.account_is_staff(p_user_id) then 'staff_account'
  end;
  if v_reason is not null then
    update public.profiles
    set purge_blocked_reason = v_reason, purge_blocked_at = now()
    where id = p_user_id;
    raise log 'account purge skipped: %', v_reason;
    return false;
  end if;
  return true;
end;
$$;

-- Starts (or resumes) the purge: false when the account is no longer due,
-- or is blocked.
create or replace function public.account_purge_begin(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deactivated_at timestamptz;
begin
  if not public.account_purge_check(p_user_id) then
    return false;
  end if;
  select deactivated_at into v_deactivated_at
  from public.profiles where id = p_user_id;

  insert into public.account_deletions (
    user_id, email_sha256, deactivated_at, properties_count
  )
  select
    p_user_id,
    encode(extensions.digest(lower(u.email), 'sha256'), 'hex'),
    v_deactivated_at,
    (select count(*) from public.properties pr where pr.owner_id = p_user_id)
  from auth.users u
  where u.id = p_user_id
  on conflict (user_id) do update
    set attempts = public.account_deletions.attempts + 1;
  return true;
end;
$$;

-- Ends the purge: deletes the user (if the Auth API has not) only while it
-- may still be purged; true once the account is gone.
drop function public.account_purge_finish(uuid, integer);
create function public.account_purge_finish(
  p_user_id uuid,
  p_files_count integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.profiles where id = p_user_id) then
    if not public.account_purge_check(p_user_id) then
      return false;
    end if;
    delete from auth.users where id = p_user_id;
  end if;
  update public.account_deletions
  set deleted_at = now(),
      files_count = files_count + greatest(p_files_count, 0)
  where user_id = p_user_id;
  return true;
end;
$$;

revoke all on function public.account_purge_due(integer)
  from public, anon, authenticated;
revoke all on function public.account_purge_check(uuid)
  from public, anon, authenticated;
revoke all on function public.account_purge_begin(uuid)
  from public, anon, authenticated;
revoke all on function public.account_purge_finish(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.account_purge_due(integer) to service_role;
grant execute on function public.account_purge_check(uuid) to service_role;
grant execute on function public.account_purge_begin(uuid) to service_role;
grant execute on function public.account_purge_finish(uuid, integer)
  to service_role;

-- Deactivation and reactivation forget a previous block.
create or replace function public.deactivate_account()
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
      deletion_due_at = coalesce(deletion_due_at, now() + interval '30 days'),
      purge_blocked_reason = null,
      purge_blocked_at = null
  where id = v_uid
  returning deletion_due_at into v_due;

  if v_due is null then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;
  return v_due;
end;
$$;

create or replace function public.reactivate_account()
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
  set deactivated_at = null, deletion_due_at = null,
      purge_blocked_reason = null, purge_blocked_at = null
  where id = auth.uid();
end;
$$;

-- Staff: the due accounts the purge skips (SQL editor / service role).
create view public.staff_purge_blocked_accounts
with (security_invoker = true)
as
select p.id as user_id, p.deactivated_at, p.deletion_due_at,
       p.purge_blocked_reason, p.purge_blocked_at
from public.profiles p
where p.purge_blocked_reason is not null
  and p.deactivated_at is not null;

revoke all on public.staff_purge_blocked_accounts
  from public, anon, authenticated;
grant select on public.staff_purge_blocked_accounts to service_role;

-- ---------------------------------------------------------------------------
-- S2 · a deactivated account is read-only
-- ---------------------------------------------------------------------------

-- Whether p_user_id may change its data (no profile: not concerned).
create function public.account_is_active(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.profiles
    where id = p_user_id and deactivated_at is not null
  );
$$;

revoke all on function public.account_is_active(uuid) from public, anon;
grant execute on function public.account_is_active(uuid) to authenticated;

-- Refuses the writes of a signed-in deactivated user (direct or through a
-- security definer RPC); staff, service role and cascades (no auth.uid())
-- are not concerned.
create function public.refuse_deactivated_writes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is not null and not public.account_is_active(auth.uid()) then
    raise exception 'account_deactivated' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

revoke execute on function public.refuse_deactivated_writes()
  from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'properties', 'property_owners', 'property_parcels',
    'previous_estimates', 'rooms', 'lifestyle_items', 'property_documents',
    'room_photos', 'property_lots', 'pending_answers',
    'sales', 'mandates', 'mandate_signatures', 'sale_requests',
    'listing_photos'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'create trigger %I before insert or update or delete on public.%I '
        'for each row execute function public.refuse_deactivated_writes()',
        t || '_refuse_deactivated', t
      );
    end if;
  end loop;
end;
$$;

create policy "Deactivated accounts cannot upload files"
  on storage.objects as restrictive for insert
  to authenticated
  with check (public.account_is_active((select auth.uid())));

create policy "Deactivated accounts cannot change files"
  on storage.objects as restrictive for update
  to authenticated
  using (public.account_is_active((select auth.uid())));

-- ---------------------------------------------------------------------------
-- Nits · documents
-- ---------------------------------------------------------------------------

create policy "Documents are not stored in a photos folder"
  on public.property_documents as restrictive for insert
  to authenticated
  with check (storage_path not like '%/photos/%');

create or replace function public.property_documents_before_write()
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
    and old.verified_at is not null
    and new.kind is distinct from old.kind then
    -- The expert verified it as this kind.
    raise exception 'document_verified' using errcode = '42501';
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
