-- EPIC-09 · Visites (docs/plans/2026-10-03-visites.md §2–§3). Additive only.
--
-- - sales: visit settings (duration of a visit, weekly repetition).
-- - visit_availability (weekly model) + visit_slot_overrides (dated
--   exceptions): the visit slots of a sale, one-hour cells on a Paris-time
--   grid; computed once, in SQL (visit_week).
-- - visit_requests: requests of buyers (entered by the team in v1, buyer
--   app later), with a frozen light profile (buyer_snapshot, whitelisted
--   keys). One accepted visit per seller and slot (unique index).
-- - visit_reports: visit reports written by the team / the agent, visible to
--   the seller once published.
-- - visit_seller_notes: the seller's private note on a request.
-- - Seller RPCs (security definer): visit_week, apply_visit_slot_changes,
--   respond_visit_request, cancel_visit, set_visit_outcome.
-- - Team functions staff_* (SQL editor; no client role can run them) and the
--   demo data (source = 'demo', deletable with staff_purge_demo_visits).
-- - Hourly pg_cron job visits-housekeeping (expiry, done, reminder the day
--   before from 18:00 Paris time).
-- Default choices pending the owner's answers: plan §11 (option (a) of each
-- question); the constants live in visit_settings_defaults().
-- The exact address of the property is never exposed here (plan Q14):
-- address_shared_at is reserved for the buyer app.

-- ---------------------------------------------------------------------------
-- 1. Constants
-- ---------------------------------------------------------------------------

-- Shared by the app (VisitDefaults) and the server: notice before a slot,
-- horizon of the slots (weeks from the current one), grid of one-hour cells
-- [first_hour, end_hour), days an outcome stays editable, hour of the
-- reminder the day before.
create function public.visit_settings_defaults()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'min_notice_hours', 24,
    'horizon_weeks', 6,
    'first_hour', 8,
    'end_hour', 20,
    'outcome_days', 7,
    'reminder_hour', 18,
    'durations', jsonb_build_array(30, 45, 60),
    'lot_duration_min', 60
  );
$$;

grant execute on function public.visit_settings_defaults() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. sales: visit settings
-- ---------------------------------------------------------------------------

alter table public.sales
  add column visit_duration_min smallint not null default 45
    check (visit_duration_min in (30, 45, 60)),
  add column visit_repeat_weekly boolean not null default true,
  -- Planned, not exposed in v1 (plan Q4: every request waits for the seller).
  add column visit_auto_accept boolean not null default false;

comment on column public.sales.visit_duration_min is
  'EPIC-09 · duration of a visit; the rest of the hour is the break.';

grant update (visit_duration_min, visit_repeat_weekly)
  on table public.sales to authenticated;

-- A lot sold as a whole is visited in one go: 60 minutes by default (Q12).
create function public.sales_visit_defaults()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.lot_id is not null and new.visit_duration_min = 45 then
    new.visit_duration_min :=
      (public.visit_settings_defaults() ->> 'lot_duration_min')::smallint;
  end if;
  return new;
end;
$$;

revoke execute on function public.sales_visit_defaults()
  from public, anon, authenticated;

create trigger sales_visit_defaults
  before insert on public.sales
  for each row execute function public.sales_visit_defaults();

-- ---------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------

create table public.visit_availability (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  start_minute smallint not null
    check (start_minute between 420 and 1200 and start_minute % 60 = 0),
  created_at timestamptz not null default now(),
  unique (sale_id, weekday, start_minute)
);

comment on table public.visit_availability is
  'EPIC-09 · weekly visit slots of a sale (ISO weekday, minute of the day, '
  'Paris time); used while sales.visit_repeat_weekly.';

create table public.visit_slot_overrides (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  starts_at timestamptz not null,
  state text not null check (state in ('open', 'closed')),
  created_at timestamptz not null default now(),
  unique (sale_id, starts_at)
);

comment on table public.visit_slot_overrides is
  'EPIC-09 · dated exceptions to the weekly slots (every open slot when the '
  'weekly repetition is off).';

create table public.visit_requests (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  -- Buyer app later; null = entered by the team.
  buyer_user_id uuid references auth.users (id) on delete set null,
  buyer_label text not null check (char_length(buyer_label) between 1 and 60),
  buyer_initials text not null
    check (char_length(buyer_initials) between 1 and 3
      and buyer_initials = upper(buyer_initials)),
  slot_starts_at timestamptz not null,
  duration_min smallint not null check (duration_min in (30, 45, 60)),
  status text not null default 'pending' check (status in (
    'pending', 'accepted', 'refused', 'cancelled', 'expired', 'done', 'no_show'
  )),
  cancelled_by text check (cancelled_by in ('buyer', 'seller', 'agent', 'system')),
  status_reason text check (status_reason in (
    'slot_taken', 'not_available', 'profile_not_matching', 'sale_withdrawn',
    'sale_closed', 'other'
  )),
  handled_by text not null default 'seller'
    check (handled_by in ('seller', 'agent')),
  pass_visite boolean not null default false,
  requalification text not null default 'not_required'
    check (requalification in ('not_required', 'pending', 'done')),
  budget_validated boolean not null default false,
  -- The buyer's search mandate (badge « Mandat signé »).
  search_mandate_signed boolean not null default false,
  compatibility_score smallint check (compatibility_score between 0 and 100),
  buyer_snapshot jsonb not null default '{}',
  source text not null check (source in ('buyer_app', 'staff', 'agency', 'demo')),
  is_test boolean not null default true,
  -- Plan Q14 (not decided): unused in v1, the address is never shared.
  address_shared_at timestamptz,
  -- The team told the buyer about the last decision (runbook).
  buyer_informed_at timestamptz,
  reminded_at timestamptz,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  cancelled_at timestamptz,
  done_at timestamptz,
  updated_at timestamptz not null default now()
);

comment on table public.visit_requests is
  'EPIC-09 · visit requests of a sale; state columns written by RPCs only.';

-- One accepted visit per seller and slot: covers the same sale and the
-- other sales of the seller (plan Q8, Q11).
create unique index visit_requests_one_accepted_per_slot
  on public.visit_requests (owner_id, slot_starts_at)
  where status = 'accepted';
create index visit_requests_owner_status_idx
  on public.visit_requests (owner_id, status, slot_starts_at);
create index visit_requests_sale_slot_idx
  on public.visit_requests (sale_id, slot_starts_at);

create trigger visit_requests_set_updated_at
  before update on public.visit_requests
  for each row execute function public.seller_tunnel_set_updated_at();

create table public.visit_reports (
  id uuid primary key default gen_random_uuid(),
  visit_request_id uuid not null unique
    references public.visit_requests (id) on delete cascade,
  sale_id uuid not null references public.sales (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  author_kind text not null check (author_kind in ('agent', 'team')),
  author_label text not null check (char_length(author_label) between 1 and 80),
  agency_label text check (char_length(agency_label) <= 80),
  author_user_id uuid references auth.users (id) on delete set null,
  interest_level text check (interest_level in ('low', 'medium', 'high')),
  liked text[] not null default '{}',
  concerns text[] not null default '{}',
  next_steps text[] not null default '{}',
  comment text check (char_length(comment) <= 1000),
  published_at timestamptz,
  source text not null check (source in ('staff', 'agency', 'demo')),
  is_test boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint visit_reports_lists check (
    cardinality(liked) <= 8 and cardinality(concerns) <= 8
    and next_steps <@ array[
      'contre_visite', 'offre_annoncee', 'reflexion', 'pas_interesse'
    ]::text[]
  )
);

comment on table public.visit_reports is
  'EPIC-09 · report of a visit, written by the team / the agent; visible to '
  'the seller once published.';

create trigger visit_reports_set_updated_at
  before update on public.visit_reports
  for each row execute function public.seller_tunnel_set_updated_at();

create table public.visit_seller_notes (
  visit_request_id uuid primary key
    references public.visit_requests (id) on delete cascade,
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  note text not null check (char_length(note) between 1 and 500),
  updated_at timestamptz not null default now()
);

comment on table public.visit_seller_notes is
  'EPIC-09 · private note of the seller on a visit request (never shared).';

create trigger visit_seller_notes_set_updated_at
  before update on public.visit_seller_notes
  for each row execute function public.seller_tunnel_set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Light profile of the buyer (buyer_snapshot, version 1)
-- ---------------------------------------------------------------------------

-- Whether p_text is a short free text without contact details (no e-mail,
-- no phone-like run of digits).
create function public.visit_text_is_clean(p_text text, p_max integer)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_text is not null
    and char_length(trim(p_text)) between 1 and p_max
    and p_text !~ '@'
    and p_text !~ '[0-9][0-9 .-]{6,}[0-9]';
$$;

-- Whitelisted keys only (never phone, e-mail, income, address…), short
-- texts, ≤ 5 sub-scores (0 ≤ score ≤ max ≤ 100), ≤ 5 reasons; every field
-- optional, v = 1 when not empty.
create function public.visit_buyer_snapshot_is_valid(p_snapshot jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_item jsonb;
  v_sub_key text;
begin
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    return false;
  end if;
  if p_snapshot = '{}'::jsonb then
    return true;
  end if;
  if p_snapshot -> 'v' is distinct from '1'::jsonb then
    return false;
  end if;
  for v_key in select jsonb_object_keys(p_snapshot) loop
    if v_key not in (
      'v', 'household', 'financing', 'capacity', 'timeline', 'subscores',
      'reasons'
    ) then
      return false;
    end if;
    if v_key in ('household', 'financing', 'capacity', 'timeline') and (
      jsonb_typeof(p_snapshot -> v_key) <> 'string'
      or not public.visit_text_is_clean(p_snapshot ->> v_key, 80)
    ) then
      return false;
    end if;
  end loop;
  if p_snapshot ? 'subscores' then
    if jsonb_typeof(p_snapshot -> 'subscores') <> 'array'
      or jsonb_array_length(p_snapshot -> 'subscores') > 5 then
      return false;
    end if;
    for v_item in select jsonb_array_elements(p_snapshot -> 'subscores') loop
      if jsonb_typeof(v_item) <> 'object'
        or jsonb_typeof(v_item -> 'label') is distinct from 'string'
        or jsonb_typeof(v_item -> 'score') is distinct from 'number'
        or jsonb_typeof(v_item -> 'max') is distinct from 'number' then
        return false;
      end if;
      for v_sub_key in select jsonb_object_keys(v_item) loop
        if v_sub_key not in ('label', 'score', 'max') then
          return false;
        end if;
      end loop;
      if not public.visit_text_is_clean(v_item ->> 'label', 40)
        or (v_item ->> 'score')::numeric < 0
        or (v_item ->> 'max')::numeric > 100
        or (v_item ->> 'max')::numeric < 1
        or (v_item ->> 'score')::numeric > (v_item ->> 'max')::numeric then
        return false;
      end if;
    end loop;
  end if;
  if p_snapshot ? 'reasons' then
    if jsonb_typeof(p_snapshot -> 'reasons') <> 'array'
      or jsonb_array_length(p_snapshot -> 'reasons') > 5 then
      return false;
    end if;
    for v_item in select jsonb_array_elements(p_snapshot -> 'reasons') loop
      if jsonb_typeof(v_item) <> 'string'
        or not public.visit_text_is_clean(v_item #>> '{}', 160) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$$;

alter table public.visit_requests
  add constraint visit_requests_snapshot_valid
    check (public.visit_buyer_snapshot_is_valid(buyer_snapshot)),
  add constraint visit_requests_label_clean
    check (public.visit_text_is_clean(buyer_label, 60));

-- ---------------------------------------------------------------------------
-- 5. Time helpers (Paris time, daylight saving included)
-- ---------------------------------------------------------------------------

-- Whether p_starts_at starts a cell of the grid (hour sharp, Paris time,
-- within [first_hour, end_hour)).
create function public.visit_slot_on_grid(p_starts_at timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select date_trunc('hour', l) = l
    and extract(hour from l)
      >= (public.visit_settings_defaults() ->> 'first_hour')::int
    and extract(hour from l)
      < (public.visit_settings_defaults() ->> 'end_hour')::int
  from (select p_starts_at at time zone 'Europe/Paris' as l) t;
$$;

-- First bookable instant (now + notice).
create function public.visit_notice_start()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select now() + make_interval(
    hours => (public.visit_settings_defaults() ->> 'min_notice_hours')::int
  );
$$;

-- End of the horizon: Monday 00:00 (Paris) of the current week + horizon.
create function public.visit_horizon_end()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (
    date_trunc('week', now() at time zone 'Europe/Paris')
    + make_interval(
      days => 7 * (public.visit_settings_defaults() ->> 'horizon_weeks')::int
    )
  ) at time zone 'Europe/Paris';
$$;

-- « sam. 3 oct. à 10 h 00 » (notifications are written in French).
create function public.visit_slot_label(p_starts_at timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select (array['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'])
      [extract(isodow from l)::int]
    || ' ' || extract(day from l)::int || ' '
    || (array['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.',
      'août', 'sept.', 'oct.', 'nov.', 'déc.'])[extract(month from l)::int]
    || ' à ' || extract(hour from l)::int || ' h '
    || to_char(l, 'MI')
  from (select p_starts_at at time zone 'Europe/Paris' as l) t;
$$;

-- Whether the sale takes new visit requests (published listing; EPIC-10
-- widens it to the sales under offer).
create function public.visit_sale_accepts_requests(p_sale public.sales)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_sale.stage = 'published';
$$;

-- Whether the seller opened the slot p_starts_at of the sale p_sale: its
-- dated exception, else the weekly model (repetition on), else closed.
create function public.visit_slot_is_open(p_sale public.sales, p_starts_at timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select o.state = 'open' from public.visit_slot_overrides o
      where o.sale_id = p_sale.id and o.starts_at = p_starts_at),
    p_sale.visit_repeat_weekly and exists (
      select 1 from public.visit_availability a
      where a.sale_id = p_sale.id
        and a.weekday = extract(isodow from p_starts_at at time zone 'Europe/Paris')
        and a.start_minute = extract(hour from p_starts_at at time zone 'Europe/Paris') * 60
    )
  );
$$;

-- In-app notification about the visit request p_request (route: the request,
-- or one of its screens).
create function public.visit_notify(
  p_request public.visit_requests,
  p_kind text,
  p_title text,
  p_body text,
  p_screen text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, property_id, kind, title, body, route)
  select
    p_request.owner_id,
    public.sale_main_property(s),
    p_kind,
    left(p_title, 200),
    left(p_body, 1000),
    '/vendeur/visites/demandes/' || p_request.id::text
      || coalesce('/' || p_screen, '')
  from public.sales s
  where s.id = p_request.sale_id;
$$;

do $$
declare
  v_function text;
begin
  foreach v_function in array array[
    'public.visit_text_is_clean(text, integer)',
    'public.visit_buyer_snapshot_is_valid(jsonb)',
    'public.visit_slot_on_grid(timestamptz)',
    'public.visit_notice_start()',
    'public.visit_horizon_end()',
    'public.visit_slot_label(timestamptz)',
    'public.visit_sale_accepts_requests(public.sales)',
    'public.visit_slot_is_open(public.sales, timestamptz)',
    'public.visit_notify(public.visit_requests, text, text, text, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated',
      v_function);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Invariants
-- ---------------------------------------------------------------------------

-- visit_requests: the owner is the sale's; the slot is a cell of the grid;
-- a new request needs a sale that takes requests and an active account;
-- L’Expert requests are handled by the agent. Identity, sale and slot never
-- change afterwards.
create function public.visit_requests_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.sale_id := old.sale_id;
    new.owner_id := old.owner_id;
    new.slot_starts_at := old.slot_starts_at;
    new.duration_min := old.duration_min;
    new.source := old.source;
    new.created_at := old.created_at;
    return new;
  end if;
  select * into v_sale from public.sales where id = new.sale_id;
  if v_sale.id is null then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
  new.owner_id := v_sale.owner_id;
  new.duration_min := coalesce(new.duration_min, v_sale.visit_duration_min);
  new.is_test := new.is_test or v_sale.is_test;
  if v_sale.formula = 'expert' then
    new.handled_by := 'agent';
  end if;
  if not public.visit_slot_on_grid(new.slot_starts_at) then
    raise exception 'slot_outside_grid' using errcode = 'P0001';
  end if;
  if not public.visit_sale_accepts_requests(v_sale) then
    raise exception 'sale_closed' using errcode = 'P0001';
  end if;
  if not public.account_is_active(v_sale.owner_id) then
    raise exception 'account_deactivated' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.visit_requests_check()
  from public, anon, authenticated;

create trigger visit_requests_check
  before insert or update on public.visit_requests
  for each row execute function public.visit_requests_check();

-- visit_reports: sale and owner of the request.
create function public.visit_reports_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  select * into v_request from public.visit_requests
  where id = new.visit_request_id;
  new.sale_id := v_request.sale_id;
  new.owner_id := v_request.owner_id;
  new.is_test := new.is_test or v_request.is_test;
  return new;
end;
$$;

revoke execute on function public.visit_reports_check()
  from public, anon, authenticated;

create trigger visit_reports_check
  before insert or update on public.visit_reports
  for each row execute function public.visit_reports_check();

-- visit_seller_notes: the note of the request's owner.
create function public.visit_seller_notes_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.owner_id := (
    select r.owner_id from public.visit_requests r
    where r.id = new.visit_request_id
  );
  if tg_op = 'UPDATE' then
    new.visit_request_id := old.visit_request_id;
  end if;
  return new;
end;
$$;

revoke execute on function public.visit_seller_notes_check()
  from public, anon, authenticated;

create trigger visit_seller_notes_check
  before insert or update on public.visit_seller_notes
  for each row execute function public.visit_seller_notes_check();

-- visit_availability / visit_slot_overrides: the owner is the sale's.
create function public.visit_slots_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.owner_id := (select s.owner_id from public.sales s where s.id = new.sale_id);
  return new;
end;
$$;

revoke execute on function public.visit_slots_owner()
  from public, anon, authenticated;

create trigger visit_availability_owner
  before insert or update on public.visit_availability
  for each row execute function public.visit_slots_owner();
create trigger visit_slot_overrides_owner
  before insert or update on public.visit_slot_overrides
  for each row execute function public.visit_slots_owner();

-- A deactivated account cannot write (EPIC-11, refuse_deactivated_writes).
do $$
declare
  t text;
begin
  foreach t in array array[
    'visit_availability', 'visit_slot_overrides', 'visit_requests',
    'visit_reports', 'visit_seller_notes'
  ] loop
    execute format(
      'create trigger %I before insert or update or delete on public.%I '
      'for each row execute function public.refuse_deactivated_writes()',
      t || '_refuse_deactivated', t
    );
  end loop;
end;
$$;

-- A sale that ends (withdrawn) cancels its open visits.
create function public.sales_end_visits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.visit_requests
  set status = 'cancelled', cancelled_by = 'system',
    status_reason = 'sale_withdrawn', cancelled_at = now()
  where sale_id = new.id and status in ('pending', 'accepted')
    and slot_starts_at > now();
  return new;
end;
$$;

revoke execute on function public.sales_end_visits()
  from public, anon, authenticated;

create trigger sales_end_visits
  after update of stage on public.sales
  for each row
  when (new.stage = 'withdrawn' and old.stage is distinct from 'withdrawn')
  execute function public.sales_end_visits();

-- ---------------------------------------------------------------------------
-- 7. Row level security
-- ---------------------------------------------------------------------------

alter table public.visit_availability enable row level security;
alter table public.visit_slot_overrides enable row level security;
alter table public.visit_requests enable row level security;
alter table public.visit_reports enable row level security;
alter table public.visit_seller_notes enable row level security;

create policy "Owners can view their weekly visit slots"
  on public.visit_availability for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can view their visit slot exceptions"
  on public.visit_slot_overrides for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can view the visit requests of their sales"
  on public.visit_requests for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can view the published reports of their visits"
  on public.visit_reports for select
  to authenticated
  using ((select auth.uid()) = owner_id and published_at is not null);

create policy "Owners can view their visit notes"
  on public.visit_seller_notes for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can write notes on their visit requests"
  on public.visit_seller_notes for insert
  to authenticated
  with check (exists (
    select 1 from public.visit_requests r
    where r.id = visit_request_id and r.owner_id = (select auth.uid())
  ));

create policy "Owners can edit their visit notes"
  on public.visit_seller_notes for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "Owners can delete their visit notes"
  on public.visit_seller_notes for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

revoke all on table public.visit_availability, public.visit_slot_overrides,
  public.visit_requests, public.visit_reports, public.visit_seller_notes
  from anon, authenticated;
grant select on table public.visit_availability, public.visit_slot_overrides,
  public.visit_requests, public.visit_reports to authenticated;
grant select, insert, delete on table public.visit_seller_notes to authenticated;
grant update (note) on table public.visit_seller_notes to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Seller RPCs (security definer: they write the state columns)
-- ---------------------------------------------------------------------------

-- The sale p_sale_id of the caller, managed by the seller (1 % formulas).
create function public.visit_own_sale(p_sale_id uuid, p_lock boolean default false)
returns public.sales
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  if p_lock then
    select * into v_sale from public.sales
    where id = p_sale_id and owner_id = (select auth.uid())
    for update;
  else
    select * into v_sale from public.sales
    where id = p_sale_id and owner_id = (select auth.uid());
  end if;
  if v_sale.id is null or v_sale.stage = 'withdrawn' then
    raise exception 'sale_not_found' using errcode = 'P0001';
  end if;
  if v_sale.formula not in ('essentiel', 'premium') then
    raise exception 'formula_not_self_managed' using errcode = 'P0001';
  end if;
  return v_sale;
end;
$$;

revoke execute on function public.visit_own_sale(uuid, boolean)
  from public, anon, authenticated;

-- The week of p_monday (any day of it) of the sale p_sale_id: every cell of
-- the grid with its state — booked (accepted visit of this sale), past
-- (before the notice or after the horizon), booked_elsewhere (accepted visit
-- of another sale of the seller), open, closed — and its pending requests.
create function public.visit_week(p_sale_id uuid, p_monday date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
  v_monday date := date_trunc('week', p_monday)::date;
  v_first integer := (public.visit_settings_defaults() ->> 'first_hour')::int;
  v_end integer := (public.visit_settings_defaults() ->> 'end_hour')::int;
  v_notice timestamptz := public.visit_notice_start();
  v_horizon timestamptz := public.visit_horizon_end();
  v_slots jsonb;
begin
  v_sale := public.visit_own_sale(p_sale_id);
  with cells as (
    select d::date as day, h,
      ((d::date + make_time(h, 0, 0)) at time zone 'Europe/Paris') as starts_at
    from generate_series(v_monday::timestamp, (v_monday + 6)::timestamp,
      interval '1 day') d,
      generate_series(v_first, v_end - 1) h
  ),
  detailed as (
    select c.*,
      public.visit_slot_is_open(v_sale, c.starts_at) as is_open,
      (select o.state from public.visit_slot_overrides o
        where o.sale_id = v_sale.id and o.starts_at = c.starts_at) as exception,
      (select r.id from public.visit_requests r
        where r.sale_id = v_sale.id and r.slot_starts_at = c.starts_at
          and r.status = 'accepted') as booked_id,
      exists (select 1 from public.visit_requests r
        where r.owner_id = v_sale.owner_id and r.sale_id <> v_sale.id
          and r.slot_starts_at = c.starts_at and r.status = 'accepted')
        as elsewhere,
      coalesce((select jsonb_agg(r.id order by r.created_at)
        from public.visit_requests r
        where r.sale_id = v_sale.id and r.slot_starts_at = c.starts_at
          and r.status = 'pending'), '[]'::jsonb) as pending_ids
    from cells c
  )
  select jsonb_agg(jsonb_build_object(
    'starts_at', d.starts_at,
    'day', d.day,
    'hour', d.h,
    'open', d.is_open,
    'exception', d.exception,
    'state', case
      when d.booked_id is not null then 'booked'
      when d.starts_at < v_notice or d.starts_at >= v_horizon then 'past'
      when d.elsewhere then 'booked_elsewhere'
      when d.is_open then 'open'
      else 'closed' end,
    'booked_request_id', d.booked_id,
    'pending_request_ids', d.pending_ids
  ) order by d.starts_at)
  into v_slots
  from detailed d;
  return jsonb_build_object(
    'sale_id', v_sale.id,
    'monday', v_monday,
    'current_monday', date_trunc('week', now() at time zone 'Europe/Paris')::date,
    'repeat_weekly', v_sale.visit_repeat_weekly,
    'duration_min', v_sale.visit_duration_min,
    'slots', coalesce(v_slots, '[]'::jsonb)
  );
end;
$$;

-- Opens / closes slots of the sale p_sale_id, then returns the week of
-- p_monday (default: the current one). Each change is
-- {scope: 'weekly', weekday, start_minute, open} (weekly model) or
-- {scope: 'date', starts_at, open} (one day only; open null removes the
-- exception). Idempotent: replaying the same changes changes nothing.
create function public.apply_visit_slot_changes(
  p_sale_id uuid,
  p_changes jsonb,
  p_monday date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
  v_change jsonb;
  v_open boolean;
  v_weekday integer;
  v_minute integer;
  v_starts_at timestamptz;
  v_base boolean;
  v_first integer := (public.visit_settings_defaults() ->> 'first_hour')::int;
  v_end integer := (public.visit_settings_defaults() ->> 'end_hour')::int;
begin
  v_sale := public.visit_own_sale(p_sale_id, true);
  if v_sale.stage not in ('mandate_signed', 'published') then
    raise exception 'sale_not_signed' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_changes) is distinct from 'array'
    or jsonb_array_length(p_changes) > 200 then
    raise exception 'invalid_changes' using errcode = 'P0001';
  end if;
  for v_change in select jsonb_array_elements(p_changes) loop
    if jsonb_typeof(v_change -> 'open') not in ('boolean', 'null')
      and v_change ? 'open' then
      raise exception 'invalid_changes' using errcode = 'P0001';
    end if;
    v_open := (v_change ->> 'open')::boolean;
    if v_change ->> 'scope' = 'weekly' then
      v_weekday := (v_change ->> 'weekday')::int;
      v_minute := (v_change ->> 'start_minute')::int;
      if v_weekday is null or v_weekday not between 1 and 7
        or v_minute is null or v_minute % 60 <> 0
        or v_minute / 60 < v_first or v_minute / 60 >= v_end
        or v_open is null then
        raise exception 'slot_outside_grid' using errcode = 'P0001';
      end if;
      if v_open then
        insert into public.visit_availability (sale_id, owner_id, weekday, start_minute)
        values (v_sale.id, v_sale.owner_id, v_weekday, v_minute)
        on conflict (sale_id, weekday, start_minute) do nothing;
      else
        delete from public.visit_availability
        where sale_id = v_sale.id and weekday = v_weekday
          and start_minute = v_minute;
      end if;
    elsif v_change ->> 'scope' = 'date' then
      v_starts_at := (v_change ->> 'starts_at')::timestamptz;
      if v_starts_at is null or not public.visit_slot_on_grid(v_starts_at) then
        raise exception 'slot_outside_grid' using errcode = 'P0001';
      end if;
      if v_starts_at < public.visit_notice_start()
        or v_starts_at >= public.visit_horizon_end() then
        raise exception 'slot_past' using errcode = 'P0001';
      end if;
      if v_open is false and exists (
        select 1 from public.visit_requests r
        where r.sale_id = v_sale.id and r.slot_starts_at = v_starts_at
          and r.status = 'accepted'
      ) then
        raise exception 'slot_booked' using errcode = 'P0001';
      end if;
      v_base := v_sale.visit_repeat_weekly and exists (
        select 1 from public.visit_availability a
        where a.sale_id = v_sale.id
          and a.weekday = extract(isodow from v_starts_at at time zone 'Europe/Paris')
          and a.start_minute
            = extract(hour from v_starts_at at time zone 'Europe/Paris') * 60
      );
      if v_open is null or v_open = v_base then
        delete from public.visit_slot_overrides
        where sale_id = v_sale.id and starts_at = v_starts_at;
      else
        insert into public.visit_slot_overrides (sale_id, owner_id, starts_at, state)
        values (v_sale.id, v_sale.owner_id, v_starts_at,
          case when v_open then 'open' else 'closed' end)
        on conflict (sale_id, starts_at) do update set state = excluded.state;
      end if;
    else
      raise exception 'invalid_changes' using errcode = 'P0001';
    end if;
  end loop;
  return public.visit_week(
    v_sale.id,
    coalesce(p_monday, (now() at time zone 'Europe/Paris')::date)
  );
end;
$$;

-- The pending request p_request_id of the caller, handled by the seller,
-- locked.
create function public.visit_own_request(p_request_id uuid)
returns public.visit_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  select * into v_request from public.visit_requests
  where id = p_request_id and owner_id = (select auth.uid())
  for update;
  if v_request.id is null then
    raise exception 'request_not_found' using errcode = 'P0001';
  end if;
  if v_request.handled_by <> 'seller' then
    raise exception 'handled_by_agent' using errcode = 'P0001';
  end if;
  return v_request;
end;
$$;

revoke execute on function public.visit_own_request(uuid)
  from public, anon, authenticated;

-- Accepts or refuses (p_decision: accept, refuse) a pending request. Accepting
-- refuses the other pending requests of the seller for the same slot
-- (slot_taken). Refusing takes an optional reason (not_available,
-- profile_not_matching, other) and a private note (visit_seller_notes),
-- never shown to the buyer. Retry-safe (same decision: nothing changes).
create function public.visit_decide(
  p_request public.visit_requests,
  p_decision text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales;
begin
  if p_decision not in ('accept', 'refuse') then
    raise exception 'invalid_decision' using errcode = 'P0001';
  end if;
  if p_request.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = 'P0001';
  end if;
  if p_request.slot_starts_at <= now() then
    raise exception 'too_late' using errcode = 'P0001';
  end if;
  if p_decision = 'accept' then
    select * into v_sale from public.sales where id = p_request.sale_id;
    if v_sale.stage not in ('mandate_signed', 'published') then
      raise exception 'sale_closed' using errcode = 'P0001';
    end if;
    begin
      update public.visit_requests
      set status = 'accepted', responded_at = now(), status_reason = null,
        buyer_informed_at = null
      where id = p_request.id;
    exception when unique_violation then
      raise exception 'slot_taken' using errcode = 'P0001';
    end;
    update public.visit_requests
    set status = 'refused', status_reason = 'slot_taken', responded_at = now(),
      buyer_informed_at = null
    where owner_id = p_request.owner_id
      and slot_starts_at = p_request.slot_starts_at
      and status = 'pending' and id <> p_request.id;
  else
    if p_reason is not null
      and p_reason not in ('not_available', 'profile_not_matching', 'other') then
      raise exception 'invalid_reason' using errcode = 'P0001';
    end if;
    update public.visit_requests
    set status = 'refused', status_reason = p_reason, responded_at = now(),
      buyer_informed_at = null
    where id = p_request.id;
  end if;
end;
$$;

revoke execute on function public.visit_decide(public.visit_requests, text, text)
  from public, anon, authenticated;

create function public.respond_visit_request(
  p_request_id uuid,
  p_decision text,
  p_reason text default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.visit_own_request(p_request_id);
  if (v_request.status = 'accepted' and p_decision = 'accept')
    or (v_request.status = 'refused' and p_decision = 'refuse') then
    return;
  end if;
  perform public.visit_decide(v_request, p_decision, p_reason);
  if nullif(trim(p_note), '') is not null then
    insert into public.visit_seller_notes (visit_request_id, owner_id, note)
    values (v_request.id, v_request.owner_id, left(trim(p_note), 500))
    on conflict (visit_request_id) do update set note = excluded.note;
  end if;
end;
$$;

-- Cancels an accepted visit to come (p_reason: not_available, other). The
-- team tells the buyer (runbook). Retry-safe.
create function public.cancel_visit(p_request_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.visit_own_request(p_request_id);
  if v_request.status = 'cancelled' and v_request.cancelled_by = 'seller' then
    return;
  end if;
  if v_request.status <> 'accepted' then
    raise exception 'request_not_accepted' using errcode = 'P0001';
  end if;
  if v_request.slot_starts_at <= now() then
    raise exception 'too_late' using errcode = 'P0001';
  end if;
  if p_reason is not null and p_reason not in ('not_available', 'other') then
    raise exception 'invalid_reason' using errcode = 'P0001';
  end if;
  update public.visit_requests
  set status = 'cancelled', cancelled_by = 'seller', cancelled_at = now(),
    status_reason = p_reason, buyer_informed_at = null
  where id = v_request.id;
end;
$$;

-- Outcome of a visit that started (p_outcome: done, no_show), editable for
-- outcome_days days after the slot.
create function public.set_visit_outcome(p_request_id uuid, p_outcome text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.visit_own_request(p_request_id);
  if p_outcome not in ('done', 'no_show') then
    raise exception 'invalid_outcome' using errcode = 'P0001';
  end if;
  if v_request.status not in ('accepted', 'done', 'no_show') then
    raise exception 'request_not_accepted' using errcode = 'P0001';
  end if;
  if v_request.slot_starts_at > now() then
    raise exception 'too_early' using errcode = 'P0001';
  end if;
  if now() > v_request.slot_starts_at + make_interval(
    days => (public.visit_settings_defaults() ->> 'outcome_days')::int
  ) then
    raise exception 'too_late' using errcode = 'P0001';
  end if;
  update public.visit_requests
  set status = p_outcome, done_at = coalesce(done_at, now())
  where id = v_request.id and status <> p_outcome;
end;
$$;

do $$
declare
  v_function text;
begin
  foreach v_function in array array[
    'public.visit_week(uuid, date)',
    'public.apply_visit_slot_changes(uuid, jsonb, date)',
    'public.respond_visit_request(uuid, text, text, text)',
    'public.cancel_visit(uuid, text)',
    'public.set_visit_outcome(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', v_function);
    execute format('grant execute on function %s to authenticated, service_role',
      v_function);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Team functions (SQL editor / service role; runbook
--    docs/runbooks/organiser-les-visites.md). Security invoker, no client
--    role can run them; each one writes a line in staff_audit_log.
-- ---------------------------------------------------------------------------

-- The request p_request_id, locked (P0002 when missing).
create function public.staff_visit_request(p_request_id uuid)
returns public.visit_requests
language plpgsql
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  select * into v_request from public.visit_requests
  where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'Visit request % not found', p_request_id using errcode = 'P0002';
  end if;
  return v_request;
end;
$$;

-- « Thomas & Léa B. · sam. 3 oct. à 10 h 00 »
create function public.visit_request_summary(p_request public.visit_requests)
returns text
language sql
stable
set search_path = ''
as $$
  select p_request.buyer_label || ' · '
    || public.visit_slot_label(p_request.slot_starts_at);
$$;

-- Property of the journal line of a request.
create function public.visit_request_property(p_request public.visit_requests)
returns uuid
language sql
stable
set search_path = ''
as $$
  select public.sale_main_property(s) from public.sales s
  where s.id = p_request.sale_id;
$$;

-- Qualification flags of p_flags (pass_visite, budget_validated,
-- search_mandate_signed: booleans; requalification: not_required, pending,
-- done) applied to the request p_request_id.
create function public.visit_apply_flags(p_request_id uuid, p_flags jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_key text;
begin
  for v_key in select jsonb_object_keys(coalesce(p_flags, '{}')) loop
    if v_key not in (
      'pass_visite', 'budget_validated', 'search_mandate_signed',
      'requalification'
    ) then
      raise exception 'Unknown flag %', v_key using errcode = '22023';
    end if;
  end loop;
  update public.visit_requests
  set pass_visite = coalesce((p_flags ->> 'pass_visite')::boolean, pass_visite),
    budget_validated =
      coalesce((p_flags ->> 'budget_validated')::boolean, budget_validated),
    search_mandate_signed = coalesce(
      (p_flags ->> 'search_mandate_signed')::boolean, search_mandate_signed
    ),
    requalification = coalesce(p_flags ->> 'requalification', requalification)
  where id = p_request_id;
end;
$$;

-- Enters a visit request (phone prospect, visit organised by the agent).
-- p_status pending (the seller answers) or accepted (L’Expert: visit planned
-- by the agent). A closed slot is refused unless p_outside_slots. Retry-safe
-- with the same p_request_id.
create function public.staff_create_visit_request(
  p_sale_id uuid,
  p_slot_starts_at timestamptz,
  p_buyer_label text,
  p_buyer_initials text,
  p_source text default 'staff',
  p_flags jsonb default '{}',
  p_score integer default null,
  p_snapshot jsonb default '{}',
  p_status text default 'pending',
  p_outside_slots boolean default false,
  p_request_id uuid default gen_random_uuid()
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_sale public.sales;
  v_request public.visit_requests;
begin
  if exists (select 1 from public.visit_requests where id = p_request_id) then
    return p_request_id;
  end if;
  select * into v_sale from public.sales where id = p_sale_id;
  if v_sale.id is null then
    raise exception 'Sale % not found', p_sale_id using errcode = 'P0002';
  end if;
  if p_status not in ('pending', 'accepted') then
    raise exception 'p_status must be pending or accepted' using errcode = '22023';
  end if;
  if not p_outside_slots and (
    not public.visit_slot_is_open(v_sale, p_slot_starts_at)
    or p_slot_starts_at < public.visit_notice_start()
    or p_slot_starts_at >= public.visit_horizon_end()
  ) then
    raise exception 'slot_closed' using errcode = 'P0001',
      hint = 'Slot not open by the seller: pass p_outside_slots => true.';
  end if;
  insert into public.visit_requests (
    id, sale_id, owner_id, buyer_label, buyer_initials, slot_starts_at,
    duration_min, handled_by, requalification, compatibility_score,
    buyer_snapshot, source, is_test
  ) values (
    p_request_id, v_sale.id, v_sale.owner_id, trim(p_buyer_label),
    upper(trim(p_buyer_initials)), p_slot_starts_at, v_sale.visit_duration_min,
    case when p_status = 'accepted' then 'agent' else 'seller' end,
    case when v_sale.formula = 'premium' then 'pending' else 'not_required' end,
    p_score, coalesce(p_snapshot, '{}'), p_source, true
  );
  perform public.visit_apply_flags(p_request_id, p_flags);
  if p_status = 'accepted' then
    begin
      update public.visit_requests
      set status = 'accepted', responded_at = now()
      where id = p_request_id;
    exception when unique_violation then
      raise exception 'slot_taken' using errcode = 'P0001';
    end;
  end if;
  select * into v_request from public.visit_requests where id = p_request_id;
  if p_status = 'accepted' then
    perform public.visit_notify(
      v_request, 'visit_updated', 'Visite programmée par votre agent',
      public.visit_request_summary(v_request)
    );
  else
    perform public.visit_notify(
      v_request, 'visit_requested', 'Nouvelle demande de visite',
      public.visit_request_summary(v_request)
    );
  end if;
  perform public._staff_log(
    'visit_request_created', public.visit_request_property(v_request),
    'visit_request', p_request_id::text,
    jsonb_build_object('status', p_status, 'source', p_source)
  );
  return p_request_id;
end;
$$;

-- Le Premium: the team called the buyer (requalification done by default).
create function public.staff_requalify_visit_request(
  p_request_id uuid,
  p_flags jsonb default '{}'
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.staff_visit_request(p_request_id);
  perform public.visit_apply_flags(
    p_request_id, jsonb_build_object('requalification', 'done') || coalesce(p_flags, '{}')
  );
  select * into v_request from public.visit_requests where id = p_request_id;
  perform public.visit_notify(
    v_request, 'visit_updated', 'Acquéreur requalifié par un agent',
    public.visit_request_summary(v_request)
  );
  perform public._staff_log(
    'visit_request_requalified', public.visit_request_property(v_request),
    'visit_request', p_request_id::text, coalesce(p_flags, '{}')
  );
end;
$$;

-- Decision of the agent (L’Expert) or for the seller (p_decision: accept,
-- refuse; p_reason as in respond_visit_request).
create function public.staff_respond_visit_request(
  p_request_id uuid,
  p_decision text,
  p_reason text default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.staff_visit_request(p_request_id);
  perform public.visit_decide(v_request, p_decision, p_reason);
  select * into v_request from public.visit_requests where id = p_request_id;
  perform public.visit_notify(
    v_request, 'visit_updated',
    case when p_decision = 'accept' then 'Visite confirmée par votre agent'
      else 'Demande de visite refusée par votre agent' end,
    public.visit_request_summary(v_request)
  );
  perform public._staff_log(
    'visit_request_' || p_decision, public.visit_request_property(v_request),
    'visit_request', p_request_id::text,
    jsonb_build_object('reason', p_reason)
  );
end;
$$;

-- Cancellation by the buyer or the agent (p_cancelled_by: buyer, agent).
create function public.staff_cancel_visit(
  p_request_id uuid,
  p_cancelled_by text,
  p_reason text default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.staff_visit_request(p_request_id);
  if p_cancelled_by not in ('buyer', 'agent') then
    raise exception 'p_cancelled_by must be buyer or agent' using errcode = '22023';
  end if;
  if v_request.status not in ('pending', 'accepted') then
    raise exception 'request_not_open' using errcode = 'P0001';
  end if;
  update public.visit_requests
  set status = 'cancelled', cancelled_by = p_cancelled_by, cancelled_at = now(),
    status_reason = coalesce(p_reason, 'other'), buyer_informed_at = now()
  where id = p_request_id
  returning * into v_request;
  perform public.visit_notify(
    v_request, 'visit_cancelled',
    case when p_cancelled_by = 'buyer' then 'Visite annulée par l’acquéreur'
      else 'Visite annulée par votre agent' end,
    public.visit_request_summary(v_request)
  );
  perform public._staff_log(
    'visit_cancelled', public.visit_request_property(v_request),
    'visit_request', p_request_id::text,
    jsonb_build_object('cancelled_by', p_cancelled_by, 'reason', p_reason)
  );
end;
$$;

-- Outcome of a visit that took place (p_outcome: done, no_show).
create function public.staff_set_visit_outcome(p_request_id uuid, p_outcome text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.staff_visit_request(p_request_id);
  if p_outcome not in ('done', 'no_show') then
    raise exception 'p_outcome must be done or no_show' using errcode = '22023';
  end if;
  if v_request.status not in ('accepted', 'done', 'no_show') then
    raise exception 'request_not_accepted' using errcode = 'P0001';
  end if;
  update public.visit_requests
  set status = p_outcome, done_at = coalesce(done_at, now())
  where id = p_request_id;
  perform public._staff_log(
    'visit_outcome', public.visit_request_property(v_request),
    'visit_request', p_request_id::text, jsonb_build_object('outcome', p_outcome)
  );
end;
$$;

-- The team told the buyer about the last decision (runbook « à prévenir »).
create function public.staff_mark_buyer_informed(p_request_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_request public.visit_requests;
begin
  v_request := public.staff_visit_request(p_request_id);
  update public.visit_requests set buyer_informed_at = now()
  where id = p_request_id;
  perform public._staff_log(
    'visit_buyer_informed', public.visit_request_property(v_request),
    'visit_request', p_request_id::text
  );
end;
$$;

-- Creates or replaces the report of a visit and publishes it. p_report:
-- {author_kind: agent|team, author_label, agency_label?, interest_level?:
-- low|medium|high, liked?: [..], concerns?: [..], next_steps?: [contre_visite,
-- offre_annoncee, reflexion, pas_interesse], comment?, source?: staff|agency|demo}.
create function public.staff_publish_visit_report(
  p_visit_request_id uuid,
  p_report jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_request public.visit_requests;
  v_id uuid;
  v_key text;
begin
  v_request := public.staff_visit_request(p_visit_request_id);
  if v_request.status not in ('accepted', 'done') then
    raise exception 'request_not_done' using errcode = 'P0001';
  end if;
  for v_key in select jsonb_object_keys(p_report) loop
    if v_key not in (
      'author_kind', 'author_label', 'agency_label', 'interest_level', 'liked',
      'concerns', 'next_steps', 'comment', 'source'
    ) then
      raise exception 'Unknown report key %', v_key using errcode = '22023';
    end if;
  end loop;
  insert into public.visit_reports (
    visit_request_id, sale_id, owner_id, author_kind, author_label,
    agency_label, interest_level, liked, concerns, next_steps, comment,
    published_at, source
  ) values (
    v_request.id, v_request.sale_id, v_request.owner_id,
    coalesce(p_report ->> 'author_kind', 'team'),
    coalesce(p_report ->> 'author_label', 'Équipe Realesty'),
    p_report ->> 'agency_label',
    p_report ->> 'interest_level',
    coalesce(array(select jsonb_array_elements_text(p_report -> 'liked')), '{}'),
    coalesce(array(select jsonb_array_elements_text(p_report -> 'concerns')), '{}'),
    coalesce(array(select jsonb_array_elements_text(p_report -> 'next_steps')), '{}'),
    p_report ->> 'comment',
    now(),
    coalesce(p_report ->> 'source', 'staff')
  )
  on conflict (visit_request_id) do update set
    author_kind = excluded.author_kind, author_label = excluded.author_label,
    agency_label = excluded.agency_label,
    interest_level = excluded.interest_level, liked = excluded.liked,
    concerns = excluded.concerns, next_steps = excluded.next_steps,
    comment = excluded.comment, published_at = excluded.published_at,
    source = excluded.source
  returning id into v_id;
  if exists (
    select 1 from public.visit_reports r, unnest(r.liked || r.concerns) t
    where r.id = v_id and (char_length(t) not between 1 and 120)
  ) then
    raise exception 'Report items must be 1 to 120 characters' using errcode = '22023';
  end if;
  perform public.visit_notify(
    v_request, 'visit_report_published', 'Compte rendu de visite disponible',
    public.visit_request_summary(v_request), 'compte-rendu'
  );
  perform public._staff_log(
    'visit_report_published', public.visit_request_property(v_request),
    'visit_report', v_id::text
  );
  return v_id;
end;
$$;

-- Demo (plan Q13): the three requests of the mockup on the next open slots
-- of a TEST sale (or the next days at 10:00, 11:00, 14:00 when fewer slots
-- are open), plus one past visit with its published report. source = demo.
create function public.staff_seed_demo_visits(p_sale_id uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_sale public.sales;
  v_slots timestamptz[];
  v_day date := (public.visit_notice_start() at time zone 'Europe/Paris')::date + 1;
  v_past timestamptz;
  v_id uuid;
  v_profiles jsonb := jsonb_build_array(
    jsonb_build_object('label', 'Thomas & Léa B.', 'initials', 'TL', 'score', 94,
      'flags', jsonb_build_object('pass_visite', true, 'budget_validated', true,
        'search_mandate_signed', true, 'requalification', 'done'),
      'snapshot', jsonb_build_object('v', 1, 'household', 'Couple, 1 enfant',
        'financing', 'Validé par le courtier', 'capacity', 'Compatible avec votre prix',
        'timeline', 'Achat sous 3 mois',
        'subscores', jsonb_build_array(
          jsonb_build_object('label', 'Intérieur', 'score', 33, 'max', 35),
          jsonb_build_object('label', 'Extérieur & trajets', 'score', 32, 'max', 35),
          jsonb_build_object('label', 'Financement', 'score', 29, 'max', 30)),
        'reasons', jsonb_build_array('Garage avec coin atelier pour la moto',
          'École primaire à pied pour leur fille de 6 ans',
          'Bureau fermé pour 3 jours de télétravail'))),
    jsonb_build_object('label', 'Nadia K.', 'initials', 'NK', 'score', 88,
      'flags', jsonb_build_object('pass_visite', true, 'budget_validated', true,
        'search_mandate_signed', true),
      'snapshot', jsonb_build_object('v', 1, 'household', 'Seule',
        'financing', 'Apport personnel et prêt en cours',
        'capacity', 'Compatible avec votre prix', 'timeline', 'Achat sous 6 mois',
        'subscores', jsonb_build_array(
          jsonb_build_object('label', 'Intérieur', 'score', 31, 'max', 35),
          jsonb_build_object('label', 'Extérieur & trajets', 'score', 30, 'max', 35),
          jsonb_build_object('label', 'Financement', 'score', 27, 'max', 30)),
        'reasons', jsonb_build_array('Séjour lumineux exposé sud',
          'Gare à moins de dix minutes'))),
    jsonb_build_object('label', 'Paul & Inès R.', 'initials', 'PR', 'score', 81,
      'flags', jsonb_build_object('pass_visite', true, 'budget_validated', true),
      'snapshot', jsonb_build_object('v', 1, 'household', 'Couple',
        'financing', 'Accord de principe bancaire',
        'capacity', 'En haut de leur budget', 'timeline', 'Achat sous 4 mois',
        'subscores', jsonb_build_array(
          jsonb_build_object('label', 'Intérieur', 'score', 28, 'max', 35),
          jsonb_build_object('label', 'Extérieur & trajets', 'score', 29, 'max', 35),
          jsonb_build_object('label', 'Financement', 'score', 24, 'max', 30)),
        'reasons', jsonb_build_array('Jardin pour leurs deux chiens')))
  );
  v_profile jsonb;
  v_count integer := 0;
begin
  select * into v_sale from public.sales where id = p_sale_id;
  if v_sale.id is null or not v_sale.is_test then
    raise exception 'Test sale % not found', p_sale_id using errcode = 'P0002';
  end if;
  -- The next open slots, from the notice to the horizon.
  select array_agg(s order by s) into v_slots
  from (
    select c.s from (
      select ((d::date + make_time(h, 0, 0)) at time zone 'Europe/Paris') as s
      from generate_series(v_day::timestamp, v_day::timestamp + interval '41 days',
        interval '1 day') d,
        generate_series(
          (public.visit_settings_defaults() ->> 'first_hour')::int,
          (public.visit_settings_defaults() ->> 'end_hour')::int - 1) h
    ) c
    where c.s < public.visit_horizon_end()
      and public.visit_slot_is_open(v_sale, c.s)
      and not exists (
        select 1 from public.visit_requests r
        where r.owner_id = v_sale.owner_id and r.slot_starts_at = c.s
          and r.status = 'accepted')
    order by c.s
    limit 3
  ) t;
  v_slots := coalesce(v_slots, '{}');
  while cardinality(v_slots) < 3 loop
    v_slots := v_slots || ((v_day + 1 + cardinality(v_slots))
      + make_time((array[10, 11, 14])[cardinality(v_slots) + 1], 0, 0))
      at time zone 'Europe/Paris';
  end loop;
  for i in 1..3 loop
    v_profile := v_profiles -> (i - 1);
    perform public.staff_create_visit_request(
      p_sale_id, v_slots[i], v_profile ->> 'label', v_profile ->> 'initials',
      'demo', v_profile -> 'flags', (v_profile ->> 'score')::int,
      v_profile -> 'snapshot', 'pending', true
    );
    v_count := v_count + 1;
  end loop;
  -- One past visit, done, with its report (V14).
  v_past := (((now() at time zone 'Europe/Paris')::date - 3) + time '10:00')
    at time zone 'Europe/Paris';
  v_id := gen_random_uuid();
  insert into public.visit_requests (
    id, sale_id, owner_id, buyer_label, buyer_initials, slot_starts_at,
    duration_min, status, handled_by, pass_visite, budget_validated,
    compatibility_score, buyer_snapshot, source, is_test, responded_at, done_at,
    buyer_informed_at
  ) values (
    v_id, v_sale.id, v_sale.owner_id, 'Julien & Sarah D.', 'JS', v_past,
    v_sale.visit_duration_min, 'done',
    case when v_sale.formula = 'expert' then 'agent' else 'seller' end,
    true, true, 86,
    jsonb_build_object('v', 1, 'household', 'Couple, 2 enfants',
      'financing', 'Validé par le courtier', 'timeline', 'Achat sous 3 mois'),
    'demo', true, now() - interval '5 days', v_past + interval '1 hour', now()
  );
  perform public.staff_publish_visit_report(v_id, jsonb_build_object(
    'author_kind', 'agent', 'author_label', 'Camille, agence partenaire',
    'agency_label', 'Agence Val d’Yzeron', 'interest_level', 'high',
    'liked', jsonb_build_array('Luminosité du séjour', 'Garage atelier',
      'Calme de l’impasse', 'Jardin clos'),
    'concerns', jsonb_build_array(
      'Salle de bain à rafraîchir (budget travaux estimé en visite)',
      'Léger vis-à-vis depuis la terrasse'),
    'next_steps', jsonb_build_array('contre_visite', 'offre_annoncee'),
    'comment', 'Les acquéreurs souhaitent une contre-visite en semaine et '
      || 'envisagent une offre.',
    'source', 'demo'
  ));
  return v_count + 1;
end;
$$;

-- Deletes the demo rows of the sale (requests, their reports, notes and
-- notifications). Returns the number of requests deleted.
create function public.staff_purge_demo_visits(p_sale_id uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_ids from public.visit_requests
  where sale_id = p_sale_id and source = 'demo';
  delete from public.notifications n
  using unnest(v_ids) i
  where n.route like '/vendeur/visites/demandes/' || i::text || '%';
  delete from public.visit_requests where id = any (v_ids);
  perform public._staff_log(
    'visit_demo_purged', null, 'sale', p_sale_id::text,
    jsonb_build_object('count', cardinality(v_ids))
  );
  return cardinality(v_ids);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Housekeeping (hourly pg_cron job, also runnable from the SQL editor)
-- ---------------------------------------------------------------------------

-- Pending requests whose slot passed → expired; accepted visits over → done;
-- old exceptions deleted; from reminder_hour (Paris), reminder of tomorrow's
-- accepted visits (once, reminded_at).
create function public.visits_housekeeping()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expired integer;
  v_done integer;
  v_reminded integer := 0;
  v_request public.visit_requests;
  v_local timestamp := now() at time zone 'Europe/Paris';
begin
  update public.visit_requests set status = 'expired'
  where status = 'pending' and slot_starts_at <= now();
  get diagnostics v_expired = row_count;
  update public.visit_requests set status = 'done', done_at = now()
  where status = 'accepted'
    and slot_starts_at + make_interval(mins => duration_min) <= now();
  get diagnostics v_done = row_count;
  delete from public.visit_slot_overrides where starts_at < now() - interval '1 day';
  if extract(hour from v_local)
    >= (public.visit_settings_defaults() ->> 'reminder_hour')::int then
    for v_request in
      update public.visit_requests set reminded_at = now()
      where status = 'accepted' and reminded_at is null
        and (slot_starts_at at time zone 'Europe/Paris')::date = v_local::date + 1
      returning *
    loop
      perform public.visit_notify(
        v_request, 'visit_reminder', 'Visite demain',
        public.visit_request_summary(v_request)
      );
      v_reminded := v_reminded + 1;
    end loop;
  end if;
  return jsonb_build_object(
    'expired', v_expired, 'done', v_done, 'reminded', v_reminded
  );
end;
$$;

do $$
declare
  v_function text;
begin
  foreach v_function in array array[
    'public.staff_visit_request(uuid)',
    'public.visit_request_summary(public.visit_requests)',
    'public.visit_request_property(public.visit_requests)',
    'public.visit_apply_flags(uuid, jsonb)',
    'public.staff_create_visit_request(uuid, timestamptz, text, text, text, jsonb, integer, jsonb, text, boolean, uuid)',
    'public.staff_requalify_visit_request(uuid, jsonb)',
    'public.staff_respond_visit_request(uuid, text, text)',
    'public.staff_cancel_visit(uuid, text, text)',
    'public.staff_set_visit_outcome(uuid, text)',
    'public.staff_mark_buyer_informed(uuid)',
    'public.staff_publish_visit_report(uuid, jsonb)',
    'public.staff_seed_demo_visits(uuid)',
    'public.staff_purge_demo_visits(uuid)',
    'public.visits_housekeeping()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated',
      v_function);
    execute format('grant execute on function %s to service_role', v_function);
  end loop;
end;
$$;

select cron.schedule(
  'visits-housekeeping',
  '7 * * * *',
  'select public.visits_housekeeping()'
);
