-- EPIC-08 · adjustments after review and owner decisions of 2026-10-03
-- (docs/plans/2026-10-03-offres-et-mise-en-vente.md, execution log).
--
-- - Prices of the services in one place (sale_service_price): Premium set-up
--   299 €, photo shoot 200 €, photo + video 350 €, diagnostics « sur devis »
--   (null). Same values in the app (SalePrices).
-- - Asking price bounded on the server: within [50 % of the sum of the
--   certified low bounds, 200 % of the sum of the high bounds] (trigger on
--   sales.asking_price_eur, and checked again at signature).
-- - Mandate « sans engagement », cancellable at any time after a minimum of
--   30 days (mandates.minimum_days; withdraw_sale refuses before; the team
--   can still end a test sale with staff_withdraw_sale).
-- - Signature typed instead of drawn (accessibility): method typed_test,
--   mandate_signatures.typed_signature.
-- - request_sale_service refuses wished slots in the past and a Premium
--   set-up on another formula.
-- - listing_photos: the property, room and source photo of a row belong to
--   the sale's target.
-- Additive: existing rows are kept (no sale nor mandate exists yet outside
-- the probes).

-- ---------------------------------------------------------------------------
-- Prices
-- ---------------------------------------------------------------------------

create function public.sale_service_price(p_kind text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'premium_setup' then 299
    when 'shooting_photo' then 200
    when 'shooting_photo_video' then 350
    else null -- diagnostics: « sur devis »
  end;
$$;

grant execute on function public.sale_service_price(text) to authenticated;

create or replace function public.sale_terms_version()
returns text
language sql
immutable
set search_path = ''
as $$ select 'test-2026-10-b'::text; $$;

-- ---------------------------------------------------------------------------
-- Price bounds
-- ---------------------------------------------------------------------------

-- [50 % of the sum of the certified low bounds, 200 % of the sum of the
-- high bounds] of the target's certified properties; nulls without any.
create function public.sale_price_bounds(
  p_property_id uuid,
  p_lot_id uuid,
  out low_eur integer,
  out high_eur integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select floor(sum(v.low_eur) * 0.5)::integer, ceil(sum(v.high_eur) * 2)::integer
  from public.properties p
  cross join lateral (
    select va.low_eur, va.high_eur from public.valuations va
    where va.property_id = p.id
    order by va.certified_at desc limit 1
  ) v
  where p.status = 'certified'
    and (p.id = p_property_id or (p_lot_id is not null and p.lot_id = p_lot_id));
$$;

revoke execute on function public.sale_price_bounds(uuid, uuid)
  from public, anon, authenticated;

create function public.sales_check_price()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_low integer;
  v_high integer;
begin
  if new.asking_price_eur is null then
    return new;
  end if;
  select b.low_eur, b.high_eur into v_low, v_high
  from public.sale_price_bounds(new.property_id, new.lot_id) b;
  if v_low is not null
    and (new.asking_price_eur < v_low or new.asking_price_eur > v_high) then
    raise exception 'price_out_of_bounds'
      using errcode = 'P0001', detail = v_low::text || ',' || v_high::text;
  end if;
  return new;
end;
$$;

revoke execute on function public.sales_check_price()
  from public, anon, authenticated;

create trigger sales_check_price
  before insert or update of asking_price_eur on public.sales
  for each row execute function public.sales_check_price();

-- ---------------------------------------------------------------------------
-- Mandates: minimum period, typed signature
-- ---------------------------------------------------------------------------

alter table public.mandates
  add column minimum_days smallint check (minimum_days between 0 and 365);

comment on column public.mandates.minimum_days is
  'Days after signature before the seller can end the mandate (30 by '
  'default, owner decision 2026-10-03).';

alter table public.mandate_signatures
  drop constraint if exists mandate_signatures_method_check;
alter table public.mandate_signatures
  add constraint mandate_signatures_method_check
    check (method in ('drawn_test', 'typed_test', 'offline')),
  add column typed_signature text
    check (char_length(typed_signature) between 2 and 200);

drop function public.sign_test_mandate(uuid, uuid, text, text, boolean, text, text);

-- Signs the TEST mandate p_mandate_id of the sale p_sale_id, with the drawn
-- signature stored at p_signature_path (bucket mandate-signatures) or the
-- name typed by the seller (p_typed_name). Requires the identity document
-- of the main property, a price within its bounds, and for L'Expert the
-- identity verified by the team. Retry-safe. Returns the mandate id.
create function public.sign_test_mandate(
  p_sale_id uuid,
  p_mandate_id uuid,
  p_terms_version text,
  p_signature_path text,
  p_accepted boolean,
  p_user_agent text default null,
  p_app_version text default null,
  p_typed_name text default null
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
  v_typed text := nullif(trim(p_typed_name), '');
  v_low integer;
  v_high integer;
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
  if v_typed is not null then
    if char_length(v_typed) < 2 or char_length(v_typed) > 200 then
      raise exception 'signature_missing' using errcode = 'P0001';
    end if;
  elsif p_signature_path is null
    or p_signature_path not like v_uid::text || '/' || p_sale_id::text || '/%'
    or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'mandate-signatures' and o.name = p_signature_path
    ) then
    raise exception 'signature_missing' using errcode = 'P0001';
  end if;

  select b.low_eur, b.high_eur into v_low, v_high
  from public.sale_price_bounds(v_sale.property_id, v_sale.lot_id) b;
  if v_sale.asking_price_eur is null then
    raise exception 'missing_price' using errcode = 'P0001';
  end if;
  if v_low is not null
    and (v_sale.asking_price_eur < v_low or v_sale.asking_price_eur > v_high) then
    raise exception 'price_out_of_bounds'
      using errcode = 'P0001', detail = v_low::text || ',' || v_high::text;
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
    (select nullif(trim(pr.first_name), '') from public.profiles pr where pr.id = v_uid),
    'Vendeur'
  );

  insert into public.mandates (
    id, sale_id, formula, kind, terms_version, presentation_price_eur,
    fee_rate, duration_months, minimum_days, status, is_test
  ) values (
    p_mandate_id, p_sale_id, v_sale.formula, 'exclusif_sans_engagement',
    p_terms_version, v_sale.asking_price_eur,
    case v_sale.formula when 'expert' then 3.00 else 1.00 end,
    null, 30, 'signed', true
  );
  insert into public.mandate_signatures (
    mandate_id, signer_user_id, property_owner_id, signer_name, method,
    signature_path, typed_signature, accepted_terms, user_agent, app_version
  ) values (
    p_mandate_id, v_uid, v_owner.id, v_name,
    case when v_typed is null then 'drawn_test' else 'typed_test' end,
    case when v_typed is null then p_signature_path end,
    v_typed, true, left(p_user_agent, 200), left(p_app_version, 40)
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

revoke execute on function public.sign_test_mandate(uuid, uuid, text, text, boolean, text, text, text)
  from public, anon;
grant execute on function public.sign_test_mandate(uuid, uuid, text, text, boolean, text, text, text)
  to authenticated, service_role;

-- Ends a sale (shared by withdraw_sale and staff_withdraw_sale).
create function public.sale_end(p_sale public.sales, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  update public.sales
  set stage = 'withdrawn', withdrawn_at = now(),
    withdraw_reason = left(nullif(trim(p_reason), ''), 300)
  where id = p_sale.id
  returning * into v_sale;
  update public.mandates
  set status = 'terminated', terminated_at = now()
  where sale_id = p_sale.id and status = 'signed';
  update public.sale_requests
  set status = 'cancelled'
  where sale_id = p_sale.id and status in ('requested', 'scheduled');
  perform public.sale_notify(
    v_sale, 'sale_withdrawn', 'Vente retirée',
    'Votre annonce est retirée et le mandat de test résilié.'
  );
end;
$$;

revoke execute on function public.sale_end(public.sales, text)
  from public, anon, authenticated;

-- Withdraws the sale: allowed before the signature, and after the minimum
-- period of the signed mandate (raises mandate_minimum_period with the
-- first day it is possible in the detail). Retry-safe.
create or replace function public.withdraw_sale(p_sale_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
  v_until timestamptz;
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
  select max(m.signed_at + make_interval(days => coalesce(m.minimum_days, 0)))
  into v_until
  from public.mandates m
  where m.sale_id = p_sale_id and m.status = 'signed';
  if v_until is not null and v_until > now() then
    raise exception 'mandate_minimum_period'
      using errcode = 'P0001', detail = v_until::text;
  end if;
  perform public.sale_end(v_sale, p_reason);
end;
$$;

-- The team ends a test sale at any time (SQL editor).
create function public.staff_withdraw_sale(p_sale_id uuid, p_reason text default null)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  select * into v_sale from public.sales where id = p_sale_id for update;
  if v_sale.id is null or v_sale.stage = 'withdrawn' then
    raise exception 'Sale % not found or withdrawn', p_sale_id using errcode = 'P0002';
  end if;
  perform public.sale_end(v_sale, p_reason);
end;
$$;

revoke execute on function public.staff_withdraw_sale(uuid, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Service requests
-- ---------------------------------------------------------------------------

create or replace function public.request_sale_service(
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
  if p_kind = 'premium_setup' and v_sale.formula <> 'premium' then
    raise exception 'premium_only' using errcode = 'P0001';
  end if;
  if p_kind = 'diagnostics' and coalesce(array_length(p_diagnostics, 1), 0) = 0 then
    raise exception 'diagnostics_missing' using errcode = 'P0001';
  end if;
  if exists (select 1 from unnest(p_preferred_slots) s where s < now()) then
    raise exception 'slot_in_past' using errcode = 'P0001';
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
    public.sale_service_price(p_kind)
  );
  return p_request_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- listing_photos: rows belong to the sale's target
-- ---------------------------------------------------------------------------

create function public.listing_photos_check_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  select * into v_sale from public.sales where id = new.sale_id;
  if new.property_id is not null and not exists (
    select 1 from public.properties p
    where p.id = new.property_id
      and (p.id = v_sale.property_id
        or (v_sale.lot_id is not null and p.lot_id = v_sale.lot_id))
  ) then
    raise exception 'listing_photo_target' using errcode = 'P0001';
  end if;
  if new.room_id is not null and (new.property_id is null or not exists (
    select 1 from public.rooms r
    where r.id = new.room_id and r.property_id = new.property_id
  )) then
    raise exception 'listing_photo_target' using errcode = 'P0001';
  end if;
  if new.source_room_photo_id is not null and (new.property_id is null or not exists (
    select 1 from public.room_photos ph
    where ph.id = new.source_room_photo_id and ph.property_id = new.property_id
  )) then
    raise exception 'listing_photo_target' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.listing_photos_check_target()
  from public, anon, authenticated;

create trigger listing_photos_check_target
  before insert on public.listing_photos
  for each row execute function public.listing_photos_check_target();
