-- EPIC-16 · fill sheet fixes (review): a source that is not one of the
-- known values is shown « invalide » and never verified; a value said
-- (dicte, dicte_autre_etape) without its turn or pending answer is « à
-- vérifier »; a value linked to a pending answer but not confirmed yet (a
-- room written for its photos before « Continuer ») is not shown as
-- confirmed; a pending note shows its step and its text.
-- `create or replace` keeps the grants (service role only), restated below.

create or replace function public.staff_fill_sheet(p_property_id uuid)
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
    case
      when v.src is null then coalesce(v.legacy, 'non_trace')
      when v.src ->> 's' in (
        'dicte', 'dicte_autre_etape', 'saisi', 'extrait', 'externe'
      ) then v.src ->> 's'
      -- Not a known source (forged or broken entry).
      else 'invalide'
    end,
    coalesce(ev.q, pa.quote),
    coalesce(t.id, pa.turn_id),
    coalesce(t.created_at, pt.created_at),
    case
      when v.src ->> 'at' ~ '^\d{4}-\d{2}-\d{2}T' then (v.src ->> 'at')::timestamptz
    end,
    -- Linked to a pending answer but not confirmed yet (a room written for
    -- its photos before « Continuer »).
    not coalesce(v.src ? 'p' and v.src ->> 'c' is null, false),
    case when v.src ? 'p' then coalesce(v.src ->> 'c', pa.status) end,
    case
      when v.src is null then null
      when coalesce(v.src ->> 's', '') not in (
        'dicte', 'dicte_autre_etape', 'saisi', 'extrait', 'externe'
      ) then false
      when v.src ? 'p' then coalesce(pa.status = 'accepted', false)
        and public.voice_value_matches(
          case when pa.kind = 'field' then pa.value else pa.value -> v.field end,
          v.v
        )
      when v.src ? 't' then t.id is not null
        and public.voice_value_matches(ev.v, v.v)
      -- Said, but neither its turn nor its pending answer is given.
      when v.src ->> 's' in ('dicte', 'dicte_autre_etape') then false
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
    case pa.kind
      when 'field' then pa.field
      when 'note' then pa.target_step
      else pa.kind
    end,
    coalesce(c.label_fr, pa.label_fr),
    case when pa.kind = 'note' then pa.value #>> '{}' else pa.label_fr end,
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
  left join catalog c
    on (pa.kind = 'field' and c.entity = 'property' and c.field = pa.field)
    or (pa.kind = 'note' and c.entity = 'note' and c.field = pa.target_step)
  left join turns pt on pt.id = pa.turn_id
  where pa.property_id = p_property_id and pa.status <> 'accepted'
  order by 16, 4, 5;
$$;

revoke execute on function public.staff_fill_sheet(uuid)
  from public, anon, authenticated;
grant execute on function public.staff_fill_sheet(uuid) to service_role;
