-- EPIC-06 · Voice agent: conversation sessions and turns (journal, quotas).
-- Clients can only READ their own rows. Every write is made by the Edge
-- Functions agent-transcribe / agent-turn / agent-speech with the service
-- role, after checking with the CALLER's JWT (RLS) that the property is
-- theirs and still a draft: the journal backs the quotas and the costs, so
-- the app cannot alter it. The audio itself is never stored. Nothing here
-- changes `properties`.

create table public.agent_sessions (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  step text not null check (step in ('technical', 'lifestyle')),
  status text not null default 'active'
    check (status in ('active', 'done', 'abandoned')),
  next_field text check (char_length(next_field) <= 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index agent_sessions_property_step
  on public.agent_sessions (property_id, step, status);
create unique index agent_sessions_one_active
  on public.agent_sessions (property_id, step)
  where status = 'active';

create trigger agent_sessions_set_updated_at
  before update on public.agent_sessions
  for each row execute function public.seller_tunnel_set_updated_at();

create table public.agent_turns (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.agent_sessions (id)
    on delete cascade,
  owner_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  transcript text not null check (char_length(transcript) <= 2000),
  audio_seconds numeric(6, 2) check (audio_seconds >= 0),
  reply_fr text check (char_length(reply_fr) <= 600),
  -- Validated and rejected answers (with reasons).
  extracted jsonb,
  stt_model text check (char_length(stt_model) <= 100),
  agent_model text check (char_length(agent_model) <= 100),
  tts_model text check (char_length(tts_model) <= 100),
  tokens_in integer,
  tokens_out integer,
  stt_ms integer,
  agent_ms integer,
  tts_ms integer,
  -- Sum of the OpenRouter usage.cost of the STT, agent and TTS calls.
  cost_usd numeric(8, 5),
  error text check (char_length(error) <= 500),
  created_at timestamptz not null default now()
);

create index agent_turns_session on public.agent_turns (session_id, created_at);
create index agent_turns_owner_day on public.agent_turns (owner_id, created_at);

-- RLS ---------------------------------------------------------------------------

alter table public.agent_sessions enable row level security;
alter table public.agent_turns enable row level security;

create policy "Owners can view their agent sessions"
  on public.agent_sessions for select
  to authenticated
  using (owner_id = (select auth.uid()));

create policy "Owners can view their agent turns"
  on public.agent_turns for select
  to authenticated
  using (owner_id = (select auth.uid()));

-- No insert / update / delete policy: writes go through the service role.

-- Grants: read only for the signed-in users.
revoke all on table public.agent_sessions, public.agent_turns
  from anon, authenticated;
grant select on table public.agent_sessions, public.agent_turns
  to authenticated;
