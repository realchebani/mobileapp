-- EPIC-14 · Voice on every step of the seller tunnel
-- (docs/plans/2026-10-02-voix-etendue.md §6.1). Additive only: the
-- agent_conversations migration (EPIC-06) is already applied, so its step
-- constraint is replaced here.

-- V5c · free description of a room (dictated or typed), and the rooms
-- dictated to the voice agent. `rooms` keeps its table-level grant (select,
-- insert, update, delete), which covers the new column; the lock (RLS,
-- draft / submitted only) already applies.
alter table public.rooms
  add column description text check (char_length(description) <= 300),
  drop constraint rooms_source_check,
  add constraint rooms_source_check
    check (source in ('scan', 'plan', 'manual', 'voice'));

comment on column public.rooms.description is
  'V5c · free description of the room (≤ 300 characters), typed or dictated.';

-- Voice agent · one active session per (property, step) for every voiced
-- step of the tunnel.
alter table public.agent_sessions
  drop constraint agent_sessions_step_check,
  add constraint agent_sessions_step_check check (step in (
    'owners', 'location', 'context', 'technical', 'rooms', 'lifestyle'
  ));

-- Quality follow-up: turns the seller undid ("Annuler" on a pill, on the
-- turn or on the whole sheet). Written by agent-turn with the service role,
-- like the rest of the journal (clients keep a read-only access).
alter table public.agent_turns
  add column undone boolean not null default false;

-- Cost and quality per step × agent model × week (plan §7.4), for the
-- re-evaluation of the models. Read by the team with the service role only
-- (SQL editor, runbook docs/runbooks/suivi-voix.md).
create view public.agent_step_stats
with (security_invoker = true) as
with turns as (
  select
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
  coalesce(r.rejected_by_reason, '{}'::jsonb) as rejected_by_reason
from turns t
left join reasons r
  on r.step = t.step and r.model = t.model and r.week = t.week
group by t.step, t.model, t.week, r.rejected_by_reason;

comment on view public.agent_step_stats is
  'EPIC-14 · voice agent cost and quality per step, agent model and week '
  '(service role only).';

revoke all on table public.agent_step_stats from public, anon, authenticated;
grant select on table public.agent_step_stats to service_role;
